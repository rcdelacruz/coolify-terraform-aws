#!/bin/bash
# fix-remote-ssh.sh - Fix remote server SSH configuration for Coolify

set -e

echo "=== Remote Server SSH Configuration Fix ==="
echo "Timestamp: $(date)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script as root"
    exit 1
fi

print_status "Configuring remote server for Coolify SSH access..."

# 1. Ensure root SSH directory exists
print_status "Setting up root SSH directory..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 2. Configure SSH daemon for root login
print_status "Configuring SSH daemon for root login..."
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original config
cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

# Enable root login with key-based authentication
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
sed -i 's/PermitRootLogin no/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
sed -i 's/PermitRootLogin yes/PermitRootLogin prohibit-password/' "$SSH_CONFIG"

# Ensure key-based authentication is enabled
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSH_CONFIG"
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' "$SSH_CONFIG"

# Ensure password authentication is disabled for security
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG"

print_status "SSH daemon configuration updated"

# 3. Copy ubuntu user's SSH keys to root (if they exist)
print_status "Copying SSH keys from ubuntu user to root..."
if [ -f /home/ubuntu/.ssh/authorized_keys ]; then
    # Copy ubuntu's keys to root
    cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
    print_status "SSH keys copied from ubuntu to root"
    
    # Show the keys that were copied
    echo "Keys copied:"
    cat /root/.ssh/authorized_keys | cut -d' ' -f3 || echo "Keys present but no comments"
else
    print_warning "No SSH keys found in ubuntu user's authorized_keys"
    print_warning "You'll need to manually add the Coolify public key to /root/.ssh/authorized_keys"
fi

# 4. Set up SSH client config for root
print_status "Setting up SSH client configuration..."
cat > /root/.ssh/config << EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF

chmod 600 /root/.ssh/config

# 5. Test SSH configuration
print_status "Testing SSH configuration..."
sshd -t && print_status "SSH configuration is valid" || {
    print_error "SSH configuration has errors"
    exit 1
}

# 6. Restart SSH service
print_status "Restarting SSH service..."
systemctl restart ssh
systemctl status ssh --no-pager -l

# 7. Check firewall
print_status "Checking firewall configuration..."
if command -v ufw >/dev/null 2>&1; then
    ufw status | grep -q "22/tcp.*ALLOW" && print_status "SSH port 22 is allowed in UFW" || {
        print_warning "SSH port 22 might not be allowed in UFW"
        echo "To allow SSH: ufw allow ssh"
    }
fi

# 8. Display current configuration
echo ""
echo "=== Current SSH Configuration ==="
echo "Root SSH login: $(grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "Not explicitly set")"
echo "Public key auth: $(grep "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "Default (yes)")"
echo "Password auth: $(grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "Default (yes)")"

echo ""
echo "=== Root SSH Keys ==="
if [ -f /root/.ssh/authorized_keys ]; then
    echo "Number of keys: $(wc -l < /root/.ssh/authorized_keys)"
    echo "Key fingerprints:"
    ssh-keygen -lf /root/.ssh/authorized_keys 2>/dev/null || echo "Could not read key fingerprints"
else
    print_warning "No authorized_keys file found for root"
fi

echo ""
echo "=== Network Information ==="
echo "Private IP: $(ip route get 1.1.1.1 | awk '{print $7}' | head -1)"
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "Not available")"

echo ""
echo "=== Next Steps ==="
echo "1. Get the Coolify public key from your control server:"
echo "   cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub"
echo ""
echo "2. Add it to this server's root authorized_keys:"
echo "   echo 'COOLIFY_PUBLIC_KEY_HERE' >> /root/.ssh/authorized_keys"
echo ""
echo "3. Test SSH connection from control server:"
echo "   ssh -i /data/coolify/ssh/keys/id.root@host.docker.internal root@$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)"

echo ""
echo "=== Manual Key Addition ==="
echo "If you have the Coolify public key, you can add it now:"
echo "Run: nano /root/.ssh/authorized_keys"
echo "And paste the public key on a new line"

print_status "Remote server SSH configuration completed!"

# 9. Optional: Show how to add a specific key
echo ""
echo "=== Add Coolify Public Key (if you have it) ==="
echo "If you want to add the Coolify public key now, paste it below and press Enter:"
echo "(Or press Ctrl+C to skip)"
read -r COOLIFY_PUBLIC_KEY

if [ -n "$COOLIFY_PUBLIC_KEY" ]; then
    echo "$COOLIFY_PUBLIC_KEY" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    print_status "Coolify public key added successfully!"
    
    # Test the key
    echo "Testing the key..."
    ssh-keygen -lf /root/.ssh/authorized_keys | tail -1
fi
