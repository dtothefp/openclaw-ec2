output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.openclaw.id
}

output "elastic_ip" {
  description = "Elastic IP address of the instance"
  value       = aws_eip.openclaw.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -p ${var.ssh_port} -i your-key.pem ${var.openclaw_user}@${aws_eip.openclaw.public_ip}"
}

output "dashboard_tunnel_command" {
  description = "SSH tunnel command to access the OpenClaw dashboard"
  value       = "ssh -p ${var.ssh_port} -i your-key.pem -L 18789:localhost:18789 ${var.openclaw_user}@${aws_eip.openclaw.public_ip}"
}
