#!/bin/bash
# terraform/user_data.sh

set -e

# Variables from Terraform
BUCKET_NAME="${bucket_name}"
REGION="${region}"
DOMAIN_NAME="${domain_name}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting Coolify Installation ==="
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
    certbot

# Configure timezone
timedatectl set-timezone UTC

# Setup firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8000/tcp
ufw allow 3000:9000/tcp
ufw --force enable

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Setup Docker
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Create swap file (recommended for ARM instances)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Mount additional EBS volume
echo "Waiting for EBS volume..."
while [ ! -e /dev/nvme1n1 ]; do
    sleep 5
done

# Format and mount data volume
mkfs.ext4 /dev/nvme1n1
mkdir -p /data
mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data ext4 defaults,nofail 0 2' >> /etc/fstab

# Create directories
mkdir -p /data/coolify
mkdir -p /data/docker
mkdir -p /data/backups
chown -R ubuntu:ubuntu /data

# Configure Docker to use data volume
service docker stop
mkdir -p /data/docker
rsync -aP /var/lib/docker/ /data/docker/
mv /var/lib/docker /var/lib/docker.old
ln -s /data/docker /var/lib/docker
service docker start

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "CoolifyServer",
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
            "diskio": {
                "measurement": [
                    "io_time"
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
                        "log_stream_name": "{instance_id}/coolify"
                    },
                    {
                        "file_path": "/var/log/docker.log",
                        "log_group_name": "/aws/ec2/coolify",
                        "log_stream_name": "{instance_id}/docker"
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

# Setup backup script
cat > /data/backups/backup-coolify.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="coolify-backup-$TIMESTAMP.tar.gz"

echo "Starting backup at $(date)"

# Create backup
cd /data
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude='./backups' \
    --exclude='./docker/containers/*/logs' \
    --exclude='./docker/tmp' \
    ./coolify

# Upload to S3
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$BUCKET_NAME/"

# Clean up local backup
rm "$BACKUP_DIR/$BACKUP_FILE"

echo "Backup completed at $(date)"
EOF

chmod +x /data/backups/backup-coolify.sh
chown ubuntu:ubuntu /data/backups/backup-coolify.sh

# Setup cron for backups (daily at 2 AM)
cat > /etc/cron.d/coolify-backup << EOF
0 2 * * * ubuntu /data/backups/backup-coolify.sh >> /var/log/backup.log 2>&1
EOF

# Install Coolify
echo "Installing Coolify..."
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# Wait for Coolify to be ready
echo "Waiting for Coolify to start..."
sleep 30

# Configure Coolify domain if provided
if [ ! -z "$DOMAIN_NAME" ]; then
    echo "Configuring domain: $DOMAIN_NAME"
    # This would typically be done through Coolify's API or configuration
    # For now, we'll just log it
    echo "Domain configuration: $DOMAIN_NAME" >> /var/log/coolify-setup.log
fi

# Create health check script
cat > /usr/local/bin/coolify-health-check.sh << 'EOF'
#!/bin/bash
# Health check for Coolify
if ! curl -f http://localhost:8000/api/health > /dev/null 2>&1; then
    echo "Coolify health check failed at $(date)" >> /var/log/coolify-health.log
    systemctl restart coolify
fi
EOF

chmod +x /usr/local/bin/coolify-health-check.sh

# Setup health check cron (every 5 minutes)
cat > /etc/cron.d/coolify-health << EOF
*/5 * * * * root /usr/local/bin/coolify-health-check.sh
EOF

# Setup log rotation
cat > /etc/logrotate.d/coolify << EOF
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

# Create monitoring script
cat > /usr/local/bin/coolify-monitor.sh << 'EOF'
#!/bin/bash
# Monitor Coolify resources

# Send custom metrics to CloudWatch
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Docker container count
CONTAINER_COUNT=$(docker ps -q | wc -l)
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyServer" --metric-data MetricName=ContainerCount,Value=$CONTAINER_COUNT,Unit=Count

# Disk usage for /data
DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyServer" --metric-data MetricName=DataDiskUsage,Value=$DISK_USAGE,Unit=Percent

# Memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyServer" --metric-data MetricName=MemoryUsage,Value=$MEM_USAGE,Unit=Percent
EOF

chmod +x /usr/local/bin/coolify-monitor.sh

# Setup monitoring cron (every minute)
cat > /etc/cron.d/coolify-monitor << EOF
* * * * * root /usr/local/bin/coolify-monitor.sh
EOF

# Create maintenance script
cat > /usr/local/bin/coolify-maintenance.sh << 'EOF'
#!/bin/bash
# Weekly maintenance tasks

echo "Starting maintenance at $(date)"

# Clean up Docker
docker system prune -f
docker volume prune -f
docker image prune -f

# Clean up logs
find /var/log -name "*.log" -type f -size +100M -delete
journalctl --vacuum-time=7d

# Update packages
apt-get update -y
apt-get upgrade -y
apt-get autoremove -y

echo "Maintenance completed at $(date)"
EOF

chmod +x /usr/local/bin/coolify-maintenance.sh

# Setup maintenance cron (weekly on Sunday at 3 AM)
cat > /etc/cron.d/coolify-maintenance << EOF
0 3 * * 0 root /usr/local/bin/coolify-maintenance.sh >> /var/log/maintenance.log 2>&1
EOF

# Final setup
chown -R ubuntu:ubuntu /data
systemctl enable docker
systemctl enable coolify

echo "=== Coolify Installation Complete ==="
echo "Timestamp: $(date)"
echo "Access Coolify at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
echo "Check logs with: tail -f /var/log/user-data.log"

# Reboot to ensure everything is properly loaded
shutdown -r +1 "Rebooting to complete Coolify installation"