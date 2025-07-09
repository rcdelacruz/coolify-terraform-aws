#!/bin/bash
# terraform/remote_user_data.sh - Coolify Remote Server Setup

set -e

# Variables from Terraform
BUCKET_NAME="${bucket_name}"
REGION="${region}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting Coolify Remote Server Installation ==="
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
    openssh-server

# Configure timezone
timedatectl set-timezone UTC

# Setup firewall for remote server (optimized for application hosting)
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp     # HTTP for applications
ufw allow 443/tcp    # HTTPS for applications
ufw allow 3000:9000/tcp  # Application ports range
ufw allow from 10.0.0.0/16 to any port 2376  # Docker daemon for control server
ufw --force enable

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Setup Docker
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Configure Docker daemon for remote management
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2376"],
  "tls": false,
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

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
mkdir -p /data/docker
mkdir -p /data/applications
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

# CloudWatch agent configuration for remote server
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "CoolifyRemoteServer",
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
                        "file_path": "/var/log/docker.log",
                        "log_group_name": "/aws/ec2/coolify",
                        "log_stream_name": "{instance_id}/docker-remote"
                    },
                    {
                        "file_path": "/var/log/applications.log",
                        "log_group_name": "/aws/ec2/coolify",
                        "log_stream_name": "{instance_id}/applications"
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

# Setup backup script for remote server
cat > /data/backups/backup-remote-server.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/data/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="remote-server-backup-$TIMESTAMP.tar.gz"
SERVER_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

echo "Starting remote server backup at $(date)"

# Create backup of application data and Docker volumes
cd /data
tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    --exclude='./backups' \
    --exclude='./docker/containers/*/logs' \
    --exclude='./docker/tmp' \
    ./applications \
    ./docker/volumes

# Upload to S3
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$BUCKET_NAME/remote/$SERVER_ID/"

# Clean up local backup
rm "$BACKUP_DIR/$BACKUP_FILE"

echo "Remote server backup completed at $(date)"
EOF

chmod +x /data/backups/backup-remote-server.sh
chown ubuntu:ubuntu /data/backups/backup-remote-server.sh

# Setup cron for backups (daily at 3 AM)
cat > /etc/cron.d/coolify-remote-backup << EOF
0 3 * * * ubuntu /data/backups/backup-remote-server.sh >> /var/log/backup.log 2>&1
EOF

# Setup log rotation
cat > /etc/logrotate.d/coolify-remote << EOF
/var/log/docker*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
/var/log/applications*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# Create monitoring script for remote server
cat > /usr/local/bin/coolify-remote-monitor.sh << 'EOF'
#!/bin/bash
# Monitor Coolify remote server resources

# Send custom metrics to CloudWatch
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Docker container count (applications running)
CONTAINER_COUNT=$(docker ps -q | wc -l)
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyRemoteServer" --metric-data MetricName=ContainerCount,Value=$CONTAINER_COUNT,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID

# Disk usage for /data (where applications are stored)
DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyRemoteServer" --metric-data MetricName=DataDiskUsage,Value=$DISK_USAGE,Unit=Percent,Dimensions=InstanceId=$INSTANCE_ID

# Memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyRemoteServer" --metric-data MetricName=MemoryUsage,Value=$MEM_USAGE,Unit=Percent,Dimensions=InstanceId=$INSTANCE_ID

# Docker daemon health check
if docker info > /dev/null 2>&1; then
    DOCKER_HEALTH=1
else
    DOCKER_HEALTH=0
fi
aws cloudwatch put-metric-data --region $REGION --namespace "CoolifyRemoteServer" --metric-data MetricName=DockerHealth,Value=$DOCKER_HEALTH,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID
EOF

chmod +x /usr/local/bin/coolify-remote-monitor.sh

# Setup monitoring cron (every minute)
cat > /etc/cron.d/coolify-remote-monitor << EOF
* * * * * root /usr/local/bin/coolify-remote-monitor.sh
EOF

# Create maintenance script for remote server
cat > /usr/local/bin/coolify-remote-maintenance.sh << 'EOF'
#!/bin/bash
# Weekly maintenance tasks for remote server

echo "Starting remote server maintenance at $(date)"

# Cleanup Docker (important for application servers)
docker system prune -f
docker volume prune -f
docker image prune -f

# Clean up application logs
find /data/applications -name "*.log" -type f -size +100M -delete

# Clean up system logs
find /var/log -name "*.log" -type f -size +100M -delete
journalctl --vacuum-time=7d

# Update packages
apt-get update -y
apt-get upgrade -y
apt-get autoremove -y

echo "Remote server maintenance completed at $(date)"
EOF

chmod +x /usr/local/bin/coolify-remote-maintenance.sh

# Setup maintenance cron (weekly on Sunday at 4 AM - after control server)
cat > /etc/cron.d/coolify-remote-maintenance << EOF
0 4 * * 0 root /usr/local/bin/coolify-remote-maintenance.sh >> /var/log/maintenance.log 2>&1
EOF

# Create Docker health check script
cat > /usr/local/bin/docker-health-check.sh << 'EOF'
#!/bin/bash
# Health check for Docker daemon on remote server
if ! docker info > /dev/null 2>&1; then
    echo "Docker daemon health check failed at $(date)" >> /var/log/docker-health.log
    systemctl restart docker
fi
EOF

chmod +x /usr/local/bin/docker-health-check.sh

# Setup Docker health check cron (every 5 minutes)
cat > /etc/cron.d/docker-health << EOF
*/5 * * * * root /usr/local/bin/docker-health-check.sh
EOF

# Prepare SSH keys directory for Coolify access
mkdir -p /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Final setup
chown -R ubuntu:ubuntu /data
systemctl enable docker

# Configure Docker daemon to start properly
systemctl edit docker --full << 'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always

# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable docker
systemctl start docker

echo "=== Coolify Remote Server Installation Complete ==="
echo "Timestamp: $(date)"
echo "Server ready for Coolify deployment management"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Docker daemon listening on: 0.0.0.0:2376"
echo "Check logs with: tail -f /var/log/user-data.log"

# Reboot to ensure everything is properly loaded
shutdown -r +1 "Rebooting to complete Coolify remote server installation"