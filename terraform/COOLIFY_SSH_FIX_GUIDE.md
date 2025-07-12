# Coolify SSH Connection Fix Guide

This guide will help you fix the SSH connection issue between your Coolify control server and remote servers.

## Error Analysis

The error you're seeing:
```
Error: Warning: Identity file /var/www/html/storage/app/ssh/keys/ssh_key@pcc0wcccccc4ssc00gcccc4o not accessible: No such file or directory.
root@10.0.1.210: Permission denied (publickey).
```

Indicates two problems:
1. **Missing SSH key file** in Coolify's storage directory
2. **Permission denied** when connecting to the remote server as root

## Quick Fix Steps

### Step 1: Fix Control Server SSH Keys

SSH into your **Coolify control server** and run:

```bash
# Download and run the SSH fix script
curl -fsSL -o fix-coolify-ssh.sh https://raw.githubusercontent.com/rcdelacruz/coolify-terraform-aws/main/terraform/fix-coolify-ssh.sh
chmod +x fix-coolify-ssh.sh
sudo ./fix-coolify-ssh.sh
```

Or manually run the commands:

```bash
# 1. Create SSH directories
sudo mkdir -p /data/coolify/ssh/keys
sudo mkdir -p /var/www/html/storage/app/ssh/keys

# 2. Generate SSH key if missing
sudo ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C "root@coolify"

# 3. Copy to Laravel storage
sudo cp /data/coolify/ssh/keys/id.root@host.docker.internal* /var/www/html/storage/app/ssh/keys/

# 4. Set permissions
sudo chown -R www-data:www-data /var/www/html/storage/app/ssh
sudo chmod 600 /var/www/html/storage/app/ssh/keys/*
sudo chmod 644 /var/www/html/storage/app/ssh/keys/*.pub

# 5. Add to root's authorized_keys
sudo mkdir -p /root/.ssh
sudo cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
```

### Step 2: Fix Remote Server SSH Configuration

SSH into your **remote server** (10.0.1.210) and run:

```bash
# Download and run the remote SSH fix script
curl -fsSL -o fix-remote-ssh.sh https://raw.githubusercontent.com/rcdelacruz/coolify-terraform-aws/main/terraform/fix-remote-ssh.sh
chmod +x fix-remote-ssh.sh
sudo ./fix-remote-ssh.sh
```

Or manually run the commands:

```bash
# 1. Enable root SSH login
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# 2. Copy ubuntu SSH keys to root
sudo mkdir -p /root/.ssh
sudo cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
sudo chown root:root /root/.ssh/authorized_keys

# 3. Restart SSH service
sudo systemctl restart ssh
```

### Step 3: Copy Public Key Between Servers

From your **control server**, get the public key:

```bash
sudo cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub
```

Copy this key and add it to your **remote server**:

```bash
# On remote server
echo "PASTE_PUBLIC_KEY_HERE" | sudo tee -a /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
```

### Step 4: Test SSH Connection

From your **control server**, test the connection:

```bash
sudo ssh -i /data/coolify/ssh/keys/id.root@host.docker.internal root@10.0.1.210 "echo 'SSH test successful'"
```

### Step 5: Update Coolify Configuration

1. **In Coolify UI**, go to **Servers** → **Your Remote Server**
2. **Edit** the server configuration
3. **Update SSH Key Path** to: `/var/www/html/storage/app/ssh/keys/id.root@host.docker.internal`
4. **Test Connection** in Coolify UI

## Alternative: Manual SSH Key Setup

If the scripts don't work, here's the manual approach:

### On Control Server:

```bash
# 1. Generate new SSH key
sudo ssh-keygen -t ed25519 -f /data/coolify/ssh/keys/coolify_key -N '' -C "coolify@$(hostname)"

# 2. Copy to Laravel storage with expected name
sudo cp /data/coolify/ssh/keys/coolify_key /var/www/html/storage/app/ssh/keys/ssh_key@$(hostname)
sudo cp /data/coolify/ssh/keys/coolify_key.pub /var/www/html/storage/app/ssh/keys/ssh_key@$(hostname).pub

# 3. Set permissions
sudo chown www-data:www-data /var/www/html/storage/app/ssh/keys/*
sudo chmod 600 /var/www/html/storage/app/ssh/keys/ssh_key@*
sudo chmod 644 /var/www/html/storage/app/ssh/keys/*.pub

# 4. Get the public key
sudo cat /var/www/html/storage/app/ssh/keys/ssh_key@$(hostname).pub
```

### On Remote Server:

```bash
# 1. Add the public key to root's authorized_keys
echo "PASTE_PUBLIC_KEY_FROM_ABOVE" | sudo tee -a /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys

# 2. Ensure SSH config allows root login
sudo grep "PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin prohibit-password" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh
```

## Troubleshooting

### Check SSH Logs on Remote Server:
```bash
sudo tail -f /var/log/auth.log
```

### Verify SSH Key Permissions:
```bash
# On control server
ls -la /var/www/html/storage/app/ssh/keys/
ls -la /data/coolify/ssh/keys/

# On remote server
ls -la /root/.ssh/
```

### Test SSH Connection Manually:
```bash
# From control server
sudo ssh -i /var/www/html/storage/app/ssh/keys/ssh_key@HOSTNAME -o StrictHostKeyChecking=no root@REMOTE_IP
```

### Check Coolify Logs:
```bash
# On control server
sudo docker logs $(docker ps | grep coolify | awk '{print $1}')
```

## Common Issues

1. **Wrong file permissions**: SSH keys must be 600, directories 700
2. **Wrong ownership**: Laravel storage should be owned by www-data
3. **SSH daemon config**: Root login must be enabled on remote server
4. **Firewall**: Ensure port 22 is open on remote server
5. **Key mismatch**: Public key on remote server must match private key on control server

## Verification

After fixing, you should see:
- ✅ SSH key files exist in `/var/www/html/storage/app/ssh/keys/`
- ✅ Manual SSH connection works from control server to remote server
- ✅ Coolify UI shows "Connected" status for remote server
- ✅ No permission denied errors in Coolify logs

If you're still having issues after following this guide, please share:
1. Output of the fix scripts
2. SSH connection test results
3. Coolify server validation logs
