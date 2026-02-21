variable "project_name" {
  description = "Project name used for resource tagging"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (t3.medium recommended: 2 vCPU, 4GB RAM)"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "ID of the subnet to launch the instance in"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group to attach"
  type        = string
}

variable "key_pair_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 30
}

variable "ssh_port" {
  description = "Custom SSH port configured on the instance"
  type        = number
  default     = 2222
}

variable "openclaw_user" {
  description = "Username for the dedicated OpenClaw Linux user"
  type        = string
  default     = "openclaw"
}

variable "install_tailscale" {
  description = "Whether to install Tailscale on the instance"
  type        = bool
  default     = false
}

variable "use_native_install" {
  description = "Use native Node.js install instead of Docker"
  type        = bool
  default     = false
}
