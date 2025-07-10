# Local computed values for the multi-server architecture
locals {
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Architecture = "multi-server"
      CreatedDate = formatdate("YYYY-MM-DD", timestamp())
    },
    var.additional_tags
  )
  
  # Resource naming convention
  name_prefix = var.name_prefix != "" ? "${var.name_prefix}-" : ""
  name_suffix = var.name_suffix != "" ? "-${var.name_suffix}" : ""
  
  # Base names for resources
  resource_prefix = "${local.name_prefix}${var.project_name}-${var.environment}"
  resource_suffix = local.name_suffix
  
  # VPC and networking
  vpc_name = "${local.resource_prefix}-vpc${local.resource_suffix}"
  igw_name = "${local.resource_prefix}-igw${local.resource_suffix}"
  subnet_name = "${local.resource_prefix}-public-subnet${local.resource_suffix}"
  route_table_name = "${local.resource_prefix}-public-rt${local.resource_suffix}"
  
  # Security groups
  control_sg_name = "${local.resource_prefix}-control-sg${local.resource_suffix}"
  remote_sg_name = "${local.resource_prefix}-remote-sg${local.resource_suffix}"
  
  # IAM resources
  iam_role_name = "${local.resource_prefix}-ec2-role${local.resource_suffix}"
  iam_policy_name = "${local.resource_prefix}-policy${local.resource_suffix}"
  iam_profile_name = "${local.resource_prefix}-profile${local.resource_suffix}"
  
  # S3 bucket for backups
  backup_bucket_name = "${local.resource_prefix}-backups-${random_id.bucket_suffix.hex}${local.resource_suffix}"
  
  # CloudWatch log group
  log_group_name = "/aws/ec2/${var.project_name}-${var.environment}"
  
  # Launch template names
  control_template_name = "${local.resource_prefix}-control-template${local.resource_suffix}"
  remote_template_name = "${local.resource_prefix}-remote-template${local.resource_suffix}"
  
  # Instance names
  control_instance_name = "${local.resource_prefix}-control-server${local.resource_suffix}"
  remote_instance_prefix = "${local.resource_prefix}-remote-server"
  
  # EBS volume names
  remote_data_volume_prefix = "${local.resource_prefix}-remote-data"
  
  # User data template variables
  control_user_data_vars = {
    bucket_name = local.backup_bucket_name
    region      = var.region
    environment = var.environment
    project_name = var.project_name
    server_type = "control"
    remote_server_count = var.remote_server_count
  }
  
  remote_user_data_vars = {
    bucket_name = local.backup_bucket_name
    region      = var.region
    environment = var.environment
    project_name = var.project_name
    server_type = "remote"
    # Note: control_server_ip is referenced in outputs, not locals to avoid circular dependency
  }
  
  # User data scripts (base64 encoded)
  control_user_data = base64encode(templatefile("${path.module}/control_user_data.sh", local.control_user_data_vars))
  remote_user_data = base64encode(templatefile("${path.module}/remote_user_data.sh", local.remote_user_data_vars))
  
  # Cost calculation (monthly estimates in USD)
  control_instance_cost = {
    "t4g.micro"  = 8.35
    "t4g.small"  = 16.70
    "t4g.medium" = 33.41
    "t4g.large"  = 66.82
    "t3.micro"   = 10.22
    "t3.small"   = 20.44
    "t3.medium"  = 40.88
    "t3.large"   = 81.76
  }
  
  remote_instance_cost = {
    "t4g.micro"   = 8.35
    "t4g.small"   = 16.70
    "t4g.medium"  = 33.41
    "t4g.large"   = 66.82
    "t4g.xlarge"  = 133.63
    "t3.micro"    = 10.22
    "t3.small"    = 20.44
    "t3.medium"   = 40.88
    "t3.large"    = 81.76
    "t3.xlarge"   = 163.52
    "m6g.large"   = 70.08
    "m6g.xlarge"  = 140.16
    "c6g.large"   = 62.41
    "c6g.xlarge"  = 124.82
  }
  
  # Calculate estimated monthly costs
  monthly_control_cost = lookup(local.control_instance_cost, var.control_instance_type, 50)
  monthly_remote_cost = lookup(local.remote_instance_cost, var.remote_instance_type, 67) * var.remote_server_count
  monthly_storage_cost = (var.control_root_volume_size * 0.08) + (var.remote_server_count * (var.remote_root_volume_size + var.remote_data_volume_size) * 0.08)
  monthly_networking_cost = 5  # Elastic IPs, data transfer
  monthly_backup_cost = 2      # S3 storage
  monthly_monitoring_cost = 2  # CloudWatch logs and metrics
  
  estimated_monthly_cost = local.monthly_control_cost + local.monthly_remote_cost + local.monthly_storage_cost + local.monthly_networking_cost + local.monthly_backup_cost + local.monthly_monitoring_cost
  
  # Server configuration summary
  architecture_summary = {
    control_server = {
      instance_type = var.control_instance_type
      root_volume_size = var.control_root_volume_size
      estimated_monthly_cost = local.monthly_control_cost
    }
    remote_servers = {
      count = var.remote_server_count
      instance_type = var.remote_instance_type
      root_volume_size = var.remote_root_volume_size
      data_volume_size = var.remote_data_volume_size
      estimated_monthly_cost_per_server = lookup(local.remote_instance_cost, var.remote_instance_type, 67)
      total_estimated_monthly_cost = local.monthly_remote_cost
    }
    total_estimated_monthly_cost = local.estimated_monthly_cost
  }
}

# Generate a random suffix for the S3 bucket to ensure uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
