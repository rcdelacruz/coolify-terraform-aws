# Multi-Server Coolify Architecture Outputs

# Control Server Information
output "control_server_public_ip" {
  description = "Public IP address of the Coolify control server"
  value       = aws_instance.coolify_control_server.public_ip
}

output "control_server_private_ip" {
  description = "Private IP address of the Coolify control server"
  value       = aws_instance.coolify_control_server.private_ip
}

output "control_server_instance_id" {
  description = "Instance ID of the control server"
  value       = aws_instance.coolify_control_server.id
}

# Remote Servers Information
output "remote_servers_public_ips" {
  description = "Public IP addresses of all remote deployment servers"
  value       = aws_instance.coolify_remote_servers[*].public_ip
}

output "remote_servers_private_ips" {
  description = "Private IP addresses of all remote deployment servers"
  value       = aws_instance.coolify_remote_servers[*].private_ip
}

output "remote_servers_instance_ids" {
  description = "Instance IDs of all remote servers"
  value       = aws_instance.coolify_remote_servers[*].id
}

output "remote_servers_details" {
  description = "Detailed information about each remote server"
  value = [
    for i, server in aws_instance.coolify_remote_servers : {
      name           = "remote-server-${i + 1}"
      public_ip      = server.public_ip
      private_ip     = server.private_ip
      instance_id    = server.id
      data_volume_id = aws_ebs_volume.remote_data[i].id
    }
  ]
}

# Access Information
output "coolify_dashboard_url" {
  description = "URL to access the Coolify dashboard"
  value       = "http://${aws_instance.coolify_control_server.public_ip}:8000"
}

output "control_ssh_command" {
  description = "SSH command to connect to the control server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.coolify_control_server.public_ip}"
}

output "remote_ssh_commands" {
  description = "SSH commands to connect to each remote server"
  value = [
    for i, ip in aws_instance.coolify_remote_servers[*].public_ip :
    "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}  # Remote server ${i + 1}"
  ]
}

# Infrastructure Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.coolify_vpc.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.coolify_public_subnet.id
}

output "control_security_group_id" {
  description = "ID of the control server security group"
  value       = aws_security_group.coolify_control_sg.id
}

output "remote_security_group_id" {
  description = "ID of the remote servers security group"
  value       = aws_security_group.coolify_remote_sg.id
}

# Storage and Backup
output "backup_bucket_name" {
  description = "Name of the S3 bucket for backups"
  value       = aws_s3_bucket.coolify_backups.bucket
}

output "backup_bucket_region" {
  description = "Region of the backup S3 bucket"
  value       = aws_s3_bucket.coolify_backups.region
}

output "remote_data_volume_ids" {
  description = "IDs of the EBS data volumes for remote servers"
  value       = aws_ebs_volume.remote_data[*].id
}

# Cost Estimation
output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (USD)"
  value = {
    control_server       = local.monthly_control_cost
    remote_servers_total = local.monthly_remote_cost
    storage              = local.monthly_storage_cost
    networking           = local.monthly_networking_cost
    backup               = local.monthly_backup_cost
    monitoring           = local.monthly_monitoring_cost
    total_estimated      = local.estimated_monthly_cost
  }
}

# Architecture Summary
output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value       = local.architecture_summary
}

# Cloudflare Tunnel Configuration
output "cloudflare_tunnel_config" {
  description = "Configuration guide for Cloudflare Tunnel setup"
  value = var.domain_name != "" ? {
    dashboard_hostname = "${var.domain_name}"
    realtime_hostname  = "realtime.${var.domain_name}"
    terminal_hostname  = "terminal.${var.domain_name}"
    wildcard_hostname  = "*.${var.domain_name}"

    tunnel_mappings = {
      "${var.domain_name}"             = "${aws_instance.coolify_control_server.private_ip}:8000"
      "realtime.${var.domain_name}"    = "${aws_instance.coolify_control_server.private_ip}:6001"
      "terminal.${var.domain_name}/ws" = "${aws_instance.coolify_control_server.private_ip}:6002"
      "*.${var.domain_name}"           = "Load balance across: ${join(", ", [for ip in aws_instance.coolify_remote_servers[*].private_ip : "${ip}:80"])}"
    }

    coolify_env_config = {
      PUSHER_HOST = "realtime.${var.domain_name}"
      PUSHER_PORT = "443"
    }

    note = ""
    } : {
    dashboard_hostname = ""
    realtime_hostname  = ""
    terminal_hostname  = ""
    wildcard_hostname  = ""

    tunnel_mappings = {}

    coolify_env_config = {
      PUSHER_HOST = ""
      PUSHER_PORT = ""
    }

    note = "Set domain_name variable to generate Cloudflare Tunnel configuration"
  }
}

# Setup Instructions
output "setup_instructions" {
  description = "Complete setup instructions for the multi-server architecture"
  value = <<-EOT

    🚀 Coolify Multi-Server Architecture Deployed Successfully!

    📊 Architecture Overview:
    ├── Control Server (${var.control_instance_type}): ${aws_instance.coolify_control_server.public_ip}
    └── Remote Servers (${var.remote_instance_type} × ${var.remote_server_count}):
        ${join("\n        ", [for i, ip in aws_instance.coolify_remote_servers[*].public_ip : "├── Remote ${i + 1}: ${ip}"])}

    💰 Estimated Monthly Cost: $${format("%.2f", local.estimated_monthly_cost)}

    🔗 Quick Access:
    • Coolify Dashboard: http://${aws_instance.coolify_control_server.public_ip}:8000
    • Control Server SSH: ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.coolify_control_server.public_ip}

    📋 Next Steps:

    1️⃣  Access Coolify Dashboard
       → Open: http://${aws_instance.coolify_control_server.public_ip}:8000
       → Complete initial setup and create admin account

    2️⃣  Add Remote Servers to Coolify
       → Go to: Settings → Servers → Add Server
       → For each remote server, use these details:
    ${join("\n", [
  for i, ip in aws_instance.coolify_remote_servers[*].private_ip :
  "       • Server ${i + 1}: ${ip} (Name: remote-server-${i + 1})"
])}
       → Connection details:
         - Host: [Use private IP from above]
         - Port: 22
         - User: ubuntu
         - Private Key: [Same key pair as control server]

    3️⃣  Configure Domain (Optional)
       ${var.domain_name != "" ?
"→ Domain configured: ${var.domain_name}\n       → Set up Cloudflare Tunnel with the mappings shown in cloudflare_tunnel_config output" :
"→ Set domain_name variable and re-run terraform apply for Cloudflare Tunnel setup"
}

    4️⃣  Deploy Your First Application
       → Create new project in Coolify dashboard
       → Choose a remote server for deployment
       → Deploy from Git repository or Docker image

    🔧 Management Commands:

    • View all servers: terraform output remote_servers_details
    • Check costs: terraform output estimated_monthly_costs
    • SSH to specific remote server:
    ${join("\n", [
  for i, ip in aws_instance.coolify_remote_servers[*].public_ip :
  "  ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}  # Remote ${i + 1}"
])}

    📚 Documentation:
    • Coolify Docs: https://coolify.io/docs
    • Multi-server setup: docs/multi-server-setup.md
    • Cloudflare Tunnel: docs/cloudflare-tunnel-setup.md

    🆘 Support:
    • Check logs: sudo tail -f /var/log/user-data.log
    • Monitor health: docker ps | grep coolify
    • Backup status: aws s3 ls s3://${aws_s3_bucket.coolify_backups.bucket}/

  EOT
}

# Quick Reference
output "quick_reference" {
  description = "Quick reference for common operations"
  value = {
    dashboard_url = "http://${aws_instance.coolify_control_server.public_ip}:8000"
    backup_bucket = aws_s3_bucket.coolify_backups.bucket
    server_count = {
      control = 1
      remote  = var.remote_server_count
      total   = 1 + var.remote_server_count
    }
    estimated_monthly_cost = format("$%.2f", local.estimated_monthly_cost)
    ssh_commands = {
      control = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.coolify_control_server.public_ip}"
      remote_servers = [
        for i, ip in aws_instance.coolify_remote_servers[*].public_ip :
        "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${ip}"
      ]
    }
  }
}
