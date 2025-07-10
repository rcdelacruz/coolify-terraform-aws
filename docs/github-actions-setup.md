# GitHub Actions Setup Guide

This guide explains how to configure GitHub Actions for automated Terraform deployments of your multi-server Coolify architecture.

## 🚨 **Current Status**

The GitHub Actions workflow is **temporarily disabled** to prevent failures before secrets are configured. The automatic triggers (`push` and `pull_request`) are commented out until you complete the setup below.

## 🔧 **Required Setup Steps**

### 1. Configure Repository Secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these **required secrets**:

```
AWS_ACCESS_KEY_ID       # Your AWS access key
AWS_SECRET_ACCESS_KEY   # Your AWS secret key  
EC2_KEY_NAME           # Name of your EC2 key pair (must exist in AWS)
```

Add these **optional secrets** (defaults will be used if not set):

```
AWS_REGION             # AWS region (default: us-east-1)
AWS_AVAILABILITY_ZONE  # AZ for EBS volumes (default: us-east-1a)
ALLOWED_CIDR          # Your IP for access (default: 0.0.0.0/0 - INSECURE!)
CONTROL_INSTANCE_TYPE # Control server type (default: t4g.micro)
REMOTE_INSTANCE_TYPE  # Remote server type (default: t4g.large)
REMOTE_SERVER_COUNT   # Number of remote servers (default: 1)
DOMAIN_NAME           # Optional domain for Cloudflare Tunnel
```

### 2. Get AWS Credentials

#### Option A: Create IAM User (Recommended for CI/CD)
```bash
# Create IAM user with programmatic access
aws iam create-user --user-name terraform-coolify-ci

# Attach necessary policies
aws iam attach-user-policy --user-name terraform-coolify-ci --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-user-policy --user-name terraform-coolify-ci --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-user-policy --user-name terraform-coolify-ci --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
aws iam attach-user-policy --user-name terraform-coolify-ci --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

# Create access keys
aws iam create-access-key --user-name terraform-coolify-ci
```

#### Option B: Use Existing Credentials
- Use your existing AWS access keys
- Ensure they have permissions for EC2, S3, CloudWatch, and IAM

### 3. Create EC2 Key Pair

```bash
# Create new key pair in your target region
aws ec2 create-key-pair --key-name coolify-terraform --region us-east-1 --query 'KeyMaterial' --output text > ~/.ssh/coolify-terraform.pem
chmod 600 ~/.ssh/coolify-terraform.pem

# Or use existing key pair name
aws ec2 describe-key-pairs --region us-east-1
```

### 4. Get Your Public IP

```bash
# Get your current public IP
curl -4 ifconfig.co

# Add /32 for single IP: 203.0.113.1/32
# Or use CIDR range for office: 203.0.113.0/24
```

### 5. Enable the Workflow

After configuring secrets, uncomment the triggers in `.github/workflows/multi-server-terraform.yml`:

```yaml
on:
  push:                                    # Uncomment this section
    branches: [ "multi-server-architecture" ]
    paths: ['terraform/**']
  pull_request:                           # Uncomment this section  
    branches: [ "multi-server-architecture" ]
    paths: ['terraform/**']
  workflow_dispatch:
    # ... rest stays the same
```

## 🧪 **Testing the Setup**

### 1. Manual Test (Recommended First)

Test the workflow manually before enabling automatic triggers:

1. Go to **Actions** tab in your GitHub repository
2. Select **Multi-Server Coolify CI/CD** workflow
3. Click **Run workflow**
4. Select **plan** action and **dev** environment
5. Click **Run workflow**

If successful, you'll see:
- ✅ Check Required Secrets (passes)
- ✅ Terraform Validate (passes)  
- ✅ Terraform Plan (shows infrastructure plan)

### 2. Enable Automatic Triggers

Once manual testing passes:

1. Edit `.github/workflows/multi-server-terraform.yml`
2. Uncomment the `push:` and `pull_request:` sections
3. Commit the changes

Now the workflow will run automatically on:
- **Push to branch**: Runs plan + apply (deploys infrastructure)
- **Pull requests**: Runs plan only (shows changes)
- **Manual dispatch**: Plan, apply, or destroy as needed

## 🔐 **Security Best Practices**

### 1. Restrict ALLOWED_CIDR
```bash
# Instead of 0.0.0.0/0 (allows everyone), use your IP:
ALLOWED_CIDR = "203.0.113.1/32"

# Or your office range:
ALLOWED_CIDR = "203.0.113.0/24"
```

### 2. Use Environment Protection Rules

Configure environment protection for production:

1. Go to **Settings** → **Environments**
2. Create **prod** environment
3. Add protection rules:
   - Required reviewers
   - Wait timer
   - Deployment branches

### 3. IAM Permissions (Principle of Least Privilege)

Instead of full access policies, create custom policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "s3:*",
        "iam:CreateRole",
        "iam:CreateInstanceProfile",
        "iam:AttachRolePolicy",
        "iam:PassRole",
        "iam:GetRole",
        "iam:ListRoles",
        "logs:*",
        "cloudwatch:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## 🎯 **Workflow Capabilities**

### Automatic Deployments
- **Development**: Auto-deploy when pushing to branch
- **Staging**: Manual trigger with staging environment
- **Production**: Manual trigger with approval required

### Plan Previews
- **Pull Requests**: Shows infrastructure changes before merge
- **Cost Estimates**: Displays estimated monthly costs
- **Validation**: Ensures Terraform syntax is correct

### Manual Operations
- **Plan**: Preview changes without applying
- **Apply**: Deploy infrastructure changes
- **Destroy**: Tear down infrastructure (use carefully!)

## 📊 **Example Secrets Configuration**

Here's a complete example setup:

```bash
# Required secrets
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EC2_KEY_NAME=coolify-terraform

# Security (IMPORTANT: Use your real IP!)
ALLOWED_CIDR=203.0.113.1/32

# Optional customization
AWS_REGION=us-east-1
CONTROL_INSTANCE_TYPE=t4g.micro
REMOTE_INSTANCE_TYPE=t4g.large
REMOTE_SERVER_COUNT=2
DOMAIN_NAME=coolify.yourdomain.com
```

## 🚨 **Troubleshooting**

### Workflow Fails with "Secrets not configured"
- Check that all required secrets are set in repository settings
- Verify secret names match exactly (case-sensitive)
- Ensure secrets have values (not empty)

### AWS Authentication Errors
- Verify AWS credentials are valid
- Check IAM permissions for the user/role
- Ensure AWS region is correct

### Terraform Validation Errors
- Check Terraform syntax in your `.tf` files
- Verify variable types and constraints
- Ensure resource names are valid

### EC2 Key Pair Errors
- Verify key pair exists in target AWS region
- Check EC2_KEY_NAME matches exactly
- Ensure key pair is not deleted from AWS

## 📚 **Advanced Configuration**

### Multi-Environment Deployment

```yaml
# Different configs per environment
dev_secrets:
  CONTROL_INSTANCE_TYPE=t4g.micro
  REMOTE_INSTANCE_TYPE=t4g.small
  REMOTE_SERVER_COUNT=1

staging_secrets:
  CONTROL_INSTANCE_TYPE=t4g.small
  REMOTE_INSTANCE_TYPE=t4g.medium
  REMOTE_SERVER_COUNT=2

prod_secrets:
  CONTROL_INSTANCE_TYPE=t4g.small
  REMOTE_INSTANCE_TYPE=t4g.large
  REMOTE_SERVER_COUNT=3
```

### Terraform Backend (State Management)

For production, configure remote state:

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://your-terraform-state-bucket

# Uncomment and configure in versions.tf:
# backend "s3" {
#   bucket = "your-terraform-state-bucket"
#   key    = "coolify-multi-server/terraform.tfstate"
#   region = "us-east-1"
# }
```

## ✅ **Ready to Deploy!**

Once you've completed the setup:

1. ✅ Configure all required secrets
2. ✅ Test with manual workflow run
3. ✅ Enable automatic triggers
4. ✅ Create your first pull request to test plan preview
5. ✅ Deploy your multi-server Coolify infrastructure!

Your GitHub Actions workflow will now automatically:
- Validate Terraform configurations
- Show cost estimates and change previews
- Deploy infrastructure safely with approval processes
- Provide detailed deployment summaries

**Happy deploying!** 🚀
