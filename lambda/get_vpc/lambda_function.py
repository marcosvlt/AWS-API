import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ.get('TABLE_NAME', 'VpcResources')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    vpc_id = event.get('pathParameters', {}).get('id')

    if vpc_id:
        # GET /vpcs/{id}
        resp = table.get_item(Key={'vpcId': vpc_id})
        item = resp.get('Item')
        if not item:
            return {
                'statusCode': 404,
                'body': json.dumps({'message': 'VPC not found'})
            }
        return {
            'statusCode': 200,
            'body': json.dumps(item)
        }

    # GET /vpcs  (list)
    scan_resp = table.scan()
    items = scan_resp.get('Items', [])
    return {
        'statusCode': 200,
        'body': json.dumps(items)
    }
