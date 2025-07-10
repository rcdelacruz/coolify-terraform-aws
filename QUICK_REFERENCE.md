# Quick Reference Guide - Coolify AWS + Cloudflare Tunnel

## 🔑 AWS Profile Setup (Recommended)

### Create Dedicated Coolify Profile
```bash
# Configure AWS CLI with a dedicated profile
aws configure --profile coolify
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json

# Set profile for current session
export AWS_PROFILE=coolify

# Verify profile is working
aws sts get-caller-identity

# Make it permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export AWS_PROFILE=coolify' >> ~/.bashrc
```

### Switch Between Profiles
```bash
# Use coolify profile
export AWS_PROFILE=coolify

# Use default profile
unset AWS_PROFILE

# Use specific profile for one command
aws s3 ls --profile coolify
terraform plan --var-file=terraform.tfvars
```

## 🚀 Quick Start Commands

### Initial Setup
```bash
# 1. Clone and setup
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws/terraform
cp terraform.tfvars.example terraform.tfvars

# 2. Configure AWS profile
aws configure --profile coolify
export AWS_PROFILE=coolify

# 3. Edit terraform.tfvars with your values
nano terraform.tfvars

# 4. Deploy
./validate.sh
terraform init
terraform plan
terraform apply
```

### Get Your Server Info
```bash
# Set AWS profile first
export AWS_PROFILE=coolify

# Get public IP
terraform output public_ip

# Get private IP (for Cloudflare tunnel)
terraform output private_ip

# Get SSH command
terraform output ssh_command

# Get Coolify URL
terraform output coolify_url
```

## 🌐 Cloudflare Tunnel Setup

### Install Cloudflared
```bash
# macOS
brew install cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

### Create Tunnel
```bash
# Login and create tunnel
cloudflared tunnel login
cloudflared tunnel create coolify-tunnel

# Create config file
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: coolify-tunnel
credentials-file: ~/.cloudflared/YOUR-TUNNEL-ID.json

ingress:
  - hostname: coolify.yourdomain.com
    service: http://YOUR-PRIVATE-IP:8000
  - hostname: realtime.yourdomain.com
    service: http://YOUR-PRIVATE-IP:6001
  - hostname: terminal.yourdomain.com
    service: http://YOUR-PRIVATE-IP:6002
    path: /ws
  - hostname: "*.yourdomain.com"
    service: http://YOUR-PRIVATE-IP:80
  - service: http_status:404
EOF

# Run tunnel
cloudflared tunnel run coolify-tunnel
```

### DNS Records (Cloudflare Dashboard)
Add these CNAME records:
- `coolify` → `YOUR-TUNNEL-ID.cfargotunnel.com`
- `realtime` → `YOUR-TUNNEL-ID.cfargotunnel.com`
- `terminal` → `YOUR-TUNNEL-ID.cfargotunnel.com`
- `*` → `YOUR-TUNNEL-ID.cfargotunnel.com`

## 🔧 Server Management

### SSH to Server
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw public_ip)
```

### Check Coolify Status
```bash
# Check containers
sudo docker ps | grep coolify

# Check logs
sudo docker logs coolify-realtime
sudo tail -f /var/log/user-data.log

# Restart Coolify
cd /data/coolify/source
sudo docker compose restart
```

### Configure Coolify for Tunnel
```bash
# Edit environment file
sudo nano /data/coolify/source/.env

# Add these lines:
PUSHER_HOST=realtime.yourdomain.com
PUSHER_PORT=443

# Restart
cd /data/coolify/source && sudo docker compose restart
```

## 📊 Monitoring & Maintenance

### Check System Resources
```bash
# Disk usage
df -h

# Memory usage
free -h

# Docker containers
sudo docker ps

# System logs
sudo journalctl -f
```

### Backup Management
```bash
# Manual backup
sudo /data/backups/backup-coolify.sh

# Check backup logs
sudo tail -f /var/log/backup.log

# List S3 backups (ensure correct profile)
export AWS_PROFILE=coolify
aws s3 ls s3://$(terraform output -raw backup_bucket)/
```

## 🛠️ Troubleshooting

### Common Issues

**Coolify not accessible:**
```bash
# Check if running
sudo docker ps | grep coolify

# Check ports
sudo netstat -tlnp | grep -E ':(80|6001|6002|8000)'

# Restart if needed
cd /data/coolify/source && sudo docker compose restart
```

**Tunnel not working:**
```bash
# Check tunnel status
cloudflared tunnel info coolify-tunnel

# Debug tunnel
cloudflared tunnel run coolify-tunnel --loglevel debug

# Check DNS
nslookup coolify.yourdomain.com
```

**High resource usage:**
```bash
# Clean up Docker
sudo docker system prune -f

# Check disk space
sudo ncdu /data

# Monitor resources
htop
```

## 💰 Cost Management

### Current Resources
```bash
# List all resources
terraform state list

# Show resource details
terraform show
```

### Estimated Monthly Costs
- **EC2 t4g.large**: ~$53/month
- **100GB GP3 storage**: ~$8/month
- **20GB root volume**: ~$2/month
- **Elastic IP**: ~$4/month
- **S3 backups**: ~$2-5/month
- **CloudWatch**: ~$1-2/month
- **Total**: ~$65-75/month

## 🔄 Updates & Maintenance

### Update Coolify
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@$(terraform output -raw public_ip)
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

### Update Infrastructure
```bash
# Pull latest changes
git pull origin main

# Plan and apply updates
terraform plan
terraform apply
```

### Destroy Everything (if needed)
```bash
# ⚠️ WARNING: This deletes everything!
terraform destroy
```

## 📱 Access URLs

After setup, access your services at:
- **Coolify Dashboard**: `https://coolify.yourdomain.com`
- **Your Apps**: `https://appname.yourdomain.com`
- **Direct IP Access**: `http://YOUR-PUBLIC-IP:8000` (for troubleshooting)

## 🆘 Emergency Contacts

- **AWS Support**: https://aws.amazon.com/support/
- **Cloudflare Support**: https://support.cloudflare.com/
- **Coolify Discord**: https://discord.gg/coolify
- **GitHub Issues**: https://github.com/rcdelacruz/coolify-terraform-aws/issues

## 📋 Pre-flight Checklist

Before deploying:
- [ ] AWS credentials configured
- [ ] EC2 key pair created
- [ ] Domain added to Cloudflare
- [ ] terraform.tfvars configured
- [ ] Validation script passed
- [ ] Budget alerts set up in AWS

After deploying:
- [ ] Coolify accessible via tunnel
- [ ] Realtime features working
- [ ] Test app deployed successfully
- [ ] Backups configured and tested
- [ ] Monitoring alerts set up

## 🎯 Quick Commands Summary

```bash
# Deploy
terraform apply

# Get info
terraform output

# SSH
ssh -i ~/.ssh/key.pem ubuntu@$(terraform output -raw public_ip)

# Tunnel
cloudflared tunnel run coolify-tunnel

# Restart Coolify
sudo docker compose -f /data/coolify/source/docker-compose.yml restart

# Check status
sudo docker ps | grep coolify
```

---
**Need help?** Check the full [SETUP_GUIDE.md](./SETUP_GUIDE.md) for detailed instructions.
