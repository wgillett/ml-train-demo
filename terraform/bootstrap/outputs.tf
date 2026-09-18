output "iam_user_name" {
  description = "Personal IAM user for local AWS CLI/Terraform use"
  value       = aws_iam_user.bootstrap.name
}

output "ecr_repository_url" {
  description = "Push/pull URL for the training image"
  value       = aws_ecr_repository.training_image.repository_url
}

output "github_oidc_provider_arn" {
  description = "OIDC provider ARN to reference when creating the GitHub Actions IAM role"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_actions_role_arn" {
  description = "Role ARN for the CI workflow to assume via aws-actions/configure-aws-credentials"
  value       = aws_iam_role.github_actions.arn
}
