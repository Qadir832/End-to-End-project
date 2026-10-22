# ============================================================
#  MQB IT Insights - AWS EC2 + Docker (Legacy Free Tier)
#  Account type: Pre-15 July 2025 (12-month free tier)
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------
# PROVIDER
# ------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "mqb-it-insights"
      ManagedBy   = "terraform"
      Environment = "demo"
    }
  }
}

# ------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------
variable "aws_region" {
  description = "AWS region (Mumbai default)"
  type        = string
  default     = "ap-south-1"
}

variable "key_name" {
  description = "EC2 key pair ka naam (AWS Console se pehle bana lein)"
  type        = string
}

variable "instance_type" {
  description = "Free tier: t3.micro (750 hrs/month). t2.micro bhi chalega."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "SSH kis IP se allowed ho (production mein apna IP/32 daalein)"
  type        = string
  default     = "0.0.0.0/0"
}

# ------------------------------------------------------------
# LATEST UBUNTU 24.04 LTS AMI (SSM se — hamesha updated)
# ------------------------------------------------------------
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ------------------------------------------------------------
# DEFAULT VPC + SUBNET (existing use karega, naya nahi banayega)
# ------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ------------------------------------------------------------
# SECURITY GROUP
# ------------------------------------------------------------
resource "aws_security_group" "app_sg" {
  name        = "mqb-app-sg"
  description = "SSH + HTTP for MQB IT Insights"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "mqb-app-sg" }
}

# ------------------------------------------------------------
# EC2 INSTANCE (Docker auto-install)
# ------------------------------------------------------------
resource "aws_instance" "app_server" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8   # Free tier: 30 GB tak allowed, 8 GB kaafi hai
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    apt-get update -y
    apt-get install -y docker.io
    systemctl enable --now docker
    usermod -aG docker ubuntu

    # Docker ready hone ka wait
    until docker info >/dev/null 2>&1; do sleep 2; done
    echo "Docker installed successfully" > /var/log/mqb-setup.log
  EOF

  user_data_replace_on_change = true

  tags = { Name = "mqb-app-server" }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------
# OUTPUTS
# ------------------------------------------------------------
output "server_ip" {
  description = "EC2 public IP — browser mein kholen"
  value       = aws_instance.app_server.public_ip
}

output "ssh_command" {
  description = "SSH karne ka command"
  value       = "ssh -i <your-key.pem> ubuntu@${aws_instance.app_server.public_ip}"
}

output "app_url" {
  description = "Live app URL"
  value       = "http://${aws_instance.app_server.public_ip}"
}