output "security_group_id" {
  description = "ID of the OpenClaw security group"
  value       = aws_security_group.openclaw.id
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.openclaw_ec2.name
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.openclaw.key_name
}
