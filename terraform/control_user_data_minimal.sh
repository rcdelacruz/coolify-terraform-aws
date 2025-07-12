#!/bin/bash
# terraform/control_user_data_minimal.sh - Minimal Coolify Control Server Setup

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
apt-get install -y curl wget git unzip htop jq awscli fail2ban ufw certbot

# Configure timezone
timedatectl set-timezone UTC

# Setup basic firewall
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

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh
apt-get install -y docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Create 4GB swap file
echo "Creating 4GB swap file..."
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Create directories
mkdir -p /data/coolify
mkdir -p /data/backups
chown -R ubuntu:ubuntu /data

# Download and run full optimization script
echo "=== Downloading full optimization script ==="
curl -fsSL -o /tmp/coolify-control-optimize.sh https://raw.githubusercontent.com/rcdelacruz/coolify-terraform-aws/main/scripts/coolify-control-optimize.sh || {
    echo "Failed to download optimization script, creating basic version..."
    cat > /tmp/coolify-control-optimize.sh << 'OPTIMIZE_EOF'
#!/bin/bash
# Basic optimization script

# System optimizations
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf
echo "root soft nofile 65535" >> /etc/security/limits.conf
echo "root hard nofile 65535" >> /etc/security/limits.conf

# Docker optimizations
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
    "nofile": {"Name": "nofile", "Hard": 65535, "Soft": 65535}
  }
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
systemctl restart docker

echo "Basic optimizations applied"
OPTIMIZE_EOF
}

chmod +x /tmp/coolify-control-optimize.sh
/tmp/coolify-control-optimize.sh

# Install Coolify
echo "Installing Coolify..."
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# Wait for installation
sleep 30

# Ensure Coolify is running
cd /data/coolify/source 2>/dev/null || {
    echo "Coolify source directory not found, trying alternative setup..."
    mkdir -p /data/coolify/source
}

# Generate SSH keys for Coolify
mkdir -p /data/coolify/ssh/keys
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify || true

# Add SSH key to authorized_keys
if [ -f /data/coolify/ssh/keys/id.root@host.docker.internal.pub ]; then
    mkdir -p /root/.ssh
    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Set permissions
chown -R root:root /data/coolify
chmod -R 755 /data/coolify

# Create systemd service
cat > /etc/systemd/system/coolify.service << 'EOF'
[Unit]
Description=Coolify
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
Group=root
WorkingDirectory=/data/coolify/source
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable coolify.service

echo "=== Coolify Control Server Installation Complete ==="
echo "Access Coolify at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8000"
echo "Check logs with: tail -f /var/log/user-data.log"
