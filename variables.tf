variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy to"
}

variable "lambda_create_zip" {
  type        = string
  description = "Path to the zipped Lambda function for creating VPCs"
  default     = "lambda/create_vpc/create_vpc.zip"
  
}

variable "lambda_get_zip" {
  type        = string
  description = "Path to the zipped Lambda function for getting VPCs"
  default     = "lambda/get_vpc/get_vpc.zip"
}