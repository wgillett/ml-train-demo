variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "iam_user_name" {
  description = "Name of the personal IAM user for local AWS CLI/Terraform use"
  type        = string
  default     = "ml-train-demo-admin"
}

variable "resource_prefix" {
  description = "Prefix used to scope the custom IAM policy's role/policy resource ARNs"
  type        = string
  default     = "ml-train-demo"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for the training image"
  type        = string
  default     = "ml-train-demo"
}
