# Complete Setup Guide: Multi-Server Coolify on AWS with Cloudflare Tunnel

## 🏗️ Architecture Overview

This guide deploys a **multi-server Coolify architecture** that separates control and application workloads:

- **Control Server** (t4g.micro): Runs Coolify dashboard and orchestrates deployments
- **Remote Servers** (t4g.large × N): Execute application workloads with dedicated resources
- **Shared Infrastructure**: VPC, S3 backups, CloudWatch monitoring, security groups

### Benefits of Multi-Server Architecture:
- **Scalability**: Add/remove remote servers based on demand
- **Resource Isolation**: Control server dedicated to management, remote servers for apps
- **Cost Efficiency**: Right-size each server type for its specific role
- **High Availability**: Applications distributed across multiple servers

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] **AWS Account** with billing enabled
- [ ] **Cloudflare Account** with a domain (e.g., `yourdomain.com`) - Optional
- [ ] **Local Machine** with admin access
- [ ] **Credit Card** for AWS charges (~$95-167/month depending on configuration)

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

# Multi-Server Configuration
control_instance_type = "t4g.micro"    # Control server (manages deployments)
remote_instance_type  = "t4g.large"    # Remote servers (run applications)
remote_server_count   = 2              # Number of remote servers (1-10)
key_name             = "coolify-key"   # The key pair you created

# Security Configuration - IMPORTANT: Replace with your IP
allowed_cidrs = [
  "YOUR.PUBLIC.IP.ADDRESS/32"  # Get from https://whatismyipaddress.com
]

# Storage Configuration
control_root_volume_size = 20   # Control server root volume (GB)
remote_root_volume_size  = 20   # Remote server root volume (GB)
remote_data_volume_size  = 100  # Remote server data volume (GB) - for Docker/apps

# Project Configuration
project_name = "coolify"
environment  = "prod"           # Options: dev, staging, prod

# Monitoring and Backup
enable_monitoring       = true
backup_retention_days   = 7
log_retention_days      = 7     # CloudWatch log retention

# Domain Configuration (Optional - for Cloudflare Tunnel)
domain_name              = ""    # Set to your domain if using Cloudflare Tunnel
enable_cloudflare_tunnel = true # Configure security groups for Cloudflare Tunnel

# Security
enable_termination_protection = true # Prevent accidental instance termination
```

### Configuration Examples:

**Development Environment (~$35/month):**
```hcl
control_instance_type = "t4g.micro"
remote_instance_type  = "t4g.small"
remote_server_count   = 1
remote_data_volume_size = 50
environment = "dev"
```

**Production Environment (~$300/month):**
```hcl
control_instance_type = "t4g.small"
remote_instance_type  = "t4g.xlarge"
remote_server_count   = 3
remote_data_volume_size = 200
environment = "prod"
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
Apply complete! Resources: 22 added, 0 changed, 0 destroyed.

Outputs:

🚀 Coolify Multi-Server Architecture Deployed Successfully!

📊 Architecture Overview:
├── Control Server (t4g.micro): 54.123.45.67
└── Remote Servers (t4g.large × 2):
    ├── Remote 1: 54.123.45.68
    └── Remote 2: 54.123.45.69

💰 Estimated Monthly Cost: $167.00

🔗 Quick Access:
• Coolify Dashboard: http://54.123.45.67:8000
• Control Server SSH: ssh -i ~/.ssh/coolify-key.pem ubuntu@54.123.45.67
```

### Step 9: Wait for Installation and Add Remote Servers

```bash
# Monitor the control server installation progress
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw control_server_public_ip)
sudo tail -f /var/log/user-data.log

# Wait for this message:
# "=== Coolify Control Server Installation Complete ==="

# You can also check if Coolify is running:
cd /data/coolify/source
sudo docker compose ps

# Check if Coolify is accessible:
curl http://localhost:8000
```

**Important:** The control server installs Coolify, while remote servers prepare Docker and wait to be added to Coolify.

### Step 10: Access Coolify and Add Remote Servers

1. **Access Coolify Dashboard:**
```bash
# Get the dashboard URL
terraform output coolify_dashboard_url
# Open in browser: http://[control-server-ip]:8000
```

2. **Complete Coolify Setup:**
   - Create admin account
   - Complete initial setup wizard

3. **Add Remote Servers to Coolify:**
   - Go to: **Settings** → **Servers** → **Add Server**
   - For each remote server, use these details:

```bash
# Get remote server details
terraform output remote_servers_details
```

**For each remote server:**
- **Name**: `remote-server-1`, `remote-server-2`, etc.
- **Host**: Use the **private IP** from terraform output
- **Port**: `22`
- **User**: `ubuntu`
- **Private Key**: Same key pair as control server (`~/.ssh/coolify-key.pem`)

4. **Verify Remote Server Connection:**
   - Coolify will test the connection
   - Each remote server should show as "Connected" in the dashboard

## Phase 5: Cloudflare Tunnel Setup

### Step 10: Create Cloudflare Tunnel via Dashboard

**Important:** The current Coolify documentation recommends creating tunnels through the Cloudflare Dashboard rather than using the CLI.

1. **Go to Cloudflare Dashboard:**
   - Navigate to **Zero Trust** → **Networks** → **Tunnels**
   - Click **Create a tunnel**
   - Choose **Cloudflared** as the connector type
   - Name your tunnel: `coolify-tunnel`
   - Click **Save tunnel**

2. **Install Cloudflared on Control Server:**
```bash
# SSH to control server
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw control_server_public_ip)

# Install cloudflared
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# Copy the token from Cloudflare Dashboard and run:
sudo cloudflared service install [YOUR_TUNNEL_TOKEN]
```

3. **Get Server IPs for Configuration:**
```bash
# Get control server private IP (for Coolify dashboard)
terraform output control_server_private_ip
# Example: 10.0.1.10

# Get control server public IP (for tunnel setup)
terraform output control_server_public_ip
# Example: 54.123.45.67
```

### Step 11: Configure Tunnel Hostnames

In the Cloudflare Dashboard, configure these **Public Hostnames** for your tunnel:

**Required Hostnames (based on Coolify documentation):**

1. **Coolify Dashboard:**
   - **Subdomain:** `app`
   - **Domain:** `yourdomain.com`
   - **Path:** (leave empty)
   - **Service Type:** HTTP
   - **URL:** `localhost:8000`

2. **Realtime Server:**
   - **Subdomain:** `realtime`
   - **Domain:** `yourdomain.com`
   - **Path:** (leave empty)
   - **Service Type:** HTTP
   - **URL:** `localhost:6001`

3. **Terminal WebSocket:**
   - **Subdomain:** `app`
   - **Domain:** `yourdomain.com`
   - **Path:** `/terminal/ws`
   - **Service Type:** HTTP
   - **URL:** `localhost:6002`

**Example Configuration:**
```
Hostnames:
1. app.yourdomain.com/terminal/ws → localhost:6002 (WebSocket terminal)
2. realtime.yourdomain.com → localhost:6001 (Realtime server)
3. app.yourdomain.com → localhost:8000 (Coolify dashboard)
Type: HTTP
```

### Step 12: Configure DNS Records

The DNS records are automatically created when you add public hostnames in the Cloudflare Dashboard. Verify these records exist:

1. **Go to Cloudflare Dashboard** → Your Domain → **DNS**
2. **Verify CNAME records exist:**
   - `app` → `[TUNNEL-ID].cfargotunnel.com`
   - `realtime` → `[TUNNEL-ID].cfargotunnel.com`

**Note:** DNS records are automatically managed by Cloudflare when using the dashboard method.

## Phase 6: Coolify Configuration

### Step 13: Configure Coolify for Tunnel

SSH into your control server and update Coolify configuration:

```bash
# SSH to control server
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw control_server_public_ip)

# Navigate to Coolify source directory
cd /data/coolify/source

# Edit Coolify environment file
sudo nano .env

# Add these lines to the .env file:
PUSHER_HOST=realtime.yourdomain.com
PUSHER_PORT=443

# Save and exit (Ctrl+X, then Y, then Enter)

# Restart Coolify to apply changes
sudo docker compose restart
```

**Important:** Replace `yourdomain.com` with your actual domain name.

### Step 14: Access Coolify

1. **Open browser:** `https://app.yourdomain.com`
2. **Complete setup wizard:**
   - Create admin account
   - Complete initial setup wizard

### Step 15: Add Remote Servers to Coolify

1. **Get remote server details:**
```bash
# Get remote server details
terraform output remote_servers_details
```

2. **Add Remote Servers:**
   - Go to: **Settings** → **Servers** → **Add Server**
   - For each remote server, use these details:

**For each remote server:**
- **Name**: `remote-server-1`, `remote-server-2`, etc.
- **Host**: Use the **private IP** from terraform output
- **Port**: `22`
- **User**: `ubuntu`
- **Private Key**: Same key pair as control server (`~/.ssh/coolify-key.pem`)

3. **Verify Remote Server Connection:**
   - Coolify will test the connection
   - Each remote server should show as "Connected" in the dashboard

## Phase 7: Verification

### Step 16: Test Everything

1. **Dashboard:** `https://app.yourdomain.com` ✅
2. **Realtime:** Should work automatically ✅
3. **Terminal:** Test in Coolify dashboard ✅
4. **Deploy test app:** Should be accessible at `appname.yourdomain.com` ✅

## Troubleshooting

### Common Issues:

1. **Tunnel not connecting:**
```bash
# Check tunnel status on control server
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw control_server_public_ip)
sudo systemctl status cloudflared

# Check tunnel logs
sudo journalctl -u cloudflared -f

# Restart tunnel service if needed
sudo systemctl restart cloudflared
```

2. **Coolify not accessible:**
```bash
# Check if Coolify is running on control server
ssh -i ~/.ssh/coolify-key.pem ubuntu@$(terraform output -raw control_server_public_ip)

# Check Coolify Docker containers
cd /data/coolify/source
sudo docker compose ps

# Check Coolify logs
sudo docker compose logs

# Restart Coolify if needed
sudo docker compose restart

# Check if port 8000 is accessible
curl http://localhost:8000

# Check remote server connectivity
terraform output remote_ssh_commands
# SSH to each remote server and verify Docker is running
```

3. **DNS not resolving:**
   - Wait 5-10 minutes for DNS propagation
   - Check DNS with: `nslookup coolify.yourdomain.com`

## Cost Management

### Default Configuration (1 Control + 2 Remote Servers)
**Monthly costs (~$167/month):**
- Control Server (t4g.micro): ~$8/month
- Remote Servers (2× t4g.large): ~$134/month
- Storage (EBS volumes): ~$15/month
- Networking & Backup: ~$10/month

### Alternative Configurations

**Development (~$35/month):**
- Control: t4g.micro, Remote: 1× t4g.small
- Ideal for testing and small applications

**Production (~$300/month):**
- Control: t4g.small, Remote: 3× t4g.xlarge
- High-performance setup for demanding workloads

**Cost Optimization Tips:**
- Use `terraform output estimated_monthly_costs` to see detailed breakdown
- Reduce `remote_server_count` for smaller workloads
- Use smaller `remote_data_volume_size` if you don't need 100GB per server
- Consider t4g.medium remote servers for lighter workloads

## Next Steps

1. **Deploy your first application** in Coolify:
   - Choose a remote server for deployment
   - Deploy from Git repository or Docker image
   - Applications will be accessible at `appname.yourdomain.com`

2. **Scale your infrastructure**:
   - Add more remote servers: Update `remote_server_count` and run `terraform apply`
   - Upgrade instance types for better performance
   - Monitor resource usage in CloudWatch

3. **Set up monitoring** with CloudWatch alarms
4. **Configure backups** (already automated to S3)
5. **Review security settings** regularly
6. **Load balance applications** across multiple remote servers

### Multi-Server Management Commands:

```bash
# View all servers
terraform output remote_servers_details

# Check costs
terraform output estimated_monthly_costs

# SSH to specific servers
terraform output control_ssh_command
terraform output remote_ssh_commands

# Get architecture summary
terraform output architecture_summary
```

## Support

- **Coolify Docs:** https://coolify.io/docs
- **Cloudflare Tunnel Docs:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- **AWS Support:** https://aws.amazon.com/support/

Your **Multi-Server Coolify** installation is now ready for production use! 🚀

## 🎯 What You've Accomplished

✅ **Deployed a scalable multi-server Coolify architecture**
✅ **Separated control and application workloads for better resource management**
✅ **Set up automated backups and monitoring**
✅ **Configured security groups and encrypted storage**
✅ **Prepared for Cloudflare Tunnel integration**
✅ **Created a foundation that can scale from 1 to 10 remote servers**

Your infrastructure is now ready to handle production workloads with the flexibility to scale as your needs grow!
