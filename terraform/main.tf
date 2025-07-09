# terraform/main.tf - Multi-Server Coolify Architecture
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

variable "control_instance_type" {
  description = "EC2 instance type for Coolify control server"
  type        = string
  default     = "t4g.micro"
}

variable "remote_instance_type" {
  description = "EC2 instance type for remote deployment servers"
  type        = string
  default     = "t4g.large"
}

variable "remote_server_count" {
  description = "Number of remote servers to create"
  type        = number
  default     = 1
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
resource "aws_security_group" "coolify_control_sg" {
  name        = "coolify-control-sg"
  description = "Security group for Coolify control server"
  vpc_id      = aws_vpc.coolify_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Coolify dashboard (restrict to your IP)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Coolify realtime server (for WebSocket connections)
  ingress {
    from_port   = 6001
    to_port     = 6001
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Coolify terminal websocket
  ingress {
    from_port   = 6002
    to_port     = 6002
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Communication with remote servers (internal)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "coolify-control-sg"
  }
}

resource "aws_security_group" "coolify_remote_sg" {
  name        = "coolify-remote-sg"
  description = "Security group for Coolify remote deployment servers"
  vpc_id      = aws_vpc.coolify_vpc.id

  # SSH access from control server and your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(var.allowed_cidrs, ["10.0.0.0/16"])
  }

  # HTTP for applications
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS for applications
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Application ports range for deployed services
  ingress {
    from_port   = 3000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Docker daemon port (for control server communication)
  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "coolify-remote-sg"
  }
}

# IAM Role for EC2 instances
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

# EBS volumes for remote servers
resource "aws_ebs_volume" "remote_data" {
  count             = var.remote_server_count
  availability_zone = var.availability_zone
  size              = 100
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = {
    Name = "coolify-remote-data-${count.index + 1}"
  }
}

# User data scripts
locals {
  control_user_data = base64encode(templatefile("${path.module}/control_user_data.sh", {
    bucket_name = aws_s3_bucket.coolify_backups.bucket
    region      = var.region
  }))

  remote_user_data = base64encode(templatefile("${path.module}/remote_user_data.sh", {
    bucket_name = aws_s3_bucket.coolify_backups.bucket
    region      = var.region
  }))
}

# Launch template for control server
resource "aws_launch_template" "coolify_control_template" {
  name_prefix   = "coolify-control-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.control_instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.coolify_control_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.coolify_profile.name
  }

  user_data = local.control_user_data

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
      Name = "coolify-control-server"
      Type = "control"
    }
  }
}

# Launch template for remote servers
resource "aws_launch_template" "coolify_remote_template" {
  name_prefix   = "coolify-remote-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.remote_instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.coolify_remote_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.coolify_profile.name
  }

  user_data = local.remote_user_data

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
      Name = "coolify-remote-server"
      Type = "remote"
    }
  }
}

# Control Server Instance
resource "aws_instance" "coolify_control_server" {
  launch_template {
    id      = aws_launch_template.coolify_control_template.id
    version = "$Latest"
  }

  subnet_id              = aws_subnet.coolify_public_subnet.id
  availability_zone      = var.availability_zone
  disable_api_termination = true

  tags = {
    Name = "coolify-control-server"
    Type = "control"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Remote Server Instances
resource "aws_instance" "coolify_remote_servers" {
  count = var.remote_server_count

  launch_template {
    id      = aws_launch_template.coolify_remote_template.id
    version = "$Latest"
  }

  subnet_id              = aws_subnet.coolify_public_subnet.id
  availability_zone      = var.availability_zone
  disable_api_termination = true

  tags = {
    Name = "coolify-remote-server-${count.index + 1}"
    Type = "remote"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Attach EBS volumes to remote servers
resource "aws_volume_attachment" "remote_data_attachment" {
  count       = var.remote_server_count
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.remote_data[count.index].id
  instance_id = aws_instance.coolify_remote_servers[count.index].id
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "coolify_logs" {
  name              = "/aws/ec2/coolify"
  retention_in_days = 7
}

# Outputs
output "control_server_public_ip" {
  value       = aws_instance.coolify_control_server.public_ip
  description = "Public IP of the Coolify control server"
}

output "control_server_private_ip" {
  value       = aws_instance.coolify_control_server.private_ip
  description = "Private IP of the Coolify control server"
}

output "remote_servers_public_ips" {
  value       = aws_instance.coolify_remote_servers[*].public_ip
  description = "Public IPs of the remote deployment servers"
}

output "remote_servers_private_ips" {
  value       = aws_instance.coolify_remote_servers[*].private_ip
  description = "Private IPs of the remote deployment servers"
}

output "coolify_dashboard_url" {
  value       = "http://${aws_instance.coolify_control_server.public_ip}:8000"
  description = "URL to access Coolify dashboard"
}

output "control_ssh_command" {
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.coolify_control_server.public_ip}"
  description = "SSH command for control server"
}

output "remote_ssh_commands" {
  value = [
    for i, ip in aws_instance.coolify_remote_servers[*].public_ip :
    "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}  # Remote server ${i + 1}"
  ]
  description = "SSH commands for remote servers"
}

output "backup_bucket" {
  value       = aws_s3_bucket.coolify_backups.bucket
  description = "S3 bucket for backups"
}

output "setup_instructions" {
  value = <<-EOT
    
    🚀 Coolify Multi-Server Setup Complete!
    
    Architecture:
    • Control Server (t4g.micro): ${aws_instance.coolify_control_server.public_ip}
    • Remote Servers (t4g.large): ${join(", ", aws_instance.coolify_remote_servers[*].public_ip)}
    
    Next Steps:
    1. Access Coolify dashboard: http://${aws_instance.coolify_control_server.public_ip}:8000
    2. Complete initial setup in Coolify dashboard
    3. Add remote servers in Coolify:
       - Go to Settings → Servers → Add Server
       - Type: Remote Server
       - For each remote server:
         * Name: remote-server-1, remote-server-2, etc.
         * Host: ${join(", ", aws_instance.coolify_remote_servers[*].private_ip)}
         * Port: 22
         * User: ubuntu
         * Private Key: Use the same key pair as control server
    
    4. Optional - Configure Cloudflare Tunnel:
       - coolify.yourdomain.com → ${aws_instance.coolify_control_server.private_ip}:8000
       - realtime.yourdomain.com → ${aws_instance.coolify_control_server.private_ip}:6001
       - terminal.yourdomain.com/ws → ${aws_instance.coolify_control_server.private_ip}:6002
       - *.yourdomain.com → Load balance across remote servers or use specific server IPs
    
    Cost Estimation:
    • Control Server (t4g.micro): ~$8/month
    • Remote Servers (t4g.large × ${var.remote_server_count}): ~$${53 * var.remote_server_count}/month
    • Storage & Networking: ~$15/month
    • Total: ~$${8 + (53 * var.remote_server_count) + 15}/month
    
  EOT
  description = "Setup instructions and next steps"
}