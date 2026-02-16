# --- Security Group ---

resource "aws_security_group" "openclaw" {
  name_prefix = "${var.project_name}-sg-"
  description = "Security group for OpenClaw EC2 instance"
  vpc_id      = var.vpc_id

  # SSH on custom port - restricted to allowed CIDRs
  ingress {
    description = "SSH on custom port"
    from_port   = var.ssh_port
    to_port     = var.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # All outbound traffic (required for API calls, WhatsApp, Telegram, Docker pulls)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- IAM Role for EC2 ---

resource "aws_iam_role" "openclaw_ec2" {
  name_prefix = "${var.project_name}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-ec2-role"
    Project = var.project_name
  }
}

# SSM access for emergency management without SSH
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = var.enable_ssm ? 1 : 0
  role       = aws_iam_role.openclaw_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "openclaw_ec2" {
  name_prefix = "${var.project_name}-ec2-"
  role        = aws_iam_role.openclaw_ec2.name

  tags = {
    Name    = "${var.project_name}-instance-profile"
    Project = var.project_name
  }
}

# --- Key Pair ---

resource "aws_key_pair" "openclaw" {
  key_name_prefix = "${var.project_name}-"
  public_key      = var.ssh_public_key

  tags = {
    Name    = "${var.project_name}-keypair"
    Project = var.project_name
  }
}
