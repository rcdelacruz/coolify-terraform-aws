# Multi-Server Coolify Setup Guide

This guide explains how to set up and manage a multi-server Coolify architecture using the configurations in this repository.

## 🏗️ Architecture Overview

The multi-server setup separates concerns for better scalability and resource management:

- **Control Server** (t4g.micro): Runs Coolify dashboard and orchestrates deployments
- **Remote Servers** (t4g.large): Execute actual application workloads
- **Shared Infrastructure**: VPC, S3 backups, CloudWatch monitoring

## 📋 Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (>= 1.0)
3. **AWS CLI** configured with credentials
4. **EC2 Key Pair** created in your target region
5. **Domain** (optional, for Cloudflare Tunnel)

## 🚀 Quick Deployment

### 1. Clone and Configure
```bash
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws
git checkout multi-server-architecture
cd terraform
```

### 2. Set Up Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
# Required
region            = "us-east-1"
availability_zone = "us-east-1a"
key_name         = "your-ec2-key-pair"

# Security (IMPORTANT: Replace with your IP)
allowed_cidrs = ["YOUR.IP.ADDRESS/32"]

# Architecture
control_instance_type = "t4g.micro"   # Control server
remote_instance_type  = "t4g.large"   # Remote servers
remote_server_count   = 2             # Number of remote servers

# Optional
domain_name = "coolify.yourdomain.com"
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 4. Access and Configure
After deployment (~10-15 minutes):
```bash
# Get important information
terraform output setup_instructions
terraform output quick_reference

# Access Coolify dashboard
open http://$(terraform output -raw control_server_public_ip):8000
```

## 🔧 Post-Deployment Configuration

### 1. Initial Coolify Setup
1. Open the Coolify dashboard URL from terraform output
2. Complete the initial setup wizard
3. Create your admin account

### 2. Add Remote Servers
In Coolify dashboard:
1. Go to **Settings** → **Servers** → **Add Server**
2. Select **Remote Server** type
3. For each remote server (get IPs from terraform output):

```
Name: remote-server-1
Host: [Private IP from terraform output]
Port: 22
User: ubuntu
Private Key: [Same key pair used for deployment]
```

### 3. Verify Connection
- Check that all servers show as "Connected" in Coolify
- Test deployment by creating a simple project

## 💰 Cost Management

### Default Configuration Costs (Monthly)
- Control Server (t4g.micro): ~$8
- Remote Servers (2x t4g.large): ~$134
- Storage (volumes): ~$15
- Networking & Backup: ~$10
- **Total: ~$167/month**

### Cost Optimization Strategies

**Development Environment** (~$35/month):
```hcl
control_instance_type = "t4g.micro"
remote_instance_type  = "t4g.small"
remote_server_count   = 1
remote_data_volume_size = 50
```

**Production Environment** (~$300/month):
```hcl
control_instance_type = "t4g.small"
remote_instance_type  = "t4g.xlarge"
remote_server_count   = 3
remote_data_volume_size = 200
```

## 🌐 Cloudflare Tunnel Setup

### 1. Configure Domain Variable
```hcl
domain_name = "coolify.yourdomain.com"
```

### 2. Apply Changes
```bash
terraform apply
```

### 3. Get Tunnel Configuration
```bash
terraform output cloudflare_tunnel_config
```

### 4. Set Up Cloudflare Tunnel
Follow the mappings from the output:
- `coolify.yourdomain.com` → Control server port 8000
- `realtime.yourdomain.com` → Control server port 6001
- `terminal.yourdomain.com/ws` → Control server port 6002
- `*.yourdomain.com` → Load balance across remote servers port 80

## 📊 Monitoring and Maintenance

### CloudWatch Metrics
- **Custom Metrics**: Container count, disk usage, memory usage
- **Standard Metrics**: CPU, network, disk I/O
- **Log Groups**: Centralized logging for all servers

### Automated Backups
- **Schedule**: Daily at 2 AM UTC
- **Storage**: S3 with versioning
- **Retention**: Configurable (default 7 days)
- **Scope**: Coolify data, Docker volumes

### Health Checks
- **Coolify Health**: Every 5 minutes with auto-restart
- **System Health**: CloudWatch alarms
- **Docker Health**: Container monitoring

## 🔨 Management Operations

### Scale Remote Servers
```bash
# Increase remote servers
terraform apply -var="remote_server_count=3"

# Decrease remote servers
terraform apply -var="remote_server_count=1"
```

### Access Servers
```bash
# Control server
ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw control_server_public_ip)

# Remote servers
terraform output remote_ssh_commands
```

### Check Status
```bash
# Server details
terraform output remote_servers_details

# Cost estimates
terraform output estimated_monthly_costs

# Architecture summary
terraform output architecture_summary
```

### Backup Management
```bash
# List backups
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/

# Download backup
aws s3 cp s3://$(terraform output -raw backup_bucket_name)/backup-file.tar.gz ./
```

## 🚨 Troubleshooting

### Common Issues

**Remote server not connecting:**
1. Check security groups allow communication
2. Verify SSH key is correct
3. Ensure Docker daemon is running on remote server

**High costs:**
1. Check unused EBS volumes
2. Review CloudWatch log retention
3. Consider smaller instance types for dev

**Backup failures:**
1. Verify IAM permissions for S3
2. Check disk space on servers
3. Review CloudWatch logs

### Debug Commands
```bash
# Check Coolify status
docker ps | grep coolify

# View logs
sudo tail -f /var/log/user-data.log
sudo journalctl -u coolify -f

# Check disk usage
df -h /data

# Test connectivity between servers
ping [remote-server-private-ip]
```

## 🔄 Updating Infrastructure

### Terraform Updates
```bash
# Always plan first
terraform plan

# Apply changes
terraform apply

# For major changes, consider blue-green deployment
```

### Coolify Updates
```bash
# SSH to control server
ssh -i ~/.ssh/your-key.pem ubuntu@[control-ip]

# Update Coolify
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

## 🔒 Security Best Practices

1. **Network Security**:
   - Restrict `allowed_cidrs` to your IP only
   - Use VPN for team access
   - Regular security group audits

2. **Access Management**:
   - Rotate SSH keys regularly
   - Use strong passwords for Coolify
   - Enable 2FA where possible

3. **Data Protection**:
   - Regular backup testing
   - Encrypt sensitive environment variables
   - Monitor access logs

4. **Infrastructure Security**:
   - Keep servers updated
   - Monitor for unusual activity
   - Use least-privilege IAM policies

## 📚 Additional Resources

- [Coolify Documentation](https://coolify.io/docs)
- [AWS Best Practices](https://docs.aws.amazon.com/wellarchitected/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
- [Docker Security](https://docs.docker.com/engine/security/)

## 🆘 Getting Help

1. **Check logs first**: Always start with server logs and Coolify logs
2. **Review outputs**: Use terraform outputs for configuration details
3. **Community support**: Coolify Discord and GitHub discussions
4. **AWS Support**: For infrastructure-specific issues

## 📝 Migration Guide

### From Single Server to Multi-Server

1. **Backup existing setup**
2. **Deploy multi-server architecture**
3. **Migrate applications** one by one
4. **Update DNS/Cloudflare** configurations
5. **Decommission old server**

### From Multi-Server to Larger Scale

1. **Increase remote_server_count**
2. **Apply terraform changes**
3. **Add new servers to Coolify**
4. **Redistribute applications**
5. **Update load balancing**
