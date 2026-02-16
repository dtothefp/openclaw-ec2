output "state_bucket_name" {
  description = "Name of the S3 bucket storing Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket storing Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions -- add this as PRODUCTION_GITHUB_ACTIONS_ROLE_ARN secret in your GitHub repo"
  value       = aws_iam_role.github_actions.arn
}
