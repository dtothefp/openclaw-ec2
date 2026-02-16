variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to create the security group in"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port (non-standard to reduce bot scanning)"
  type        = number
  default     = 2222
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH into the instance"
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Public SSH key to authorize for EC2 access"
  type        = string
}

variable "enable_ssm" {
  description = "Enable AWS Systems Manager access as a backup management channel"
  type        = bool
  default     = false
}
