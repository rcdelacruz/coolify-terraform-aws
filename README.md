# Multi-Server Coolify Deployment on AWS

Production-ready Terraform configuration for deploying a scalable, multi-server Coolify architecture on AWS with ARM-based instances, complete with monitoring, backups, and security hardening.

## 🚀 Overview

This Terraform configuration deploys a **multi-server Coolify architecture** on AWS that separates control and application workloads:

### 🏗️ Architecture Components
- **Control Server** (t4g.micro): Runs Coolify dashboard and orchestrates deployments
- **Remote Servers** (t4g.large × N): Execute application workloads with dedicated resources
- **Shared Infrastructure**: VPC, S3 backups, CloudWatch monitoring, security groups
- **Scalable Design**: Easily add/remove remote servers based on demand

### ✨ Key Features
- **ARM-based instances** for ~20% cost savings over x86
- **Encrypted EBS volumes** with GP3 performance (3000 IOPS)
- **Automated S3 backups** with lifecycle policies
- **CloudWatch monitoring** with custom metrics and health checks
- **Security hardening** (UFW, fail2ban, restricted access)
- **Multi-environment support** (dev, staging, prod)
- **Cloudflare Tunnel ready** with load balancing across remote servers
- **GitHub Actions CI/CD** with automated deployment workflows

## 💰 Cost Estimates

### Default Configuration (1 Control + 2 Remote Servers)
**Monthly costs (~$167/month):**
- Control Server (t4g.micro): ~$8/month
- Remote Servers (2× t4g.large): ~$134/month
- Storage (EBS volumes): ~$15/month
- Networking & Backup: ~$10/month

### Alternative Configurations

**Development** (~$35/month):
- Control: t4g.micro, Remote: 1× t4g.small
- Ideal for testing and small applications

**Production** (~$300/month):
- Control: t4g.small, Remote: 3× t4g.xlarge
- High-performance setup for demanding workloads

## 🛠️ Prerequisites

1. **AWS Account** with appropriate IAM permissions
2. **Terraform** installed (>= 1.0)
3. **AWS CLI** configured with credentials
4. **EC2 Key Pair** created in your target region
5. **Domain** (optional, for Cloudflare Tunnel setup)

## 🚀 Quick Start

### 1. Clone and Switch to Multi-Server Branch
```bash
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws
git checkout multi-server-architecture
cd terraform
```

### 2. Configure Variables
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
# Required Configuration
region            = "us-east-1"
availability_zone = "us-east-1a"
key_name         = "your-ec2-key-pair"

# Security (IMPORTANT: Replace with your IP!)
allowed_cidrs = ["YOUR.IP.ADDRESS/32"]

# Architecture Configuration
control_instance_type = "t4g.micro"   # Control server
remote_instance_type  = "t4g.large"   # Remote servers
remote_server_count   = 2             # Number of remote servers

# Optional Domain Configuration
domain_name = "coolify.yourdomain.com"
```

### 3. Deploy Infrastructure
```bash
terraform init
terraform plan
terraform apply
```

### 4. Access and Configure Coolify
After deployment (~10-15 minutes):

```bash
# Get deployment information
terraform output setup_instructions
terraform output quick_reference

# Access Coolify dashboard
open http://$(terraform output -raw control_server_public_ip):8000
```

## 🔧 Post-Deployment Setup

### 1. Initial Coolify Configuration
1. Access the dashboard URL from terraform output
2. Complete the Coolify setup wizard
3. Create your admin account

### 2. Add Remote Servers to Coolify
In the Coolify dashboard:
1. Navigate to **Settings** → **Servers** → **Add Server**
2. Select **Remote Server** type
3. For each remote server (get private IPs from terraform output):

```
Server Configuration:
- Name: remote-server-1 (increment for each)
- Host: [Private IP from terraform output]
- Port: 22
- User: ubuntu
- Private Key: [Same key pair used for deployment]
```

### 3. Verify and Deploy
- Confirm all servers show "Connected" status
- Deploy your first application to test the setup

## 🏗️ Architecture Deep Dive

### Network Architecture
```
Internet Gateway
       │
    VPC (10.0.0.0/16)
       │
 Public Subnet (10.0.1.0/24)
       │
┌──────┴──────┐
│             │
Control      Remote
Server       Servers
(Dashboard)  (Apps)
```

### Server Roles

**Control Server**:
- Runs Coolify dashboard and management interface
- Orchestrates deployments to remote servers
- Handles user authentication and project management
- Minimal resource requirements (t4g.micro)

**Remote Servers**:
- Execute actual application workloads
- Docker containers and databases run here
- Dedicated resources for application performance
- Scalable count based on workload requirements

### Security Model
- **Control Server**: Restricted dashboard access (your IP only)
- **Remote Servers**: Public web traffic + internal communication
- **Inter-server**: Private network communication within VPC
- **Data**: Encrypted EBS volumes and S3 backups

## 📊 Monitoring & Observability

### CloudWatch Metrics
**Custom Metrics** (sent every minute):
- Container count per server
- Disk usage for data volumes
- Memory utilization
- Application-specific metrics

**Standard AWS Metrics**:
- CPU utilization
- Network I/O
- Disk I/O
- Instance health

### Health Monitoring
- **Coolify Health Checks**: Every 5 minutes with auto-restart
- **System Health**: Automated alerting via CloudWatch
- **Container Health**: Docker container status monitoring
- **Backup Health**: S3 backup verification

### Centralized Logging
- **CloudWatch Logs**: Centralized log collection
- **Log Retention**: Configurable retention periods
- **Log Analytics**: CloudWatch Insights for analysis

## 💾 Backup & Disaster Recovery

### Automated Backup Strategy
- **Schedule**: Daily backups at 2 AM UTC
- **Scope**: Coolify data, Docker volumes, configuration
- **Storage**: S3 with versioning and encryption
- **Retention**: Configurable (default 7 days)
- **Cross-Region**: Optional replication for disaster recovery

### Backup Contents
- Coolify database and configuration
- Docker volumes and persistent data
- Application data and databases
- System configuration files

### Recovery Procedures
- **Point-in-time recovery** from S3 backups
- **Cross-region disaster recovery** options
- **Individual application restore** capabilities

## 🌐 Cloudflare Tunnel Integration

### Automatic Configuration
When `domain_name` is set, terraform generates Cloudflare Tunnel mappings:

```hcl
# Your terraform.tfvars
domain_name = "coolify.yourdomain.com"
```

### Generated Tunnel Mappings
```
coolify.yourdomain.com → Control Server:8000 (Dashboard)
realtime.yourdomain.com → Control Server:6001 (WebSocket)
terminal.yourdomain.com/ws → Control Server:6002 (Terminal)
*.yourdomain.com → Load balanced across Remote Servers:80 (Apps)
```

### Setup Instructions
1. Deploy with `domain_name` configured
2. Run `terraform output cloudflare_tunnel_config`
3. Follow the generated configuration guide
4. Set up Cloudflare Tunnel with provided mappings

## 🔄 Scaling Operations

### Horizontal Scaling (Add/Remove Servers)
```bash
# Scale up to 3 remote servers
terraform apply -var="remote_server_count=3"

# Scale down to 1 remote server
terraform apply -var="remote_server_count=1"
```

### Vertical Scaling (Instance Types)
```bash
# Upgrade remote servers to t4g.xlarge
terraform apply -var="remote_instance_type=t4g.xlarge"

# Upgrade control server to t4g.small for better performance
terraform apply -var="control_instance_type=t4g.small"
```

### Multi-Environment Management
```bash
# Deploy to different environments
terraform apply -var="environment=staging"
terraform apply -var="environment=prod"
```

## 🔧 Management Operations

### Common Commands
```bash
# Get server details
terraform output remote_servers_details

# Check current costs
terraform output estimated_monthly_costs

# Get SSH commands for all servers
terraform output remote_ssh_commands

# View architecture summary
terraform output architecture_summary
```

### Server Access
```bash
# Control server
ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw control_server_public_ip)

# Remote servers (use output for specific IPs)
terraform output remote_ssh_commands
```

### Monitoring Commands
```bash
# Check Coolify status on control server
docker ps | grep coolify

# Monitor logs
sudo tail -f /var/log/user-data.log

# Check disk usage
df -h /data

# View backup status
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/
```

## 🤖 CI/CD Integration

### GitHub Actions Workflow
The repository includes a comprehensive GitHub Actions workflow for:
- **Automated validation** of Terraform configurations
- **Multi-environment deployments** (dev, staging, prod)
- **Plan previews** on pull requests
- **Automated deployments** on branch pushes
- **Manual triggers** for apply/destroy operations

### Required Secrets
Configure these secrets in your GitHub repository:
```
AWS_ACCESS_KEY_ID       # AWS credentials
AWS_SECRET_ACCESS_KEY   # AWS credentials
AWS_REGION             # Target AWS region
EC2_KEY_NAME           # EC2 key pair name
ALLOWED_CIDR           # Your IP for access
CONTROL_INSTANCE_TYPE  # Control server instance type
REMOTE_INSTANCE_TYPE   # Remote server instance type
REMOTE_SERVER_COUNT    # Number of remote servers
DOMAIN_NAME           # Optional domain name
```

### Workflow Triggers
- **Push to branch**: Automatic deployment
- **Pull requests**: Plan previews with cost estimates
- **Manual dispatch**: Deploy, destroy, or plan operations

## 🚨 Troubleshooting

### Common Issues

**Remote server connection failures**:
1. Verify security groups allow internal communication
2. Check SSH key configuration in Coolify
3. Ensure Docker daemon is running on remote servers

**High infrastructure costs**:
1. Review unused EBS volumes and snapshots
2. Optimize CloudWatch log retention periods
3. Consider smaller instance types for development

**Application deployment failures**:
1. Check remote server resources (CPU, memory, disk)
2. Verify Docker daemon status
3. Review Coolify deployment logs

### Debug Commands
```bash
# Check server connectivity
ping [remote-server-private-ip]

# Verify Docker status
systemctl status docker

# Check Coolify logs
docker logs coolify-realtime

# Monitor resource usage
htop
df -h
docker system df
```

## 📋 Variables Reference

### Required Variables
| Variable | Description | Example |
|----------|-------------|---------|
| `key_name` | EC2 Key Pair name | `"my-keypair"` |

### Core Configuration
| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `region` | AWS region | `"us-east-1"` | Any AWS region |
| `control_instance_type` | Control server type | `"t4g.micro"` | t4g.micro, t4g.small, etc. |
| `remote_instance_type` | Remote server type | `"t4g.large"` | t4g.large, t4g.xlarge, etc. |
| `remote_server_count` | Number of remote servers | `1` | 1-10 |

### Security Settings
| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `allowed_cidrs` | IP ranges for access | `["0.0.0.0/0"]` | `["1.2.3.4/32"]` |
| `enable_termination_protection` | Prevent accidental deletion | `true` | true/false |

### Storage Configuration
| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `remote_data_volume_size` | Data volume size (GB) | `100` | 20-1000 |
| `backup_retention_days` | S3 backup retention | `7` | 1-365 |

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Test** your changes thoroughly
4. **Commit** your changes (`git commit -m 'Add amazing feature'`)
5. **Push** to the branch (`git push origin feature/amazing-feature`)
6. **Open** a Pull Request

### Development Guidelines
- Follow Terraform best practices
- Test with multiple configurations
- Update documentation for new features
- Ensure cost estimates are accurate

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support & Resources

### Documentation
- **[Multi-Server Setup Guide](docs/multi-server-setup.md)**: Detailed setup instructions
- **[Cloudflare Tunnel Guide](docs/cloudflare-tunnel-setup.md)**: Domain configuration
- **[Coolify Documentation](https://coolify.io/docs)**: Official Coolify docs

### Community Support
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Community Q&A and ideas
- **Coolify Discord**: Official Coolify community

### Professional Support
- **AWS Support**: Infrastructure-related issues
- **Terraform Cloud**: Enterprise Terraform management
- **Custom Solutions**: Contact for enterprise deployments

## 🙏 Acknowledgments

- **[Coolify](https://coolify.io)** - The amazing self-hosted PaaS platform
- **[AWS](https://aws.amazon.com)** - Reliable cloud infrastructure provider
- **[Terraform](https://terraform.io)** - Infrastructure as Code that makes this possible
- **[ARM Architecture](https://aws.amazon.com/ec2/graviton/)** - Cost-effective computing power

---

**Ready to deploy your scalable Coolify infrastructure?** 🚀

```bash
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws
git checkout multi-server-architecture
cd terraform && terraform apply
```
