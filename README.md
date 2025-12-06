# AWS-API (MVP)

Small Terraform + Lambda project that provides an HTTP API to create and list VPCs, backed by DynamoDB and secured with Cognito.

---

## Repo layout

- [main.tf](main.tf) — Terraform resources (DynamoDB, IAM, Lambda, Cognito, API Gateway)
- [provider.tf](provider.tf) — provider configuration
- [variables.tf](variables.tf) — variable declarations
- [versions.tf](versions.tf) — required Terraform version
- [output.tf](output.tf) — Terraform outputs
- [testing-example.http](testing-example.http) — example HTTP requests for the API and Cognito
- [cognito.sh](cognito.sh) — helper script to create a Cognito user
- [.gitignore](.gitignore)
- [LICENSE](LICENSE)
- lambda/
  - [lambda/create_vpc/lambda_function.py](lambda/create_vpc/lambda_function.py)
  - [lambda/get_vpc/lambda_function.py](lambda/get_vpc/lambda_function.py)

(Links above point to files in this workspace.)

---

## What this does

- Creates a DynamoDB table `VpcResources` to store created VPC metadata.
  - Terraform resource: [`aws_dynamodb_table.vpc_resources`](main.tf).
- Deploys two Lambda functions:
  - Create VPC: [`aws_lambda_function.create_vpc`](main.tf) — code at [lambda/create_vpc/lambda_function.py](lambda/create_vpc/lambda_function.py), handler [`lambda.create_vpc.lambda_handler`](lambda/create_vpc/lambda_function.py), helper [`lambda.create_vpc.parse_body`](lambda/create_vpc/lambda_function.py).
  - Get VPC(s): [`aws_lambda_function.get_vpc`](main.tf) — code at [lambda/get_vpc/lambda_function.py](lambda/get_vpc/lambda_function.py), handler [`lambda.get_vpc.lambda_handler`](lambda/get_vpc/lambda_function.py).
- Adds minimal IAM role/policy for Lambda: [`aws_iam_role.lambda_exec`](main.tf), [`aws_iam_role_policy.lambda_policy_attach`](main.tf).
- Creates Cognito user pool and client: [`aws_cognito_user_pool.user_pool`](main.tf), [`aws_cognito_user_pool_client.app_client`](main.tf).
- Creates an HTTP API (API Gateway v2) with a Cognito JWT authorizer: [`aws_apigatewayv2_api.http_api`](main.tf), [`aws_apigatewayv2_authorizer.cognito_jwt`](main.tf).
- Integrates API routes to Lambdas: [`aws_apigatewayv2_integration.create_vpc_integration`](main.tf), [`aws_apigatewayv2_integration.get_vpc_integration`](main.tf) and routes for:
  - POST /vpcs — [`aws_apigatewayv2_route.post_vpcs`](main.tf)
  - GET /vpcs — [`aws_apigatewayv2_route.get_vpcs`](main.tf)
  - GET /vpcs/{id} — [`aws_apigatewayv2_route.get_vpc_id`](main.tf)

---

## Lambda behavior (quick)

- Create VPC lambda ([lambda/create_vpc/lambda_function.py](lambda/create_vpc/lambda_function.py)):
  - Entry: [`lambda.create_vpc.lambda_handler`](lambda/create_vpc/lambda_function.py)
  - Accepts JSON body with `cidrBlock` and `subnets` array.
  - Creates VPC and subnets via EC2 SDK and stores metadata in DynamoDB table `VpcResources`.
  - `parse_body` handles API Gateway proxy or direct test payloads: [`lambda.create_vpc.parse_body`](lambda/create_vpc/lambda_function.py).

- Get VPC lambda ([lambda/get_vpc/lambda_function.py](lambda/get_vpc/lambda_function.py)):
  - Entry: [`lambda.get_vpc.lambda_handler`](lambda/get_vpc/lambda_function.py)
  - If path parameter `id` provided → returns single item from DynamoDB.
  - Otherwise → scans and returns all items.

---

## Deploy

1. Ensure AWS credentials are configured (environment or shared config).
2. Initialize and apply Terraform:

```sh
terraform init
terraform apply
```

3. Terraform will build local zip archives (data `archive_file`) for the Lambdas from:
   - [lambda/create_vpc/lambda_function.py](lambda/create_vpc/lambda_function.py)
   - [lambda/get_vpc/lambda_function.py](lambda/get_vpc/lambda_function.py)

Notes:
- Variables are declared in [variables.tf](variables.tf). Adjust `lambda_create_zip` / `lambda_get_zip` if you move zip files.
- Terraform provider config is in [provider.tf](provider.tf) and Terraform version in [versions.tf](versions.tf).
- Outputs (Cognito user pool id, DynamoDB table name, Lambda role ARN, region, etc.) are in [output.tf](output.tf).

---

## Testing

- Example HTTP requests (use your API endpoint & Cognito tokens): see [testing-example.http](testing-example.http).
- To create a Cognito user via helper script: [cognito.sh](cognito.sh)

Example: create a user
```sh
./cognito.sh -p <USER_POOL_ID> -e user@example.com
```

---


## Authentication and API usage

Use the file testing-example.http

1) Create a VPC (POST /vpcs)

Request (JSON body) — replace <API-URL> and add Authorization header:

```http
POST https://<API-URL>/vpcs
Content-Type: application/json
Authorization: Bearer <ACCESS_TOKEN>

{
  "cidrBlock": "10.3.0.0/16",
  "subnets": [
    {"cidrBlock": "10.3.0.0/24", "az": "us-east-1a"},
    {"cidrBlock": "10.3.1.0/24", "az": "us-east-1b"},
    {"cidrBlock": "10.3.2.0/24", "az": "us-east-1c"}
  ]
}
```

Example curl:

```sh
curl -s -X POST "https://<API-URL>/vpcs" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"cidrBlock":"10.3.0.0/16","subnets":[{"cidrBlock":"10.3.0.0/24","az":"us-east-1a"},{"cidrBlock":"10.3.1.0/24","az":"us-east-1b"},{"cidrBlock":"10.3.2.0/24","az":"us-east-1c"}]}'
```

2) List all VPCs (GET /vpcs)

```http
GET https://<API-URL>/vpcs
Authorization: Bearer <ACCESS_TOKEN>
```

Example curl:

```sh
curl -s "https://<API-URL>/vpcs" -H "Authorization: Bearer $ACCESS_TOKEN"
```

4) Get a single VPC (GET /vpcs/{id})

```http
GET https://<API-URL>/vpcs/<VPC-ID>
Authorization: Bearer <ACCESS_TOKEN>
```

Example curl:

```sh
curl -s "https://<API-URL>/vpcs/<VPC-ID>" -H "Authorization: Bearer $ACCESS_TOKEN"
```

Notes
- Use the helper script `./cognito.sh -p <USER_POOL_ID> -e <EMAIL>` to create users if needed.
- The easiest way to call Cognito management APIs is via the AWS CLI or an AWS SDK — raw HTTP calls must be signed (SigV4).
- If you cannot find the API URL, get it from the API Gateway console or run:
```sh
aws apigatewayv2 get-apis --region <AWS-REGION>
```