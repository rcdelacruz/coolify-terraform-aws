# Production Coolify Deployment on AWS

Production-ready Terraform configuration for deploying Coolify on AWS with t4g.large ARM instances, complete with monitoring, backups, and security hardening.

## 🚀 Overview

This Terraform configuration deploys a production-ready Coolify instance on AWS with:

- **t4g.large ARM-based instance** (4 vCPU, 8GB RAM) - ~20% cost savings
- **100GB GP3 encrypted data volume** with 3000 IOPS
- **Automated S3 backups** with lifecycle policies
- **CloudWatch monitoring** with custom metrics
- **Security hardening** (UFW, fail2ban, encrypted volumes)
- **Auto-scaling launch template** for easy replacement
- **Route 53 DNS** configuration (optional)
- **SSL/TLS ready** with automatic certificate management

## 💰 Cost Estimate

**Monthly costs (~$65-75/month):**
- EC2 t4g.large: ~$53/month
- 100GB GP3 storage: ~$8/month
- 20GB root volume: ~$2/month
- Elastic IP: ~$4/month
- S3 backup storage: ~$2-5/month
- CloudWatch logs: ~$1-2/month

## 🛠️ Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** installed (>= 1.0)
3. **AWS CLI** configured with credentials
4. **EC2 Key Pair** created in your target region

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws/terraform
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
region            = "us-east-1"
availability_zone = "us-east-1a"
key_name         = "your-ec2-key-pair"
domain_name      = "coolify.yourdomain.com"  # Optional
allowed_cidrs    = ["YOUR.IP.ADDRESS/32"]    # Your IP for security
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 4. Access Coolify
After deployment (takes ~5-10 minutes):
```bash
# Get outputs
terraform output public_ip
terraform output coolify_url
terraform output ssh_command

# Access Coolify dashboard at: http://YOUR-IP:8000
```

## 🏗️ Architecture

### Network Setup
- **Custom VPC** (10.0.0.0/16) with public subnet
- **Internet Gateway** for public access
- **Elastic IP** for static addressing
- **Security Groups** with minimal required ports

### Storage
- **20GB GP3 root volume** (encrypted, 3000 IOPS)
- **100GB GP3 data volume** (encrypted, 3000 IOPS)
- **S3 bucket** for automated backups with versioning

### Security Features
- **UFW firewall** configured with minimal ports
- **fail2ban** for SSH brute-force protection
- **Encrypted EBS volumes** with AES-256
- **IAM roles** with least-privilege permissions
- **Security groups** restricting dashboard access

## 📊 Monitoring

### CloudWatch Metrics
The system automatically sends custom metrics:
- **ContainerCount**: Number of running Docker containers
- **DataDiskUsage**: Disk usage percentage for /data
- **MemoryUsage**: Memory utilization percentage
- **CPU, Disk I/O, Network**: Standard CloudWatch metrics

### Health Checks
- **Coolify health check** every 5 minutes with auto-restart
- **System monitoring** with CloudWatch alarms
- **Log rotation** to prevent disk space issues

## 💾 Backup Strategy

### Automated Backups
- **Daily backups** at 2 AM UTC to S3
- **7-day retention** (configurable)
- **Versioning enabled** for backup files
- **Lifecycle policies** for cost optimization

## 🔧 Maintenance

### Automated Maintenance
- **Weekly system updates** on Sundays at 3 AM
- **Docker cleanup** (unused images, containers, volumes)
- **Log cleanup** (files >100MB, journal >7 days)
- **Package updates** with auto-remove

## 📋 Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `region` | AWS region | `us-east-1` | No |
| `availability_zone` | AZ for EBS volumes | `us-east-1a` | No |
| `instance_type` | EC2 instance type | `t4g.large` | No |
| `key_name` | EC2 Key Pair name | - | Yes |
| `domain_name` | Domain for Coolify | `""` | No |
| `allowed_cidrs` | IP ranges for access | `["0.0.0.0/0"]` | No |
| `enable_monitoring` | Enable CloudWatch | `true` | No |
| `backup_retention_days` | Backup retention | `7` | No |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

- **GitHub Issues**: For bug reports and feature requests
- **Coolify Documentation**: https://coolify.io/docs

## 🙏 Acknowledgments

- [Coolify](https://coolify.io) - The amazing self-hosted PaaS
- [AWS](https://aws.amazon.com) - Cloud infrastructure provider
- [Terraform](https://terraform.io) - Infrastructure as Code tool