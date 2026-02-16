output "instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "elastic_ip" {
  description = "Elastic IP of the OpenClaw instance"
  value       = module.compute.elastic_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = module.compute.ssh_command
}

output "dashboard_tunnel_command" {
  description = "SSH tunnel command to access OpenClaw dashboard locally"
  value       = module.compute.dashboard_tunnel_command
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
