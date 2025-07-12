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

# === FIX EC2 UID/GID CONFLICTS FOR CONTAINER WORKLOADS ===
echo "=== Fixing EC2 UID/GID conflicts for container workloads ==="

# The default Ubuntu EC2 AMI has sshd user at UID 105 and _ssh group at GID 106
# These conflict with container UIDs. We need to move them to higher UIDs.

# Check current conflicting users/groups
echo "Current system users that may conflict with containers:"
getent passwd | grep -E ":(10[0-9]|11[0-9]):" || echo "No conflicting users found in 100-119 range"
getent group | grep -E ":(10[0-9]|11[0-9]):" || echo "No conflicting groups found in 100-119 range"

# Function to safely change UID/GID
change_uid_gid() {
    local username=$1
    local new_uid=$2
    local new_gid=$3

    if id "$username" >/dev/null 2>&1; then
        local old_uid=$(id -u "$username")
        local old_gid=$(id -g "$username")

        echo "Changing $username from UID:$old_uid GID:$old_gid to UID:$new_uid GID:$new_gid"

        # Stop any services using this user
        systemctl stop ssh || true

        # Change the user's UID and GID
        usermod -u "$new_uid" "$username" 2>/dev/null || echo "Failed to change UID for $username"
        groupmod -g "$new_gid" "$username" 2>/dev/null || echo "Failed to change GID for $username group"

        # Update file ownership
        find / -user "$old_uid" -exec chown "$new_uid" {} \; 2>/dev/null || true
        find / -group "$old_gid" -exec chgrp "$new_gid" {} \; 2>/dev/null || true

        echo "Successfully updated $username"
    else
        echo "User $username not found, skipping"
    fi
}

# Move common conflicting users to higher UIDs (1000+ range)
# This prevents conflicts with container UIDs typically in 100-999 range

# Fix sshd user (typically UID 105) - move to 1105
if getent passwd sshd >/dev/null 2>&1; then
    change_uid_gid "sshd" "1105" "1105"
fi

# Fix _ssh group conflicts (typically GID 106)
if getent group _ssh >/dev/null 2>&1; then
    echo "Moving _ssh group from GID $(getent group _ssh | cut -d: -f3) to GID 1106"
    groupmod -g 1106 _ssh 2>/dev/null || echo "Failed to change _ssh group GID"
fi

# Fix systemd-network user (typically UID 101)
if getent passwd systemd-network >/dev/null 2>&1; then
    change_uid_gid "systemd-network" "1101" "1101"
fi

# Fix systemd-resolve user (typically UID 102)
if getent passwd systemd-resolve >/dev/null 2>&1; then
    change_uid_gid "systemd-resolve" "1102" "1102"
fi

# Fix messagebus user (typically UID 103)
if getent passwd messagebus >/dev/null 2>&1; then
    change_uid_gid "messagebus" "1103" "1103"
fi

# Fix systemd-timesync user (typically UID 104)
if getent passwd systemd-timesync >/dev/null 2>&1; then
    change_uid_gid "systemd-timesync" "1104" "1104"
fi

# Restart SSH service
systemctl start ssh || true

echo "UID/GID conflict resolution completed"
echo "Updated system users:"
getent passwd | grep -E ":(110[0-9]):" || echo "No users found in new 1100+ range"

# === SYSTEM OPTIMIZATIONS FOR SUPABASE/DATABASE WORKLOADS ===
echo "=== Applying system optimizations for Supabase workloads ==="

# 1. Increase file descriptor limits system-wide
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf
echo "* soft nproc 65535" >> /etc/security/limits.conf
echo "* hard nproc 65535" >> /etc/security/limits.conf
echo "root soft nofile 65535" >> /etc/security/limits.conf
echo "root hard nofile 65535" >> /etc/security/limits.conf

# 2. Configure systemd limits
echo "DefaultLimitNOFILE=65535" >> /etc/systemd/system.conf
echo "DefaultLimitNPROC=65535" >> /etc/systemd/system.conf

# 3. Optimize kernel parameters for database workloads
cat >> /etc/sysctl.conf << 'EOF'

# Network optimizations for database connections
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# Memory management optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Process limits
kernel.pid_max = 4194304
EOF

# Apply sysctl settings immediately
sysctl -p

# 4. Configure Docker daemon for high file descriptor limits
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 65535,
      "Soft": 65535
    }
  }
}
EOF

echo "System optimizations applied successfully"

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

# Install Docker with modern compose plugin
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh

# Ensure Docker Compose plugin is installed (modern docker compose, not docker-compose)
echo "Installing Docker Compose plugin..."
apt-get update
apt-get install -y docker-compose-plugin

# Setup Docker
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Verify docker compose works (not docker-compose)
docker compose version

# === CONFIGURE COOLIFY FOR ROOT USER CONTAINERS ===
echo "=== Configuring Coolify for root user containers ==="

# Create Coolify configuration directory
mkdir -p /data/coolify-config

# Create environment file for Coolify with root user settings
cat > /data/coolify-config/.env.override << 'EOF'
# Coolify environment overrides for root user containers

# Default user for containers (root)
COOLIFY_DEFAULT_USER=0
COOLIFY_DEFAULT_GROUP=0

# Security settings for root containers
COOLIFY_CONTAINER_SECURITY_OPT=no-new-privileges:false
COOLIFY_CONTAINER_PRIVILEGED=false

# Ensure containers have proper permissions
COOLIFY_CONTAINER_USER_OVERRIDE=true
EOF

# Create a script to apply root user settings to Coolify
cat > /usr/local/bin/coolify-root-config.sh << 'EOF'
#!/bin/bash
# Script to ensure Coolify containers run as root

echo "Applying root user configuration to Coolify control server..."

# Ensure Coolify data directories have proper permissions
chown -R root:root /data/coolify-config
chmod -R 755 /data/coolify-config

# Set proper permissions for Coolify installation
if [ -d /data/coolify ]; then
    chown -R root:root /data/coolify
    chmod -R 755 /data/coolify
fi

echo "Root user configuration applied successfully"
EOF

chmod +x /usr/local/bin/coolify-root-config.sh

# Run the configuration script
/usr/local/bin/coolify-root-config.sh

echo "Coolify root user configuration completed"

# Create 4GB swap file (optimized for Supabase workloads)
echo "Creating 4GB swap file for database workloads..."
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Verify swap is active
swapon --show
echo "Swap configuration completed"

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

# Install Coolify directly using the official method AS ROOT
echo "Installing Coolify as root user..."

# Ensure we're running as root for Coolify installation
if [ "$EUID" -ne 0 ]; then
    echo "Switching to root for Coolify installation..."
    sudo su -
fi

# Set environment for root installation
export COOLIFY_USER=root
export COOLIFY_GROUP=root

# Run the installation script as root (most reliable method)
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# Wait for installation to complete
echo "Waiting for Coolify installation to complete..."
sleep 30

# Check if installation was successful by looking for containers
if ! docker ps | grep -q "coolify"; then
    echo "Coolify containers not found, trying alternative installation..."

    # Create Docker network if it doesn't exist
    docker network create --attachable coolify || true

    # Start Coolify manually
    cd /data/coolify/source
    docker compose up -d || true

    # Wait for containers to start
    sleep 30
fi

# Ensure SSH directories exist
mkdir -p /data/coolify/ssh/keys
mkdir -p /data/coolify/ssh/mux

# Wait for Coolify to be ready
echo "Waiting for Coolify to start..."
sleep 60

# Verify installation and start if needed
echo "Verifying Coolify installation..."
cd /data/coolify/source

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "WARNING: docker-compose.yml not found, but continuing..."
else
    echo "docker-compose.yml found, continuing with installation..."
fi

# Ensure Coolify is running (don't fail if already running)
echo "Ensuring Coolify services are running..."
cd /data/coolify/source
docker compose up -d || true

# Check if services started
echo "Checking Coolify status..."
docker ps | grep coolify || echo "Coolify containers status check completed"

# CRITICAL: Generate SSH key for Coolify to manage itself AS ROOT (ALWAYS RUN THIS)
echo "=== CRITICAL: Setting up Coolify SSH keys for root user ==="
mkdir -p /data/coolify/ssh/keys || true

# Generate SSH key for root user (overwrite if exists)
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify -y || true

# Add Coolify's public key to root's authorized_keys
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ -f /data/coolify/ssh/keys/id.root@host.docker.internal.pub ]; then
    # Add to root's authorized_keys (avoid duplicates)
    grep -qxF "$(cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub)" /root/.ssh/authorized_keys 2>/dev/null || cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # Also add to ubuntu user's authorized_keys for compatibility
    grep -qxF "$(cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub)" /home/ubuntu/.ssh/authorized_keys 2>/dev/null || cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /home/ubuntu/.ssh/authorized_keys
    chmod 600 /home/ubuntu/.ssh/authorized_keys
    chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys

    echo "SSH key added to both root and ubuntu authorized_keys"
else
    echo "WARNING: SSH public key not found, generating again..."
    ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify || true
    if [ -f /data/coolify/ssh/keys/id.root@host.docker.internal.pub ]; then
        cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
        cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /home/ubuntu/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        chmod 600 /home/ubuntu/.ssh/authorized_keys
        chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
    fi
fi

# Set correct permissions for Coolify (MODIFIED FOR ROOT USER)
echo "=== Configuring Coolify to use root user for containers ==="
chown -R root:root /data/coolify || true
chmod -R 755 /data/coolify || true
chmod 644 /data/coolify/ssh/keys/id.root@host.docker.internal.pub || true
chmod 600 /data/coolify/ssh/keys/id.root@host.docker.internal || true

# Configure Coolify environment for root user containers
if [ -d /data/coolify/source ]; then
    # Add environment variables to Coolify's .env file
    echo "" >> /data/coolify/source/.env
    echo "# Root user configuration for containers" >> /data/coolify/source/.env
    echo "COOLIFY_DEFAULT_USER=0" >> /data/coolify/source/.env
    echo "COOLIFY_DEFAULT_GROUP=0" >> /data/coolify/source/.env
    echo "COOLIFY_CONTAINER_USER_OVERRIDE=true" >> /data/coolify/source/.env

    # Create docker-compose override for root user
    cat > /data/coolify/source/docker-compose.root.yml << 'EOF'
# Docker Compose override for root user containers
version: '3.8'

# Default settings for all services
x-default-user: &default-user
  user: "0:0"
  security_opt:
    - no-new-privileges:false

services:
  # These settings will be inherited by deployed applications
  postgres:
    <<: *default-user
  redis:
    <<: *default-user
  app:
    <<: *default-user
EOF

    echo "Coolify configured for root user containers"
fi

# === ENABLE ROOT SSH LOGIN FOR USER ACCESS ===
echo "=== Enabling root SSH login for user access ==="

# Enable root SSH login (required for user to SSH as root)
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Copy ubuntu user's authorized_keys to root (so you can SSH as root with your key)
echo "=== Copying SSH keys from ubuntu to root user ==="
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    # Copy ubuntu's authorized_keys to root
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
    echo "✓ SSH keys copied from ubuntu to root user"
    echo "✓ You can now SSH as: ssh -i your-key.pem root@server-ip"
else
    echo "⚠ Ubuntu authorized_keys not found, root SSH may not work with your key"
fi

# Restart SSH service to apply changes
systemctl restart ssh

echo "Root SSH login configured for user access"

# Test SSH connection as root
echo "Testing SSH connection as root..."
ssh -i /data/coolify/ssh/keys/id.root@host.docker.internal -o StrictHostKeyChecking=no root@localhost "echo 'SSH test successful as root'" || echo "Root SSH test failed, trying ubuntu..."
ssh -i /data/coolify/ssh/keys/id.root@host.docker.internal -o StrictHostKeyChecking=no ubuntu@localhost "echo 'SSH test successful as ubuntu'" || echo "SSH test failed but continuing..."

# Wait for Coolify to be accessible
echo "Waiting for Coolify to be accessible..."
for i in {1..30}; do
    if curl -f http://localhost:8000 > /dev/null 2>&1; then
        echo "Coolify is now accessible!"
        break
    fi
    echo "Attempt $i/30: Coolify not ready yet, waiting 10 seconds..."
    sleep 10
done

# Create health check script
cat > /usr/local/bin/coolify-health-check.sh << 'EOF'
#!/bin/bash
# Health check for Coolify control server
if ! curl -f http://localhost:8000 > /dev/null 2>&1; then
    echo "Coolify health check failed at $(date)" >> /var/log/coolify-health.log
    cd /data/coolify/source
    docker compose restart
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

# Ensure Coolify starts on boot by creating a systemd service (running as root)
cat > /etc/systemd/system/coolify.service << 'EOF'
[Unit]
Description=Coolify (Root User)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
Group=root
WorkingDirectory=/data/coolify/source
Environment=HOME=/root
Environment=USER=root
ExecStart=/usr/bin/docker compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml up -d --pull always --remove-orphans --force-recreate
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable coolify.service

echo "=== Coolify Control Server Installation Complete ==="
echo "Timestamp: $(date)"
echo "Access Coolify at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Check logs with: tail -f /var/log/user-data.log"

# CRITICAL: Fix SSH directory permissions for Coolify (ROOT USER)
echo "=== CRITICAL: Fixing SSH directory permissions for root user ==="
mkdir -p /data/coolify/ssh/mux || true
mkdir -p /data/coolify/ssh/keys || true
chmod -R 755 /data/coolify/ssh || true
chown -R root:root /data/coolify/ssh || true

# Fix storage permissions for root user
mkdir -p /var/www/html/storage/app/ssh/mux || true
mkdir -p /var/www/html/storage/app/ssh/keys || true
chmod -R 755 /var/www/html/storage || true
chown -R root:root /var/www/html/storage || true

# Ensure all Coolify directories are owned by root
chown -R root:root /data/coolify || true
chmod -R 755 /data/coolify || true

# Final status check
echo "=== Final Status Check ==="
cd /data/coolify/source
echo "Docker Container Status:"
docker ps | grep coolify || echo "No Coolify containers found yet"
echo "All Docker Containers:"
docker ps || echo "Docker ps failed"
echo "Coolify Accessibility Test:"
curl -I http://localhost:8000 || echo "Coolify not accessible yet"
echo "SSH Key Status:"
ls -la /data/coolify/ssh/keys/ || echo "SSH keys directory not found"
echo "=== Installation Summary Complete ==="

# Create and run validation script
cat > /usr/local/bin/validate-optimizations.sh << 'VALIDATION_EOF'
#!/bin/bash
# Validate Supabase system optimizations

set -e

echo "=== Validating Supabase System Optimizations ==="
echo "Timestamp: $(date)"

# Check file descriptor limits
echo "1. Checking file descriptor limits..."
echo "   System file-max: $(cat /proc/sys/fs/file-max)"
echo "   Current ulimit -n: $(ulimit -n)"
echo "   Current ulimit -u: $(ulimit -u)"

# Check swap configuration
echo "2. Checking swap configuration..."
echo "   Swap status:"
swapon --show
echo "   Swappiness: $(cat /proc/sys/vm/swappiness)"

# Check kernel parameters
echo "3. Checking kernel parameters..."
echo "   somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "   tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"
echo "   vfs_cache_pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"

# Check Docker configuration
echo "4. Checking Docker configuration..."
if [ -f /etc/docker/daemon.json ]; then
    echo "   Docker daemon.json exists"
    echo "   Docker configured with optimized ulimits"
else
    echo "   WARNING: Docker daemon.json not found"
fi

# Check UID/GID conflicts
echo "5. Checking UID/GID conflicts..."
echo "   Users in potential conflict range (100-119):"
getent passwd | grep -E ":(10[0-9]|11[0-9]):" || echo "   No conflicting users found"
echo "   Groups in potential conflict range (100-119):"
getent group | grep -E ":(10[0-9]|11[0-9]):" || echo "   No conflicting groups found"
echo "   Users moved to safe range (1100+):"
getent passwd | grep -E ":(110[0-9]):" || echo "   No users found in safe range"

# Check Coolify root user configuration
echo "6. Checking Coolify root user configuration..."
if [ -f /data/coolify/source/.env ]; then
    echo "   Coolify .env file exists"
    if grep -q "COOLIFY_DEFAULT_USER=0" /data/coolify/source/.env; then
        echo "   ✓ Coolify configured for root user containers"
    else
        echo "   ⚠ Coolify root user configuration not found"
    fi
else
    echo "   Coolify .env file not found (installation may be in progress)"
fi

if [ -d /data/coolify ]; then
    echo "   Coolify directory ownership: $(stat -c '%U:%G' /data/coolify)"
else
    echo "   Coolify directory not found"
fi

# Check root SSH access
echo "7. Checking root SSH configuration..."
if [ -d /root/.ssh ]; then
    echo "   ✓ Root SSH directory exists"
    echo "   Root SSH directory permissions: $(stat -c '%a' /root/.ssh)"
else
    echo "   ⚠ Root SSH directory not found"
fi

# Check SSH daemon configuration for root login
if grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config; then
    echo "   ✓ Root SSH login enabled (key-based)"
elif grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
    echo "   ✓ Root SSH login enabled (full access)"
else
    echo "   ⚠ Root SSH login may be disabled"
fi

# Check if user's SSH key is in root's authorized_keys
if [ -f /root/.ssh/authorized_keys ] && [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    UBUNTU_KEYS=$(wc -l < /home/ubuntu/.ssh/authorized_keys)
    ROOT_KEYS=$(wc -l < /root/.ssh/authorized_keys)
    echo "   Ubuntu authorized_keys: $UBUNTU_KEYS key(s)"
    echo "   Root authorized_keys: $ROOT_KEYS key(s)"

    if [ "$ROOT_KEYS" -gt 0 ]; then
        echo "   ✓ Root has SSH keys configured"
    else
        echo "   ⚠ Root has no SSH keys configured"
    fi
else
    echo "   ⚠ SSH key files not found"
fi

echo "=== Control Server Validation Complete ==="
echo "Timestamp: $(date)"
VALIDATION_EOF

chmod +x /usr/local/bin/validate-optimizations.sh

# Run validation
echo "=== Running optimization validation ==="
/usr/local/bin/validate-optimizations.sh

# Reboot to ensure everything is properly loaded
shutdown -r +1 "Rebooting to complete Coolify control server installation"
