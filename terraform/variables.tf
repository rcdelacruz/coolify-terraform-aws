# Terraform variables
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
  default     = ["0.0.0.0/0"]
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

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "coolify"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "data_volume_size" {
  description = "Size of the data volume in GB"
  type        = number
  default     = 100
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 20
}

variable "domain_name" {
  description = "Domain name for Coolify (optional)"
  type        = string
  default     = ""
}

variable "enable_termination_protection" {
  description = "Enable EC2 termination protection"
  type        = bool
  default     = true
}

variable "enable_cloudflare_tunnel" {
  description = "Configure security groups for Cloudflare Tunnel"
  type        = bool
  default     = true
}
