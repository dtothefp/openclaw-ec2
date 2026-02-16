# Look up the latest Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "openclaw" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_pair_name
  iam_instance_profile   = var.instance_profile_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true

    tags = {
      Name    = "${var.project_name}-ebs"
      Project = var.project_name
    }
  }

  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    ssh_port          = var.ssh_port
    openclaw_user     = var.openclaw_user
    install_tailscale = var.install_tailscale
  })

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "openclaw" {
  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }
}

resource "aws_eip_association" "openclaw" {
  instance_id   = aws_instance.openclaw.id
  allocation_id = aws_eip.openclaw.id
}
