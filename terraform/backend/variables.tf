variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-west-2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state (must be globally unique)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in 'owner/repo' format (e.g. 'davidfox-powell/openclaw')"
  type        = string
}
