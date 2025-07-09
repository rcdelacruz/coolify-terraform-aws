# Coolify Multi-Server Troubleshooting Guide

Common issues and solutions for the multi-server Coolify deployment.

## Infrastructure Issues

### Terraform Deployment Problems

#### Error: Key pair not found
```bash
# Create key pair first
aws ec2 create-key-pair --key-name coolify-key --query 'KeyMaterial' --output text > ~/.ssh/coolify-key.pem
chmod 400 ~/.ssh/coolify-key.pem
```

#### Error: Availability zone has no supported instance type
```hcl
# Update terraform.tfvars
availability_zone = "us-east-1b"  # Try different AZ
```

### Instance Launch Issues

#### Control server not accessible
```bash
# Check security group
aws ec2 describe-security-groups --group-names coolify-control-sg

# Verify your IP is allowed
curl ifconfig.me  # Get your current IP
# Update allowed_cidrs in terraform.tfvars
```

#### Remote servers can't connect to control
```bash
# Test connectivity from control server
ssh -i ~/.ssh/coolify-key.pem ubuntu@CONTROL_IP
ssh ubuntu@REMOTE_PRIVATE_IP

# Check Docker daemon on remote
sudo systemctl status docker
netstat -tlnp | grep :2376
```

## Coolify Application Issues

### Dashboard not loading
```bash
# Check Coolify service
sudo systemctl status coolify
sudo journalctl -u coolify -f

# Restart if needed
sudo systemctl restart coolify
```

### Remote server connection failed
```bash
# From Coolify dashboard, check:
# 1. SSH connectivity test
# 2. Docker daemon accessibility
# 3. Server requirements validation

# Manual verification
ssh ubuntu@REMOTE_PRIVATE_IP docker info
```

### Application deployment failures
```bash
# Check Docker logs on remote server
docker ps -a
docker logs CONTAINER_ID

# Check disk space
df -h /data

# Check memory usage
free -h
```

## Performance Issues

### High memory usage on control server
```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head

# Restart Coolify if needed
sudo systemctl restart coolify

# Consider upgrading to t4g.small
```

### Slow application performance
```bash
# Check remote server resources
htop
iostat -x 1
netstat -i

# Scale up if consistently high usage
```

## Network Connectivity Issues

### SSH connection problems
```bash
# Check SSH daemon
sudo systemctl status ssh

# Verify key permissions
chmod 400 ~/.ssh/coolify-key.pem

# Test SSH with verbose output
ssh -v -i ~/.ssh/coolify-key.pem ubuntu@SERVER_IP
```

### Docker daemon unreachable
```bash
# Check Docker daemon status
sudo systemctl status docker

# Verify Docker daemon configuration
sudo cat /etc/docker/daemon.json

# Restart Docker if needed
sudo systemctl restart docker
```

## Monitoring and Logging

### CloudWatch logs not appearing
```bash
# Check CloudWatch agent
sudo systemctl status amazon-cloudwatch-agent

# Verify configuration
sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Restart agent
sudo systemctl restart amazon-cloudwatch-agent
```

### Missing metrics in dashboard
```bash
# Check custom metric scripts
sudo /usr/local/bin/coolify-control-monitor.sh
sudo /usr/local/bin/coolify-remote-monitor.sh

# Verify IAM permissions for CloudWatch
```

## Backup and Recovery

### Backup script failures
```bash
# Check backup script logs
tail -f /var/log/backup.log

# Test S3 access
aws s3 ls s3://BUCKET_NAME/

# Verify IAM permissions for S3
```

### Restore from backup
```bash
# Download backup from S3
aws s3 cp s3://BUCKET_NAME/control/backup.tar.gz /tmp/

# Extract and restore
cd /data
sudo tar -xzf /tmp/backup.tar.gz
sudo chown -R ubuntu:ubuntu /data/coolify
```

## Emergency Procedures

### Complete system recovery
```bash
# 1. Redeploy infrastructure
terraform destroy -auto-approve
terraform apply -auto-approve

# 2. Restore from backup
# Follow backup restoration steps above

# 3. Reconfigure remote servers in Coolify
# Use the setup instructions from terraform output
```

### Scale down for cost emergency
```bash
# Temporarily reduce remote servers
remote_server_count = 1
terraform apply

# Move critical applications to remaining server
```

## Getting Help

### Useful diagnostic commands
```bash
# System overview
sudo systemctl status coolify docker
df -h
free -h
ps aux --sort=-%cpu | head

# Network connectivity
ss -tulnp
curl -I localhost:8000
telnet REMOTE_IP 2376

# Docker health
docker system info
docker system df
docker ps --all
```

### Log locations
```bash
# System logs
journalctl -u coolify -f
journalctl -u docker -f

# Application logs
tail -f /var/log/user-data.log
tail -f /var/log/backup.log
tail -f /var/log/coolify-health.log
```

---

**Remember**: Always check the Terraform outputs for current IP addresses and connection details before troubleshooting connectivity issues.