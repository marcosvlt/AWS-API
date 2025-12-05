import json
import os
from datetime import datetime
import boto3

dynamodb = boto3.resource("dynamodb")
ec2 = boto3.client("ec2")

TABLE_NAME = os.environ.get("TABLE_NAME", "VpcResources")
table = dynamodb.Table(TABLE_NAME)


def parse_body(event):
    """
    Handles:
    - API Gateway proxy event → event["body"] is a JSON string
    - Lambda test event → event is already the payload itself
    - Missing body → {}
    """
    if "body" in event:
        body_raw = event.get("body") or "{}"
        if isinstance(body_raw, str):
            try:
                return json.loads(body_raw)
            except json.JSONDecodeError:
                return {}
        return body_raw
    else:
        # Lambda test payload passes JSON directly
        return event


def lambda_handler(event, context):
    print("Received event:", json.dumps(event))

    body = parse_body(event)

    cidr_block = body.get("cidrBlock", "10.0.0.0/16")
    requested_subnets = body.get("subnets", [])

    # Validate subnet list
    if not isinstance(requested_subnets, list):
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "'subnets' must be a list"})
        }

    # ---- CREATE VPC ----
    vpc_response = ec2.create_vpc(CidrBlock=cidr_block)
    vpc_id = vpc_response["Vpc"]["VpcId"]
    

    # ---- CREATE SUBNETS ----
    subnets = []

    for subnet in requested_subnets:
        cidr = subnet.get("cidrBlock")
        az = subnet.get("az")

        if not cidr or not az:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Each subnet must include cidrBlock and az"})
            }

        created = ec2.create_subnet(
            VpcId=vpc_id,
            CidrBlock=cidr,
            AvailabilityZone=az
        )["Subnet"]

        subnet_id = created["SubnetId"]

        ec2.create_tags(
            Resources=[subnet_id],
            Tags=[{"Key": "Name", "Value": f"Subnet-{cidr}"}]
        )

        subnets.append({
            "subnetId": subnet_id,
            "cidrBlock": cidr,
            "az": az
        })

    # ---- SAVE TO DYNAMODB ----
    item = {
        "vpcId": vpc_id,
        "cidrBlock": cidr_block,
        "subnets": subnets,
        "createdAt": datetime.utcnow().isoformat() + "Z",
    }

    table.put_item(Item=item)

    # ---- RETURN SUCCESS ----
    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(item)
    }
