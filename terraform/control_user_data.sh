#!/bin/bash
# terraform/control_user_data.sh - Coolify Control Server Setup

set -e

# Variables from Terraform
BUCKET_NAME="${bucket_name}"
REGION="${region}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting Coolify Control Server Installation ==="
echo "Timestamp: $(date)"

# Update system
apt-get update -y
apt-get upgrade -y

# Install essential packages
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    htop \
    ncdu \
    tree \
    jq \
    awscli \
    fail2ban \
    ufw \
    docker.io \
    docker-compose \
    certbot \
    openssh-client

# Configure timezone
timedatectl set-timezone UTC

# Setup firewall (more restrictive for control server)
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 8000/tcp   # Coolify dashboard
ufw allow 6001/tcp   # Coolify realtime server
ufw allow 6002/tcp   # Coolify terminal websocket
ufw --force enable

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Setup Docker
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Create swap file (recommended for micro instances)
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Create directories
mkdir -p /data/coolify
mkdir -p /data/backups
chown -R ubuntu:ubuntu /data

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# CloudWatch agent configuration for control server
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "CoolifyControlServer",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ],
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/coolify.log",
                        "log_group_name": "/aws/ec2/coolify",
                        "log_stream_name": "{instance_id}/coolify-control"
                    },
                    {
                        "file_path": "/var/log/docker.log",
                        "log_group_name": "/aws/ec2/coolify",
                        "log_stream_name": "{instance_id}/docker-control"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Setup backup script for control server
cat > /data/backups/backup-coolify-control.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="coolify-control-backup-$TIMESTAMP.tar.gz"

echo "Starting control server backup at $(date)"

# Create backup of Coolify configuration and data
cd /data
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude='./backups' \
    ./coolify

# Upload to S3
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$BUCKET_NAME/control/"

# Clean up local backup
rm "$BACKUP_DIR/$BACKUP_FILE"

echo "Control server backup completed at $(date)"
EOF

chmod +x /data/backups/backup-coolify-control.sh
chown ubuntu:ubuntu /data/backups/backup-coolify-control.sh

# Setup cron for backups (daily at 2 AM)
cat > /etc/cron.d/coolify-control-backup << EOF
0 2 * * * ubuntu /data/backups/backup-coolify-control.sh >> /var/log/backup.log 2>&1
EOF

# Install Coolify
echo "Installing Coolify..."
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# Wait for Coolify to be ready
echo "Waiting for Coolify to start..."
sleep 30

# Create health check script
cat > /usr/local/bin/coolify-health-check.sh << 'EOF'
#!/bin/bash
# Health check for Coolify control server
if ! curl -f http://localhost:8000/api/health > /dev/null 2>&1; then
    echo "Coolify health check failed at $(date)" >> /var/log/coolify-health.log
    systemctl restart coolify
fi
EOF

chmod +x /usr/local/bin/coolify-health-check.sh

# Setup health check cron (every 5 minutes)
cat > /etc/cron.d/coolify-control-health << EOF
*/5 * * * * root /usr/local/bin/coolify-health-check.sh
EOF

# Setup log rotation
cat > /etc/logrotate.d/coolify-control << EOF
/var/log/coolify*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# Create monitoring script for control server
cat > /usr/local/bin/coolify-control-monitor.sh << 'EOF'
#!/bin/bash
# Monitor Coolify control server resources

# Send custom metrics to CloudWatch
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Docker container count (should be minimal on control server)
CONTAINER_COUNT=$(docker ps -q | wc -l)
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyControlServer" --metric-data MetricName=ContainerCount,Value=$CONTAINER_COUNT,Unit=Count

# Disk usage for /data
DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyControlServer" --metric-data MetricName=DataDiskUsage,Value=$DISK_USAGE,Unit=Percent

# Memory usage (important for micro instances)
MEM_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyControlServer" --metric-data MetricName=MemoryUsage,Value=$MEM_USAGE,Unit=Percent
EOF

chmod +x /usr/local/bin/coolify-control-monitor.sh

# Setup monitoring cron (every minute)
cat > /etc/cron.d/coolify-control-monitor << EOF
* * * * * root /usr/local/bin/coolify-control-monitor.sh
EOF

# Create maintenance script
cat > /usr/local/bin/coolify-control-maintenance.sh << 'EOF'
#!/bin/bash
# Weekly maintenance tasks for control server

echo "Starting control server maintenance at $(date)"

# Light cleanup for control server (it shouldn't have many containers)
docker system prune -f

# Clean up logs
find /var/log -name "*.log" -type f -size +50M -delete
journalctl --vacuum-time=7d

# Update packages
apt-get update -y
apt-get upgrade -y
apt-get autoremove -y

echo "Control server maintenance completed at $(date)"
EOF

chmod +x /usr/local/bin/coolify-control-maintenance.sh

# Setup maintenance cron (weekly on Sunday at 3 AM)
cat > /etc/cron.d/coolify-control-maintenance << EOF
0 3 * * 0 root /usr/local/bin/coolify-control-maintenance.sh >> /var/log/maintenance.log 2>&1
EOF

# Final setup
chown -R ubuntu:ubuntu /data
systemctl enable docker
systemctl enable coolify

echo "=== Coolify Control Server Installation Complete ==="
echo "Timestamp: $(date)"
echo "Access Coolify at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Check logs with: tail -f /var/log/user-data.log"

# Reboot to ensure everything is properly loaded
shutdown -r +1 "Rebooting to complete Coolify control server installation"