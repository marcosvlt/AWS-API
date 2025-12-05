#################################
# Dynamo DB Table for VPC Resources
#################################

resource "aws_dynamodb_table" "vpc_resources" {
  name         = "VpcResources"
  billing_mode = "PAY_PER_REQUEST" # on-demand capacity

  hash_key = "vpcId"

  attribute {
    name = "vpcId"
    type = "S"
  }

  tags = {
    Name = "VpcResources"
    Environment = "MVP"
  }
}


#################################
# IAM Role & Policies for Lambdas
#################################
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "lambda_vpc_creator_role_mvp"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Minimal inline policy for EC2, DynamoDB and Logs (MVP)
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid     = "AllowEC2Actions"
    effect  = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:DescribeAvailabilityZones",
      "ec2:ModifyVpcAttribute",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets"
    ]
    resources = ["*"]
  }

  statement {
    sid     = "AllowDynamoDB"
    effect  = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query"
    ]
    resources = [aws_dynamodb_table.vpc_resources.arn]
  }

  statement {
    sid     = "AllowCloudWatchLogs"
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy_attach" {
  name   = "lambda_vpc_creator_policy_mvp"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

#################################
# Lambda functions (local zip files)
#################################
# Package the Lambda function code
data "archive_file" "create_vpc" {
  type        = "zip"
  source_file = "lambda/create_vpc/lambda_function.py"
  output_path = "lambda/create_vpc/create_vpc.zip"
}

data "archive_file" "get_vpc" {
  type        = "zip"
  source_file = "lambda/get_vpc/lambda_function.py"
  output_path = "lambda/get_vpc/get_vpc.zip"
}


resource "aws_lambda_function" "create_vpc" {
  filename         = var.lambda_create_zip       
  function_name    = "create_vpc_mvp"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256(var.lambda_create_zip)

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.vpc_resources.name
    }
  }
}

resource "aws_lambda_function" "get_vpc" {
  filename         = var.lambda_get_zip
  function_name    = "get_vpc_mvp"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256(var.lambda_get_zip)

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.vpc_resources.name
    }
  }
}


#################################
# Cognito User Pool + App Client
#################################
resource "aws_cognito_user_pool" "user_pool" {
  name = "CreateApiUsers"
  # default settings for MVP
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "CreateApiClient"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret     = false
  prevent_user_existence_errors = "ENABLED"
}

#################################
# API Gateway v2 (HTTP API) + JWT Authorizer (Cognito)
#################################
resource "aws_apigatewayv2_api" "http_api" {
  name          = "vpc-api-mvp"
  protocol_type = "HTTP"
}

# JWT authorizer pointing to Cognito
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id = aws_apigatewayv2_api.http_api.id
  name   = "CognitoJWT"

  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.user_pool.id}"
    audience = [aws_cognito_user_pool_client.app_client.id]
  }
}

# Integrations: Lambda
resource "aws_apigatewayv2_integration" "create_vpc_integration" {
  api_id = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_vpc.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "get_vpc_integration" {
  api_id = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_vpc.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# Routes
resource "aws_apigatewayv2_route" "post_vpcs" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /vpcs"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.cognito_jwt.id
  target    = "integrations/${aws_apigatewayv2_integration.create_vpc_integration.id}"
}

resource "aws_apigatewayv2_route" "get_vpcs" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /vpcs"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.cognito_jwt.id
  target    = "integrations/${aws_apigatewayv2_integration.get_vpc_integration.id}"
}

resource "aws_apigatewayv2_route" "get_vpc_id" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /vpcs/{id}"
  authorization_type = "JWT"
  authorizer_id = aws_apigatewayv2_authorizer.cognito_jwt.id
  target    = "integrations/${aws_apigatewayv2_integration.get_vpc_integration.id}"
}

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.http_api.id
  name   = "$default"
  auto_deploy = true
}

# Permissions so API Gateway can invoke Lambdas
resource "aws_lambda_permission" "allow_apigw_create" {
  statement_id  = "AllowExecutionFromAPIGatewayCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_vpc.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigw_get" {
  statement_id  = "AllowExecutionFromAPIGatewayGet"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_vpc.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
#################################
# END OF FILE
#################################
