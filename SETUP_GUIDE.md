# Complete Setup Guide: Coolify on AWS with Cloudflare Tunnel

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] **AWS Account** with billing enabled
- [ ] **Cloudflare Account** with a domain (e.g., `yourdomain.com`)
- [ ] **Local Machine** with admin access
- [ ] **Credit Card** for AWS charges (~$65-75/month)

## Phase 1: Local Environment Setup

### Step 1: Install Required Tools

**On macOS:**
```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Terraform
brew install terraform

# Install AWS CLI
brew install awscli

# Install jq (for JSON parsing)
brew install jq
```

**On Windows:**
```powershell
# Install Chocolatey (if not installed)
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install tools
choco install terraform awscli jq
```

**On Linux (Ubuntu/Debian):**
```bash
# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Install jq
sudo apt install jq
```

### Step 2: Verify Installations
```bash
terraform version    # Should show v1.0+
aws --version        # Should show AWS CLI version
jq --version         # Should show jq version
```

## Phase 2: AWS Configuration

### Step 3: Configure AWS Credentials

1. **Create IAM User:**
   - Go to [AWS IAM Console](https://console.aws.amazon.com/iam/)
   - Click "Users" → "Create user"
   - Username: `terraform-coolify`
   - Select "Programmatic access"
   - Attach policy: `AdministratorAccess` (for simplicity)
   - Save Access Key ID and Secret Access Key

2. **Configure AWS CLI with Coolify Profile:**
```bash
# Create a dedicated profile for Coolify
aws configure --profile coolify
# AWS Access Key ID: [paste your access key]
# AWS Secret Access Key: [paste your secret key]
# Default region name: us-east-1
# Default output format: json
```

3. **Test AWS Access:**
```bash
# Test the coolify profile
aws sts get-caller-identity --profile coolify
# Should show your account details

# Set environment variable for this session
export AWS_PROFILE=coolify

# Verify it's working
aws sts get-caller-identity
# Should show the same account details
```

### Step 4: Create EC2 Key Pair

1. **Via AWS Console:**
   - Go to [EC2 Console](https://console.aws.amazon.com/ec2/)
   - Navigate to "Key Pairs" in the left sidebar
   - Click "Create key pair"
   - Name: `coolify-key`
   - Type: RSA
   - Format: `.pem`
   - Download and save to `~/.ssh/coolify-key.pem`

2. **Set Permissions:**
```bash
chmod 400 ~/.ssh/coolify-key.pem
```

## Phase 3: Project Setup

### Step 5: Clone and Configure Project

```bash
# Clone the repository
git clone https://github.com/rcdelacruz/coolify-terraform-aws.git
cd coolify-terraform-aws/terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars
```

### Step 6: Configure terraform.tfvars

Edit `terraform.tfvars` with your specific values:

```hcl
# AWS Configuration
region            = "us-east-1"
availability_zone = "us-east-1a"

# EC2 Configuration
instance_type = "t4g.large"
key_name     = "coolify-key"  # The key pair you created

# Security Configuration - IMPORTANT: Replace with your IP
allowed_cidrs = [
  "YOUR.PUBLIC.IP.ADDRESS/32"  # Get from https://whatismyipaddress.com
]

# Project Configuration
project_name = "coolify"
environment  = "prod"

# Storage Configuration
data_volume_size = 100  # GB
root_volume_size = 20   # GB

# Monitoring and Backup
enable_monitoring       = true
backup_retention_days   = 7
enable_termination_protection = true
```

**To find your public IP:**
```bash
curl -s https://checkip.amazonaws.com
# Use this IP in allowed_cidrs as "YOUR.IP.ADDRESS/32"
```

## Phase 4: Deployment

### Step 7: Set AWS Profile and Validate Configuration

```bash
# Set the AWS profile for this session
export AWS_PROFILE=coolify

# Verify the profile is active
aws sts get-caller-identity

# Run the validation script
./validate.sh
```

This will check:
- Required tools are installed
- AWS credentials are working
- Key pair exists
- Terraform configuration is valid

### Step 8: Deploy Infrastructure

```bash
# Ensure AWS profile is set
export AWS_PROFILE=coolify

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy (this takes 5-10 minutes)
terraform apply
# Type 'yes' when prompted
```

**Expected Output:**
```
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

coolify_url = "http://54.123.45.67:8000"
public_ip = "54.123.45.67"
ssh_command = "ssh -i ~/.ssh/coolify-key.pem ubuntu@54.123.45.67"
```

### Step 9: Wait for Installation

```bash
# Monitor the installation progress
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw public_ip)
sudo tail -f /var/log/user-data.log

# Wait for this message:
# "=== Coolify Installation Complete ==="
```

## Phase 5: Cloudflare Tunnel Setup

### Step 10: Install Cloudflared (Local Machine)

**On macOS:**
```bash
brew install cloudflared
```

**On Windows:**
```powershell
# Download from https://github.com/cloudflare/cloudflared/releases
# Or use winget:
winget install --id Cloudflare.cloudflared
```

**On Linux:**
```bash
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

### Step 11: Create Cloudflare Tunnel

1. **Login to Cloudflare:**
```bash
cloudflared tunnel login
# This opens browser - login to your Cloudflare account
```

2. **Create Tunnel:**
```bash
cloudflared tunnel create coolify-tunnel
# Note the tunnel ID from output
```

3. **Get Server Private IP:**
```bash
terraform output private_ip
# Example: 10.0.1.123
```

### Step 12: Configure Tunnel

1. **Create tunnel config file:**
```bash
# Create config directory
mkdir -p ~/.cloudflared

# Create config file
cat > ~/.cloudflared/config.yml << EOF
tunnel: coolify-tunnel
credentials-file: ~/.cloudflared/[TUNNEL-ID].json

ingress:
  # Coolify Dashboard
  - hostname: coolify.yourdomain.com
    service: http://[PRIVATE-IP]:8000

  # Realtime Server
  - hostname: realtime.yourdomain.com
    service: http://[PRIVATE-IP]:6001

  # Terminal WebSocket
  - hostname: terminal.yourdomain.com
    service: http://[PRIVATE-IP]:6002
    path: /ws

  # Wildcard for deployed apps
  - hostname: "*.yourdomain.com"
    service: http://[PRIVATE-IP]:80

  # Catch-all
  - service: http_status:404
EOF
```

**Replace:**
- `[TUNNEL-ID]` with your actual tunnel ID
- `[PRIVATE-IP]` with the private IP from terraform output
- `yourdomain.com` with your actual domain

### Step 13: Configure DNS Records

1. **Go to Cloudflare Dashboard** → Your Domain → DNS
2. **Add CNAME records:**
   - `coolify` → `[TUNNEL-ID].cfargotunnel.com`
   - `realtime` → `[TUNNEL-ID].cfargotunnel.com`
   - `terminal` → `[TUNNEL-ID].cfargotunnel.com`
   - `*` → `[TUNNEL-ID].cfargotunnel.com` (wildcard)

### Step 14: Start Tunnel

```bash
# Test the tunnel
cloudflared tunnel run coolify-tunnel

# If working, install as service (optional)
sudo cloudflared service install
```

## Phase 6: Coolify Configuration

### Step 15: Access Coolify

1. **Open browser:** `https://coolify.yourdomain.com`
2. **Complete setup wizard:**
   - Create admin account
   - Set up your first project

### Step 16: Configure Coolify for Tunnel

SSH into your server and update Coolify configuration:

```bash
# SSH to server
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw public_ip)

# Edit Coolify environment
sudo nano /data/coolify/source/.env

# Add these lines:
PUSHER_HOST=realtime.yourdomain.com
PUSHER_PORT=443

# Restart Coolify
cd /data/coolify/source
sudo docker compose restart
```

## Phase 7: Verification

### Step 17: Test Everything

1. **Dashboard:** `https://coolify.yourdomain.com` ✅
2. **Realtime:** Should work automatically ✅
3. **Terminal:** Test in Coolify dashboard ✅
4. **Deploy test app:** Should be accessible at `appname.yourdomain.com` ✅

## Troubleshooting

### Common Issues:

1. **Tunnel not connecting:**
```bash
# Check tunnel status
cloudflared tunnel info coolify-tunnel

# Check logs
cloudflared tunnel run coolify-tunnel --loglevel debug
```

2. **Coolify not accessible:**
```bash
# Check if Coolify is running
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw public_ip)
sudo docker ps | grep coolify
```

3. **DNS not resolving:**
   - Wait 5-10 minutes for DNS propagation
   - Check DNS with: `nslookup coolify.yourdomain.com`

## Cost Management

**Monthly costs (~$65-75):**
- EC2 t4g.large: ~$53/month
- 100GB GP3 storage: ~$8/month
- 20GB root volume: ~$2/month
- Elastic IP: ~$4/month
- S3 backup storage: ~$2-5/month
- CloudWatch logs: ~$1-2/month

## Next Steps

1. **Deploy your first application** in Coolify
2. **Set up monitoring** with CloudWatch alarms
3. **Configure backups** (already automated)
4. **Review security settings** regularly
5. **Scale resources** as needed

## Support

- **Coolify Docs:** https://coolify.io/docs
- **Cloudflare Tunnel Docs:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **AWS Support:** https://aws.amazon.com/support/

Your Coolify installation is now ready for production use! 🚀
