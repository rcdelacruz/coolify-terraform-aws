#!/bin/bash
# terraform/remote_user_data_minimal.sh - Minimal Coolify Remote Server Setup

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
apt-get install -y curl wget git unzip htop jq awscli fail2ban ufw

# Configure timezone
timedatectl set-timezone UTC

# Setup firewall for remote server
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000:9000/tcp
ufw allow from 10.0.0.0/16 to any port 2376
ufw --force enable

# Configure fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# Create 4GB swap file
echo "Creating 4GB swap file..."
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Wait for EBS volume
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

# Download and run full optimization script
echo "=== Downloading full optimization script ==="
curl -fsSL -o /tmp/coolify-remote-optimize.sh https://raw.githubusercontent.com/rcdelacruz/coolify-terraform-aws/main/scripts/coolify-remote-optimize.sh || {
    echo "Failed to download optimization script, creating basic version..."
    cat > /tmp/coolify-remote-optimize.sh << 'OPTIMIZE_EOF'
#!/bin/bash
# Basic optimization script for remote server

# High density system limits
echo "* soft nofile 1048576" >> /etc/security/limits.conf
echo "* hard nofile 1048576" >> /etc/security/limits.conf
echo "* soft nproc 1048576" >> /etc/security/limits.conf
echo "* hard nproc 1048576" >> /etc/security/limits.conf
echo "root soft nofile 1048576" >> /etc/security/limits.conf
echo "root hard nofile 1048576" >> /etc/security/limits.conf

# Kernel optimizations
cat >> /etc/sysctl.conf << 'EOF'
# High container density optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.swappiness = 10
vm.max_map_count = 2147483647
fs.file-max = 2097152
kernel.pid_max = 4194304
net.netfilter.nf_conntrack_max = 1048576
EOF

sysctl -p

# Docker optimizations for high density
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
  "default-ulimits": {
    "nofile": {"Name": "nofile", "Hard": 1048576, "Soft": 1048576},
    "nproc": {"Name": "nproc", "Hard": 1048576, "Soft": 1048576}
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF

# Enable root SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Copy SSH keys to root
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
fi

systemctl restart ssh

echo "Basic optimizations applied"
OPTIMIZE_EOF
}

chmod +x /tmp/coolify-remote-optimize.sh
/tmp/coolify-remote-optimize.sh

# Configure Docker for remote access
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/tcp.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2376
EOF

systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
sleep 10

# Create container monitoring script
cat > /usr/local/bin/container-monitor.sh << 'EOF'
#!/bin/bash
RUNNING=$(docker ps -q | wc -l)
echo "$(date): $RUNNING containers running" >> /var/log/container-monitor.log
if [ "$RUNNING" -gt 100 ]; then
    echo "High container density: $RUNNING containers"
fi
EOF

chmod +x /usr/local/bin/container-monitor.sh

# Setup monitoring cron
echo "*/15 * * * * root /usr/local/bin/container-monitor.sh" > /etc/cron.d/container-monitor

echo "=== Coolify Remote Server Installation Complete ==="
echo "Server ready for Coolify deployment management"
echo "Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
echo "Docker daemon listening on: 0.0.0.0:2376"
