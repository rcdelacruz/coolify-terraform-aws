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

# === FIX EC2 UID/GID CONFLICTS FOR POSTGRESQL CONTAINERS ===
echo "=== Fixing EC2 UID/GID conflicts for PostgreSQL containers ==="

# The default Ubuntu EC2 AMI has sshd user at UID 105 and _ssh group at GID 106
# These conflict with PostgreSQL container UIDs. We need to move them to higher UIDs.

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

# 1. Increase file descriptor limits system-wide (critical for PostgreSQL)
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
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# Memory management optimizations (tuned for database workloads)
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 2
vm.overcommit_ratio = 80

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Process limits
kernel.pid_max = 4194304

# Shared memory settings for PostgreSQL
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
EOF

# Apply sysctl settings immediately
sysctl -p

# 4. Configure Docker daemon for HIGH CONTAINER DENSITY on Graviton
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "2"
  },
  "storage-driver": "overlay2",
  "data-root": "/data/docker",
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 1048576,
      "Soft": 1048576
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 1048576,
      "Soft": 1048576
    },
    "memlock": {
      "Name": "memlock",
      "Hard": -1,
      "Soft": -1
    }
  },
  "storage-opts": [
    "overlay2.override_kernel_check=true",
    "overlay2.size=20G"
  ],
  "default-shm-size": "128M",
  "userland-proxy": false,
  "live-restore": true,
  "experimental": false,
  "features": {
    "buildkit": true
  },
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "10GB"
    }
  }
}
EOF

echo "System optimizations applied successfully"

# === GRAVITON-SPECIFIC OPTIMIZATIONS FOR HIGH CONTAINER DENSITY ===
echo "=== Applying Graviton ARM64 optimizations for high container density ==="

# 1. ARM64/Graviton-specific kernel parameters
cat >> /etc/sysctl.conf << 'EOF'

# Graviton ARM64 optimizations for high container density
# CPU and scheduling optimizations
kernel.sched_migration_cost_ns = 500000
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000
kernel.sched_child_runs_first = 0

# Memory management for high container density
vm.min_free_kbytes = 131072
vm.zone_reclaim_mode = 0
vm.page_cluster = 3
vm.drop_caches = 1

# Network optimizations for many containers
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr

# Container networking optimizations
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1

# Increase connection tracking for many containers
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_buckets = 262144
net.netfilter.nf_conntrack_tcp_timeout_established = 86400

# File system optimizations for container layers
fs.aio-max-nr = 1048576
fs.nr_open = 1048576

# Process and thread limits for high density
kernel.threads-max = 4194304
kernel.pid_max = 4194304
vm.max_map_count = 2147483647
EOF

# Apply sysctl settings
sysctl -p

# 2. Configure CPU governor for performance (Graviton benefits from performance governor)
echo "=== Configuring CPU governor for Graviton performance ==="
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo "CPU governor set to performance"

    # Make it persistent
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
else
    echo "CPU frequency scaling not available (may be managed by hypervisor)"
fi

# 3. Optimize for container density - increase limits dramatically
echo "=== Optimizing system limits for high container density ==="

# Update limits.conf for extreme container density
cat >> /etc/security/limits.conf << 'EOF'

# High container density limits
* soft nproc 1048576
* hard nproc 1048576
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
root soft nproc 1048576
root hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

# Update systemd limits for high density
cat >> /etc/systemd/system.conf << 'EOF'

# High container density systemd limits
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultTasksMax=infinity
EOF

# Update systemd user limits
cat >> /etc/systemd/user.conf << 'EOF'

# High container density user limits
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultTasksMax=infinity
EOF

# 4. Configure huge pages for better memory management with many containers
echo "=== Configuring huge pages for container density ==="
# Calculate huge pages (use 25% of available memory for huge pages)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
HUGEPAGE_SIZE_KB=2048  # 2MB huge pages
HUGEPAGES_COUNT=$((TOTAL_MEM_KB / HUGEPAGE_SIZE_KB / 4))  # 25% of memory

echo "vm.nr_hugepages = $HUGEPAGES_COUNT" >> /etc/sysctl.conf
echo "Configured $HUGEPAGES_COUNT huge pages (2MB each)"

# 5. Optimize I/O for container layers and volumes
echo "=== Optimizing I/O for container workloads ==="

# Set I/O scheduler for all block devices
echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"' > /etc/udev/rules.d/60-io-scheduler.rules
echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"' >> /etc/udev/rules.d/60-io-scheduler.rules

# Optimize read-ahead for container images
echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{bdi/read_ahead_kb}="1024"' >> /etc/udev/rules.d/60-io-scheduler.rules
echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{bdi/read_ahead_kb}="1024"' >> /etc/udev/rules.d/60-io-scheduler.rules

echo "Graviton ARM64 optimizations applied successfully"

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

# Install Docker - SIMPLE AS FUCK
echo "Installing Docker..."

# Remove any existing Docker
apt-get remove -y docker docker-engine docker.io containerd runc || true

# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# Just use the default Docker service but configure it properly
systemctl stop docker || true

# Create simple daemon.json WITHOUT hosts (let systemd handle sockets)
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

# Enable Docker to listen on TCP via systemd drop-in
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/tcp.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2376
EOF

# Start Docker
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Wait for it to be ready
sleep 10

# Create 4GB swap file (optimized for Supabase database workloads)
echo "Creating 4GB swap file for database workloads..."
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Verify swap is active
swapon --show
echo "Swap configuration completed"

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

# Docker data is already configured to use /data/docker in the startup script
echo "Docker data directory is already configured for /data/docker"

# === ADDITIONAL OPTIMIZATIONS FOR SUPABASE ===
echo "=== Applying additional Supabase optimizations ==="

# Create optimized tmpfs for PostgreSQL temporary files
mkdir -p /data/postgres-tmp
echo "tmpfs /data/postgres-tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=1G 0 0" >> /etc/fstab
mount -a

# Optimize I/O scheduler for database workloads (use mq-deadline for better database performance)
echo 'ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"' > /etc/udev/rules.d/60-scheduler.rules

# Set up huge pages for better memory management (PostgreSQL can benefit from this)
echo "vm.nr_hugepages = 128" >> /etc/sysctl.conf
sysctl -p

# Create a systemd service to ensure optimizations persist after reboot
cat > /etc/systemd/system/supabase-optimizations.service << 'EOF'
[Unit]
Description=Supabase System Optimizations
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'echo mq-deadline > /sys/block/nvme0n1/queue/scheduler; echo mq-deadline > /sys/block/nvme1n1/queue/scheduler'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable supabase-optimizations.service

echo "Additional Supabase optimizations applied"

# === HIGH CONTAINER DENSITY MANAGEMENT SCRIPTS ===
echo "=== Creating container density management scripts ==="

# Create container monitoring script
cat > /usr/local/bin/container-density-monitor.sh << 'EOF'
#!/bin/bash
# Monitor container density and system resources

echo "=== Container Density Report $(date) ==="

# Container statistics
RUNNING_CONTAINERS=$(docker ps -q | wc -l)
TOTAL_CONTAINERS=$(docker ps -aq | wc -l)
IMAGES_COUNT=$(docker images -q | wc -l)
VOLUMES_COUNT=$(docker volume ls -q | wc -l)
NETWORKS_COUNT=$(docker network ls -q | wc -l)

echo "Containers: $RUNNING_CONTAINERS running, $TOTAL_CONTAINERS total"
echo "Images: $IMAGES_COUNT"
echo "Volumes: $VOLUMES_COUNT"
echo "Networks: $NETWORKS_COUNT"

# Memory usage
MEMORY_TOTAL=$(free -m | awk 'NR==2{printf "%.0f", $2}')
MEMORY_USED=$(free -m | awk 'NR==2{printf "%.0f", $3}')
MEMORY_PERCENT=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')

echo "Memory: $${MEMORY_USED}MB / $${MEMORY_TOTAL}MB ($${MEMORY_PERCENT}%)"

# CPU load
LOAD_1MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_CORES=$(nproc)
echo "Load: $LOAD_1MIN ($${CPU_CORES} cores)"

# Disk usage
DISK_USAGE=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_USED=$(df -h /data | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -h /data | tail -1 | awk '{print $2}')
echo "Disk: $${DISK_USED} / $${DISK_TOTAL} ($${DISK_USAGE}%)"

# Docker system usage
echo ""
echo "Docker System Usage:"
docker system df

# Top containers by resource usage
echo ""
echo "Top 10 containers by memory usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -11

# Check for any resource warnings
if [ "$MEMORY_PERCENT" -gt 85 ]; then
    echo "⚠️  WARNING: Memory usage above 85%"
fi

if [ "$DISK_USAGE" -gt 85 ]; then
    echo "⚠️  WARNING: Disk usage above 85%"
fi

if [ "$RUNNING_CONTAINERS" -gt 100 ]; then
    echo "ℹ️  INFO: High container density detected ($RUNNING_CONTAINERS containers)"
fi

echo "=== End Report ==="
EOF

chmod +x /usr/local/bin/container-density-monitor.sh

# Create container cleanup script for high density
cat > /usr/local/bin/container-density-cleanup.sh << 'EOF'
#!/bin/bash
# Cleanup script optimized for high container density

echo "=== Container Density Cleanup $(date) ==="

# Remove stopped containers
STOPPED_CONTAINERS=$(docker ps -aq --filter "status=exited" | wc -l)
if [ "$STOPPED_CONTAINERS" -gt 0 ]; then
    echo "Removing $STOPPED_CONTAINERS stopped containers..."
    docker container prune -f
fi

# Remove unused images (keep recent ones)
echo "Removing unused images..."
docker image prune -f

# Remove unused volumes (be careful with this)
UNUSED_VOLUMES=$(docker volume ls -qf dangling=true | wc -l)
if [ "$UNUSED_VOLUMES" -gt 0 ]; then
    echo "Removing $UNUSED_VOLUMES unused volumes..."
    docker volume prune -f
fi

# Remove unused networks
echo "Removing unused networks..."
docker network prune -f

# Clean build cache but keep recent builds
echo "Cleaning build cache (keeping 10GB)..."
docker builder prune -f --keep-storage 10GB

# System-wide cleanup
echo "Running system cleanup..."
docker system prune -f

echo "Cleanup completed at $(date)"
EOF

chmod +x /usr/local/bin/container-density-cleanup.sh

# Create container optimization script
cat > /usr/local/bin/container-optimize.sh << 'EOF'
#!/bin/bash
# Optimize system for current container load

echo "=== Container Optimization $(date) ==="

# Get current container count
CONTAINER_COUNT=$(docker ps -q | wc -l)
echo "Current containers: $CONTAINER_COUNT"

# Adjust kernel parameters based on container count
if [ "$CONTAINER_COUNT" -gt 50 ]; then
    echo "High container density detected, applying optimizations..."

    # Increase network connection tracking
    echo 2097152 > /proc/sys/net/netfilter/nf_conntrack_max

    # Optimize memory management
    echo 1 > /proc/sys/vm/drop_caches

    # Adjust CPU scheduling for many processes
    echo 1000000 > /proc/sys/kernel/sched_migration_cost_ns

    echo "High-density optimizations applied"
elif [ "$CONTAINER_COUNT" -gt 20 ]; then
    echo "Medium container density, applying moderate optimizations..."

    echo 1048576 > /proc/sys/net/netfilter/nf_conntrack_max
    echo "Medium-density optimizations applied"
else
    echo "Low container density, using default settings"
fi

echo "Optimization completed"
EOF

chmod +x /usr/local/bin/container-optimize.sh

# Setup cron jobs for container density management
cat > /etc/cron.d/container-density << EOF
# Container density monitoring and optimization
*/15 * * * * root /usr/local/bin/container-optimize.sh >> /var/log/container-optimize.log 2>&1
0 2 * * * root /usr/local/bin/container-density-cleanup.sh >> /var/log/container-cleanup.log 2>&1
0 */6 * * * root /usr/local/bin/container-density-monitor.sh >> /var/log/container-monitor.log 2>&1
EOF

echo "Container density management scripts created"

# === CONFIGURE COOLIFY FOR ROOT USER CONTAINERS ===
echo "=== Configuring Coolify for root user containers ==="

# Create Coolify configuration directory
mkdir -p /data/coolify-config

# Create Docker Compose override for Coolify to ensure containers run as root
cat > /data/coolify-config/docker-compose.override.yml << 'EOF'
# Override file to ensure Coolify containers run as root
# This eliminates UID/GID conflicts with PostgreSQL and other database containers

version: '3.8'

# Default configuration for all services
x-default-config: &default-config
  user: "0:0"  # Run as root (UID:GID 0:0)
  security_opt:
    - no-new-privileges:false
  cap_add:
    - SYS_ADMIN
    - DAC_OVERRIDE
    - CHOWN
    - FOWNER
    - SETUID
    - SETGID

services:
  # This will be applied to any services Coolify creates
  # The override ensures they run with root privileges
EOF

# Create environment file for Coolify with root user settings
cat > /data/coolify-config/.env.override << 'EOF'
# Coolify environment overrides for root user containers

# Default user for containers (root)
COOLIFY_DEFAULT_USER=0
COOLIFY_DEFAULT_GROUP=0

# Security settings
COOLIFY_CONTAINER_SECURITY_OPT=no-new-privileges:false
COOLIFY_CONTAINER_PRIVILEGED=false

# PostgreSQL specific settings (for Supabase)
POSTGRES_USER=postgres
POSTGRES_UID=0
POSTGRES_GID=0

# Ensure containers have proper permissions
COOLIFY_CONTAINER_USER_OVERRIDE=true
EOF

# Create a script to apply root user settings to Coolify deployments
cat > /usr/local/bin/coolify-root-config.sh << 'EOF'
#!/bin/bash
# Script to ensure Coolify containers run as root

echo "Applying root user configuration to Coolify..."

# Set Docker to allow privileged containers for Coolify
if [ -f /etc/docker/daemon.json ]; then
    # Backup original
    cp /etc/docker/daemon.json /etc/docker/daemon.json.backup

    # Add privileged container support
    jq '. + {"default-runtime": "runc", "experimental": false}' /etc/docker/daemon.json > /tmp/daemon.json
    mv /tmp/daemon.json /etc/docker/daemon.json

    systemctl restart docker
fi

# Ensure Coolify data directories have proper permissions
chown -R root:root /data/coolify-config
chmod -R 755 /data/coolify-config

echo "Root user configuration applied successfully"
EOF

chmod +x /usr/local/bin/coolify-root-config.sh

# Run the configuration script
/usr/local/bin/coolify-root-config.sh

# Create systemd service to ensure root configuration persists
cat > /etc/systemd/system/coolify-root-config.service << 'EOF'
[Unit]
Description=Coolify Root User Configuration
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/coolify-root-config.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl enable coolify-root-config.service

echo "Coolify root user configuration completed"

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

# Prepare SSH keys directory for Coolify access (ROOT USER)
echo "=== Preparing SSH access for Coolify root user ==="

# Ensure root can SSH (for Coolify management)
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Also maintain ubuntu SSH access
mkdir -p /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh

# Enable root SSH login (required for Coolify)
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

echo "SSH configured for root user access"

# Final setup
chown -R ubuntu:ubuntu /data
systemctl enable docker

# Make sure Docker is running
echo "Verifying Docker is running..."
systemctl restart docker
sleep 5

# Verify Docker is working with detailed diagnostics
echo "Verifying Docker installation..."

# Check if Docker service is running
if systemctl is-active --quiet docker; then
    echo "✅ Docker service is active"
else
    echo "❌ Docker service is not active"
    echo "Docker service status:"
    systemctl status docker --no-pager || true
    echo "Docker service logs:"
    journalctl -u docker --no-pager -n 20 || true
fi

# Test Docker socket
echo "Testing Docker Unix socket..."
if docker info > /dev/null 2>&1; then
    echo "✅ Docker Unix socket is working"
    docker version
else
    echo "❌ Docker Unix socket failed"
fi

# Test Docker TCP socket
echo "Testing Docker TCP socket..."
sleep 5
if curl -s http://localhost:2376/version > /dev/null 2>&1; then
    echo "✅ Docker TCP socket is working"
    curl -s http://localhost:2376/version | jq .Version || echo "TCP socket responding"
else
    echo "❌ Docker TCP socket not responding"
    echo "Checking if port 2376 is listening:"
    netstat -tlnp | grep 2376 || echo "Port 2376 not listening"
fi

# Final Docker verification
echo "Final Docker verification:"
docker info || echo "Docker info check failed but continuing..."

echo "=== Coolify Remote Server Installation Complete ==="
echo "Timestamp: $(date)"
echo "Server ready for Coolify deployment management"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Docker daemon listening on: 0.0.0.0:2376"
echo "Check logs with: tail -f /var/log/user-data.log"

# Create and run validation script
cat > /usr/local/bin/validate-optimizations.sh << 'VALIDATION_EOF'
#!/bin/bash
# Validate Supabase system optimizations for remote server

set -e

echo "=== Validating Supabase System Optimizations (Remote Server) ==="
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
    echo "   Docker data root: $(grep data-root /etc/docker/daemon.json || echo 'Default')"
else
    echo "   WARNING: Docker daemon.json not found"
fi

# Check I/O scheduler
echo "5. Checking I/O scheduler..."
echo "   nvme0n1: $(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null || echo 'N/A')"
echo "   nvme1n1: $(cat /sys/block/nvme1n1/queue/scheduler 2>/dev/null || echo 'N/A')"

# Check huge pages
echo "6. Checking huge pages..."
echo "   Huge pages: $(cat /proc/sys/vm/nr_hugepages)"

# Check data volume
echo "7. Checking data volume..."
echo "   Data volume mount:"
df -h /data

# Check UID/GID conflicts
echo "8. Checking UID/GID conflicts..."
echo "   Users in potential conflict range (100-119):"
getent passwd | grep -E ":(10[0-9]|11[0-9]):" || echo "   No conflicting users found"
echo "   Groups in potential conflict range (100-119):"
getent group | grep -E ":(10[0-9]|11[0-9]):" || echo "   No conflicting groups found"
echo "   Users moved to safe range (1100+):"
getent passwd | grep -E ":(110[0-9]):" || echo "   No users found in safe range"

# Check Coolify root user configuration
echo "9. Checking Coolify root user configuration..."
if [ -f /data/coolify-config/.env.override ]; then
    echo "   ✓ Coolify root user override configuration exists"
    if grep -q "COOLIFY_DEFAULT_USER=0" /data/coolify-config/.env.override; then
        echo "   ✓ Root user configuration is set"
    fi
else
    echo "   ⚠ Coolify root user configuration not found"
fi

if [ -f /usr/local/bin/coolify-root-config.sh ]; then
    echo "   ✓ Root configuration script exists"
else
    echo "   ⚠ Root configuration script not found"
fi

# Check root SSH access
echo "10. Checking root SSH configuration..."
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

# Check Graviton container density optimizations
echo "11. Checking Graviton container density optimizations..."
echo "   System limits:"
echo "   - Max open files: $(ulimit -n)"
echo "   - Max processes: $(ulimit -u)"
echo "   - Connection tracking max: $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 'N/A')"

# Check container density scripts
if [ -f /usr/local/bin/container-density-monitor.sh ]; then
    echo "   ✓ Container density monitoring script exists"
else
    echo "   ⚠ Container density monitoring script not found"
fi

if [ -f /usr/local/bin/container-density-cleanup.sh ]; then
    echo "   ✓ Container density cleanup script exists"
else
    echo "   ⚠ Container density cleanup script not found"
fi

# Check CPU governor (if available)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
    echo "   CPU governor: $GOVERNOR"
else
    echo "   CPU governor: Not available (hypervisor managed)"
fi

# Check huge pages
HUGEPAGES=$(cat /proc/sys/vm/nr_hugepages)
echo "   Huge pages configured: $HUGEPAGES"

# Quick container density check
RUNNING_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
echo "   Current running containers: $RUNNING_CONTAINERS"

echo "=== Remote Server Validation Complete ==="
echo "Timestamp: $(date)"
VALIDATION_EOF

chmod +x /usr/local/bin/validate-optimizations.sh

# Run validation
echo "=== Running optimization validation ==="
/usr/local/bin/validate-optimizations.sh

# Reboot to ensure everything is properly loaded
shutdown -r +1 "Rebooting to complete Coolify remote server installation"
