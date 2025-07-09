# Multi-Server Coolify Architecture Variables

# Core Infrastructure
variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for EBS volumes (must be in the specified region)"
  type        = string
  default     = "us-east-1a"
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "coolify"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# Server Configuration
variable "control_instance_type" {
  description = "EC2 instance type for Coolify control server (manages deployments)"
  type        = string
  default     = "t4g.micro"
  
  validation {
    condition = contains([
      "t4g.micro", "t4g.small", "t4g.medium", "t4g.large",
      "t3.micro", "t3.small", "t3.medium", "t3.large"
    ], var.control_instance_type)
    error_message = "Control instance type must be a valid ARM or x86 instance type."
  }
}

variable "remote_instance_type" {
  description = "EC2 instance type for remote deployment servers (runs applications)"
  type        = string
  default     = "t4g.large"
  
  validation {
    condition = contains([
      "t4g.micro", "t4g.small", "t4g.medium", "t4g.large", "t4g.xlarge",
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "m6g.large", "m6g.xlarge", "c6g.large", "c6g.xlarge"
    ], var.remote_instance_type)
    error_message = "Remote instance type must be a valid instance type."
  }
}

variable "remote_server_count" {
  description = "Number of remote deployment servers to create"
  type        = number
  default     = 1
  
  validation {
    condition     = var.remote_server_count >= 1 && var.remote_server_count <= 10
    error_message = "Remote server count must be between 1 and 10."
  }
}

# Security Configuration
variable "key_name" {
  description = "EC2 Key Pair name (must exist in the target region)"
  type        = string
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access SSH and Coolify dashboard"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All allowed_cidrs must be valid CIDR blocks."
  }
}

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection for all instances"
  type        = bool
  default     = true
}

# Storage Configuration
variable "control_root_volume_size" {
  description = "Size of control server root volume in GB"
  type        = number
  default     = 20
}

variable "remote_root_volume_size" {
  description = "Size of remote server root volume in GB"
  type        = number
  default     = 20
}

variable "remote_data_volume_size" {
  description = "Size of remote server data volume in GB (for Docker and applications)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.remote_data_volume_size >= 20 && var.remote_data_volume_size <= 1000
    error_message = "Remote data volume size must be between 20 and 1000 GB."
  }
}

# Monitoring and Backup
variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring for all instances"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain S3 backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid CIDR block."
  }
}

# Domain Configuration (Optional)
variable "domain_name" {
  description = "Domain name for Coolify dashboard (optional, for Cloudflare Tunnel setup)"
  type        = string
  default     = ""
}

variable "enable_cloudflare_tunnel" {
  description = "Configure security groups for Cloudflare Tunnel access"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Resource Naming
variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = ""
}

variable "name_suffix" {
  description = "Suffix for all resource names"
  type        = string
  default     = ""
}
