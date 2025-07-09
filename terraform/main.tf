# terraform/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Backend configuration (uncomment and configure for production)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "coolify/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for EBS volumes"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.large"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access SSH and Coolify dashboard"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# Provider configuration
provider "aws" {
  region = var.region
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-lts-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Random password for initial setup
resource "random_password" "coolify_password" {
  length  = 16
  special = true
}

# VPC and Networking
resource "aws_vpc" "coolify_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "coolify-vpc"
  }
}

resource "aws_internet_gateway" "coolify_igw" {
  vpc_id = aws_vpc.coolify_vpc.id

  tags = {
    Name = "coolify-igw"
  }
}

resource "aws_subnet" "coolify_public_subnet" {
  vpc_id                  = aws_vpc.coolify_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "coolify-public-subnet"
  }
}

resource "aws_route_table" "coolify_public_rt" {
  vpc_id = aws_vpc.coolify_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coolify_igw.id
  }

  tags = {
    Name = "coolify-public-rt"
  }
}

resource "aws_route_table_association" "coolify_public_rta" {
  subnet_id      = aws_subnet.coolify_public_subnet.id
  route_table_id = aws_route_table.coolify_public_rt.id
}

# Security Groups
resource "aws_security_group" "coolify_sg" {
  name        = "coolify-sg"
  description = "Security group for Coolify server"
  vpc_id      = aws_vpc.coolify_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # HTTP (for Cloudflare Tunnel)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (for Cloudflare Tunnel)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Coolify dashboard (restrict to your IP)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Coolify realtime server (for Cloudflare Tunnel)
  ingress {
    from_port   = 6001
    to_port     = 6001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Coolify terminal websocket (for Cloudflare Tunnel)
  ingress {
    from_port   = 6002
    to_port     = 6002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Application ports range
  ingress {
    from_port   = 3000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "coolify-sg"
  }
}

# IAM Role for EC2 instance
resource "aws_iam_role" "coolify_role" {
  name = "coolify-ec2-role"

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
}

# IAM policies for backup and monitoring
resource "aws_iam_role_policy" "coolify_policy" {
  name = "coolify-policy"
  role = aws_iam_role.coolify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.coolify_backups.arn,
          "${aws_s3_bucket.coolify_backups.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "coolify_profile" {
  name = "coolify-profile"
  role = aws_iam_role.coolify_role.name
}

# S3 bucket for backups
resource "aws_s3_bucket" "coolify_backups" {
  bucket = "coolify-backups-${random_password.coolify_password.id}"
}

resource "aws_s3_bucket_versioning" "coolify_backups_versioning" {
  bucket = aws_s3_bucket.coolify_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "coolify_backups_lifecycle" {
  bucket = aws_s3_bucket.coolify_backups.id

  rule {
    id     = "backup_lifecycle"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "coolify_backups_encryption" {
  bucket = aws_s3_bucket.coolify_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# EBS volumes
resource "aws_ebs_volume" "coolify_data" {
  availability_zone = var.availability_zone
  size              = 100
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = {
    Name = "coolify-data"
  }
}

# User data script for Coolify installation
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    bucket_name = aws_s3_bucket.coolify_backups.bucket
    region      = var.region
  }))
}

# Launch template for auto-scaling (optional)
resource "aws_launch_template" "coolify_template" {
  name_prefix   = "coolify-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.coolify_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.coolify_profile.name
  }

  user_data = local.user_data

  credit_specification {
    cpu_credits = "unlimited"
  }

  monitoring {
    enabled = var.enable_monitoring
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
      iops        = 3000
      throughput  = 125
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "coolify-server"
    }
  }
}

# EC2 Instance
resource "aws_instance" "coolify_server" {
  launch_template {
    id      = aws_launch_template.coolify_template.id
    version = "$Latest"
  }

  subnet_id              = aws_subnet.coolify_public_subnet.id
  availability_zone      = var.availability_zone
  disable_api_termination = true

  tags = {
    Name = "coolify-server"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Attach EBS volume
resource "aws_volume_attachment" "coolify_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.coolify_data.id
  instance_id = aws_instance.coolify_server.id
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "coolify_logs" {
  name              = "/aws/ec2/coolify"
  retention_in_days = 7
}

# Outputs
output "public_ip" {
  value = aws_instance.coolify_server.public_ip
}

output "private_ip" {
  value = aws_instance.coolify_server.private_ip
}

output "coolify_url" {
  value = "http://${aws_instance.coolify_server.public_ip}:8000"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.coolify_server.public_ip}"
}

output "backup_bucket" {
  value = aws_s3_bucket.coolify_backups.bucket
}

output "cloudflare_tunnel_setup" {
  value = <<-EOT
    Configure your Cloudflare Tunnel with these hostname mappings:
    
    1. coolify.stratpoint.io → ${aws_instance.coolify_server.private_ip}:8000 (HTTP)
    2. realtime.stratpoint.io → ${aws_instance.coolify_server.private_ip}:6001 (HTTP)
    3. terminal.stratpoint.io/ws → ${aws_instance.coolify_server.private_ip}:6002 (HTTP)
    4. *.stratpoint.io → ${aws_instance.coolify_server.private_ip}:80 (HTTP) [for deployed apps]
    
    Then update Coolify's .env file with:
    PUSHER_HOST=realtime.stratpoint.io
    PUSHER_PORT=443
  EOT
}
