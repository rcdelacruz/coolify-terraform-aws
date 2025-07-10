# Terraform outputs
output "public_ip" {
  description = "Public IP address of the Coolify server (Elastic IP)"
  value       = aws_eip.coolify_eip.public_ip
}

output "private_ip" {
  description = "Private IP address of the Coolify server"
  value       = aws_instance.coolify_server.private_ip
}

output "coolify_url" {
  description = "URL to access Coolify dashboard"
  value       = "http://${aws_eip.coolify_eip.public_ip}:8000"
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.coolify_eip.public_ip}"
}

output "backup_bucket" {
  description = "S3 bucket name for backups"
  value       = aws_s3_bucket.coolify_backups.bucket
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.coolify_server.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.coolify_sg.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.coolify_vpc.id
}

output "subnet_id" {
  description = "Subnet ID"
  value       = aws_subnet.coolify_public_subnet.id
}

output "data_volume_id" {
  description = "Data volume ID"
  value       = aws_ebs_volume.coolify_data.id
}

output "cloudflare_tunnel_setup" {
  description = "Cloudflare Tunnel configuration instructions"
  value       = <<-EOT
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

output "initial_setup_commands" {
  description = "Commands to run after deployment"
  value       = <<-EOT
    # Connect to your server
    ${format("ssh -i ~/.ssh/%s.pem ubuntu@%s", var.key_name, aws_eip.coolify_eip.public_ip)}

    # Check Coolify status
    sudo docker ps | grep coolify

    # View installation logs
    sudo tail -f /var/log/user-data.log

    # Access Coolify dashboard
    echo "Coolify URL: http://${aws_eip.coolify_eip.public_ip}:8000"
  EOT
}

output "elastic_ip_id" {
  description = "Elastic IP allocation ID"
  value       = aws_eip.coolify_eip.id
}
