# terraform/main.tf - Multi-Server Coolify Architecture

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
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC and Networking
resource "aws_vpc" "coolify_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = local.vpc_name
  })
}

resource "aws_internet_gateway" "coolify_igw" {
  vpc_id = aws_vpc.coolify_vpc.id

  tags = merge(local.common_tags, {
    Name = local.igw_name
  })
}

resource "aws_subnet" "coolify_public_subnet" {
  vpc_id                  = aws_vpc.coolify_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = local.subnet_name
  })
}

resource "aws_route_table" "coolify_public_rt" {
  vpc_id = aws_vpc.coolify_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coolify_igw.id
  }

  tags = merge(local.common_tags, {
    Name = local.route_table_name
  })
}

resource "aws_route_table_association" "coolify_public_rta" {
  subnet_id      = aws_subnet.coolify_public_subnet.id
  route_table_id = aws_route_table.coolify_public_rt.id
}

# Security Groups
resource "aws_security_group" "coolify_control_sg" {
  name        = local.control_sg_name
  description = "Security group for Coolify control server"
  vpc_id      = aws_vpc.coolify_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
    description = "SSH access"
  }

  # Coolify dashboard
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
    description = "Coolify dashboard"
  }

  # Coolify realtime server
  ingress {
    from_port   = 6001
    to_port     = 6001
    protocol    = "tcp"
    cidr_blocks = var.enable_cloudflare_tunnel ? ["0.0.0.0/0"] : var.allowed_cidrs
    description = "Coolify realtime/WebSocket"
  }

  # Coolify terminal websocket
  ingress {
    from_port   = 6002
    to_port     = 6002
    protocol    = "tcp"
    cidr_blocks = var.enable_cloudflare_tunnel ? ["0.0.0.0/0"] : var.allowed_cidrs
    description = "Coolify terminal WebSocket"
  }

  # Communication with remote servers (internal)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Internal SSH to remote servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = local.control_sg_name
  })
}

resource "aws_security_group" "coolify_remote_sg" {
  name        = local.remote_sg_name
  description = "Security group for Coolify remote deployment servers"
  vpc_id      = aws_vpc.coolify_vpc.id

  # SSH access from control server and your IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat(var.allowed_cidrs, [var.vpc_cidr])
    description = "SSH access"
  }

  # HTTP for applications
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for applications"
  }

  # HTTPS for applications
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for applications"
  }

  # Application ports range for deployed services
  ingress {
    from_port   = 3000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Application port range"
  }

  # Docker daemon port (for control server communication)
  ingress {
    from_port   = 2376
    to_port     = 2376
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Docker daemon (internal)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = local.remote_sg_name
  })
}

# IAM Role for EC2 instances
resource "aws_iam_role" "coolify_role" {
  name = local.iam_role_name

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

  tags = local.common_tags
}

# IAM policies for backup and monitoring
resource "aws_iam_role_policy" "coolify_policy" {
  name = local.iam_policy_name
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
  name = local.iam_profile_name
  role = aws_iam_role.coolify_role.name

  tags = local.common_tags
}

# S3 bucket for backups
resource "aws_s3_bucket" "coolify_backups" {
  bucket = local.backup_bucket_name

  tags = local.common_tags
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

    filter {
      prefix = ""
    }

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
  size              = var.remote_data_volume_size
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${local.remote_data_volume_prefix}-${count.index + 1}"
  })
}

# Launch template for control server
resource "aws_launch_template" "coolify_control_template" {
  name_prefix   = local.control_template_name
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
      volume_size = var.control_root_volume_size
      volume_type = "gp3"
      encrypted   = true
      iops        = 3000
      throughput  = 125
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = local.control_instance_name
      Type = "control"
    })
  }

  tags = local.common_tags
}

# Launch template for remote servers
resource "aws_launch_template" "coolify_remote_template" {
  name_prefix   = local.remote_template_name
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
      volume_size = var.remote_root_volume_size
      volume_type = "gp3"
      encrypted   = true
      iops        = 3000
      throughput  = 125
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.remote_instance_prefix}-template"
      Type = "remote"
    })
  }

  tags = local.common_tags
}

# Control Server Instance
resource "aws_instance" "coolify_control_server" {
  launch_template {
    id      = aws_launch_template.coolify_control_template.id
    version = "$Latest"
  }

  subnet_id               = aws_subnet.coolify_public_subnet.id
  availability_zone       = var.availability_zone
  disable_api_termination = var.enable_termination_protection

  tags = merge(local.common_tags, {
    Name = local.control_instance_name
    Type = "control"
  })

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

  subnet_id               = aws_subnet.coolify_public_subnet.id
  availability_zone       = var.availability_zone
  disable_api_termination = var.enable_termination_protection

  tags = merge(local.common_tags, {
    Name = "${local.remote_instance_prefix}-${count.index + 1}"
    Type = "remote"
  })

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
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}
