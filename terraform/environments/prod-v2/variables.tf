variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "openclaw"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "AWS availability zone"
  type        = string
  default     = "us-west-2a"
}

variable "ssh_port" {
  description = "Custom SSH port"
  type        = number
  default     = 2222
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (e.g. your home IP as [\"1.2.3.4/32\"])"
  type        = list(string)
}

variable "ssh_public_key" {
  description = "Your SSH public key content (e.g. contents of ~/.ssh/id_ed25519.pub)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "openclaw_user" {
  description = "Linux user for OpenClaw"
  type        = string
  default     = "openclaw"
}

variable "install_tailscale" {
  description = "Install Tailscale for secure private networking"
  type        = bool
  default     = false
}

variable "enable_ssm" {
  description = "Enable AWS SSM for backup instance management"
  type        = bool
  default     = false
}
