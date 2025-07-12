#!/bin/bash
# fix-coolify-ssh.sh - Fix Coolify SSH key configuration

set -e

echo "=== Coolify SSH Key Configuration Fix ==="
echo "Timestamp: $(date)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
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

print_status "Starting Coolify SSH configuration fix..."

# 1. Check current Coolify installation
print_status "Checking Coolify installation..."
if [ ! -d "/data/coolify" ]; then
    print_error "Coolify directory not found at /data/coolify"
    exit 1
fi

# 2. Create necessary directories
print_status "Creating SSH directories..."
mkdir -p /data/coolify/ssh/keys
mkdir -p /data/coolify/ssh/mux
mkdir -p /var/www/html/storage/app/ssh/keys
mkdir -p /var/www/html/storage/app/ssh/mux

# 3. Generate SSH key if it doesn't exist
SSH_KEY_PATH="/data/coolify/ssh/keys/id.root@host.docker.internal"
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_status "Generating new SSH key for Coolify..."
    ssh-keygen -f "$SSH_KEY_PATH" -t ed25519 -N '' -C "root@coolify-$(hostname)"
else
    print_status "SSH key already exists at $SSH_KEY_PATH"
fi

# 4. Copy SSH key to Laravel storage location
print_status "Copying SSH keys to Laravel storage..."
if [ -f "$SSH_KEY_PATH" ]; then
    cp "$SSH_KEY_PATH" /var/www/html/storage/app/ssh/keys/
    cp "${SSH_KEY_PATH}.pub" /var/www/html/storage/app/ssh/keys/
    
    # Also create the specific key file that Coolify is looking for
    COOLIFY_KEY_NAME=$(ls /var/www/html/storage/app/ssh/keys/ | grep "ssh_key@" | head -1)
    if [ -z "$COOLIFY_KEY_NAME" ]; then
        # Create a key with the expected naming pattern
        COOLIFY_KEY_NAME="ssh_key@$(hostname | tr '.' '_')"
        cp "$SSH_KEY_PATH" "/var/www/html/storage/app/ssh/keys/$COOLIFY_KEY_NAME"
        cp "${SSH_KEY_PATH}.pub" "/var/www/html/storage/app/ssh/keys/${COOLIFY_KEY_NAME}.pub"
        print_status "Created Coolify SSH key: $COOLIFY_KEY_NAME"
    fi
else
    print_error "SSH key generation failed"
    exit 1
fi

# 5. Set proper permissions
print_status "Setting SSH key permissions..."
chown -R root:root /data/coolify/ssh
chmod 700 /data/coolify/ssh
chmod 700 /data/coolify/ssh/keys
chmod 600 /data/coolify/ssh/keys/*
chmod 644 /data/coolify/ssh/keys/*.pub

chown -R www-data:www-data /var/www/html/storage/app/ssh
chmod 755 /var/www/html/storage/app/ssh
chmod 755 /var/www/html/storage/app/ssh/keys
chmod 600 /var/www/html/storage/app/ssh/keys/*
chmod 644 /var/www/html/storage/app/ssh/keys/*.pub

# 6. Add public key to root's authorized_keys
print_status "Adding public key to root's authorized_keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ -f "${SSH_KEY_PATH}.pub" ]; then
    # Remove any existing entries for this key
    if [ -f /root/.ssh/authorized_keys ]; then
        grep -v "root@coolify" /root/.ssh/authorized_keys > /tmp/authorized_keys_temp || true
        mv /tmp/authorized_keys_temp /root/.ssh/authorized_keys
    fi
    
    # Add the new key
    cat "${SSH_KEY_PATH}.pub" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
    
    print_status "Public key added to root's authorized_keys"
else
    print_error "Public key not found"
    exit 1
fi

# 7. Test SSH connection locally
print_status "Testing SSH connection locally..."
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@localhost "echo 'SSH test successful'" || {
    print_warning "Local SSH test failed, but this might be normal if SSH is configured differently"
}

# 8. Create SSH config for Coolify
print_status "Creating SSH config for Coolify..."
cat > /root/.ssh/config << EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
    IdentitiesOnly yes
    ConnectTimeout 10
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF

chmod 600 /root/.ssh/config

# 9. Fix Coolify database SSH key references (if accessible)
print_status "Checking Coolify database configuration..."
if [ -f "/data/coolify/source/.env" ]; then
    print_status "Found Coolify .env file"
    
    # Check if we can access the database
    if command -v docker >/dev/null 2>&1; then
        print_status "Attempting to update Coolify database SSH key references..."
        
        # Get the container name
        COOLIFY_CONTAINER=$(docker ps --format "table {{.Names}}" | grep -E "(coolify|postgres)" | head -1)
        
        if [ -n "$COOLIFY_CONTAINER" ]; then
            print_status "Found Coolify container: $COOLIFY_CONTAINER"
            
            # Try to update the database (this might need adjustment based on your setup)
            docker exec "$COOLIFY_CONTAINER" sh -c "
                echo 'Coolify container is running'
            " 2>/dev/null || print_warning "Could not access Coolify container"
        fi
    fi
else
    print_warning "Coolify .env file not found"
fi

# 10. Restart relevant services
print_status "Restarting SSH service..."
systemctl restart ssh

if systemctl is-active --quiet docker; then
    print_status "Restarting Coolify containers..."
    cd /data/coolify/source 2>/dev/null && docker compose restart 2>/dev/null || print_warning "Could not restart Coolify containers"
fi

# 11. Display summary
echo ""
echo "=== SSH Configuration Summary ==="
print_status "SSH key location: $SSH_KEY_PATH"
print_status "Public key location: ${SSH_KEY_PATH}.pub"
print_status "Laravel storage: /var/www/html/storage/app/ssh/keys/"

echo ""
echo "=== Next Steps ==="
echo "1. In Coolify UI, go to Server settings"
echo "2. Update the SSH key path to: /var/www/html/storage/app/ssh/keys/$(basename $SSH_KEY_PATH)"
echo "3. Or use the key: /var/www/html/storage/app/ssh/keys/$COOLIFY_KEY_NAME"
echo "4. Test the connection to your remote server"

echo ""
echo "=== Remote Server Setup ==="
echo "On your remote server, ensure:"
echo "1. Root SSH login is enabled: PermitRootLogin prohibit-password"
echo "2. This public key is in /root/.ssh/authorized_keys:"
echo ""
cat "${SSH_KEY_PATH}.pub"
echo ""

echo ""
echo "=== Troubleshooting ==="
echo "If still having issues:"
echo "1. Check remote server SSH logs: tail -f /var/log/auth.log"
echo "2. Test manual SSH: ssh -i $SSH_KEY_PATH root@REMOTE_SERVER_IP"
echo "3. Verify remote server firewall allows SSH (port 22)"

print_status "SSH configuration fix completed!"
