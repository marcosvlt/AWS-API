#################################
# Terraform outputs
#################################

output "vpc_resources_table_name" {
  description = "DynamoDB table name for VPC resources"
  value       = aws_dynamodb_table.vpc_resources.name
}

output "vpc_resources_table_arn" {
  description = "DynamoDB table ARN for VPC resources"
  value       = aws_dynamodb_table.vpc_resources.arn
}

output "lambda_role_name" {
  description = "IAM role name for Lambda execution"
  value       = aws_iam_role.lambda_exec.name
}

output "lambda_role_arn" {
  description = "IAM role ARN for Lambda execution"
  value       = aws_iam_role.lambda_exec.arn
}

output "lambda_policy_attachment_id" {
  description = "ID of the inline role policy attached to the Lambda role"
  value       = aws_iam_role_policy.lambda_policy_attach.id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

