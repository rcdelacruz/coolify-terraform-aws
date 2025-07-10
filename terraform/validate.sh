#!/bin/bash
# Terraform validation and pre-deployment checks

set -e

echo "=== Coolify Terraform AWS Validation ==="
echo "Timestamp: $(date)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}✗${NC} $message"
            ;;
    esac
}

# Check if we're in the terraform directory
if [ ! -f "main.tf" ]; then
    print_status "ERROR" "Please run this script from the terraform directory"
    exit 1
fi

print_status "OK" "Running from terraform directory"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    print_status "WARN" "terraform.tfvars not found. Please copy from terraform.tfvars.example"
    echo "Run: cp terraform.tfvars.example terraform.tfvars"
    exit 1
fi

print_status "OK" "terraform.tfvars found"

# Check required tools
echo ""
echo "=== Checking Required Tools ==="

# Check Terraform
if command -v terraform &> /dev/null; then
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    print_status "OK" "Terraform installed (version: $TERRAFORM_VERSION)"
else
    print_status "ERROR" "Terraform not installed"
    exit 1
fi

# Check AWS CLI
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    print_status "OK" "AWS CLI installed (version: $AWS_VERSION)"
else
    print_status "ERROR" "AWS CLI not installed"
    exit 1
fi

# Check AWS credentials
echo ""
echo "=== Checking AWS Configuration ==="

# Check if AWS_PROFILE is set
if [ -n "$AWS_PROFILE" ]; then
    print_status "OK" "AWS_PROFILE set to: $AWS_PROFILE"
    PROFILE_FLAG="--profile $AWS_PROFILE"
else
    print_status "WARN" "AWS_PROFILE not set, using default profile"
    PROFILE_FLAG=""
fi

if aws sts get-caller-identity $PROFILE_FLAG &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity $PROFILE_FLAG --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity $PROFILE_FLAG --query Arn --output text)
    print_status "OK" "AWS credentials configured"
    echo "    Account: $AWS_ACCOUNT"
    echo "    User: $AWS_USER"
    if [ -n "$AWS_PROFILE" ]; then
        echo "    Profile: $AWS_PROFILE"
    fi
else
    print_status "ERROR" "AWS credentials not configured or invalid"
    if [ -n "$AWS_PROFILE" ]; then
        echo "Run: aws configure --profile $AWS_PROFILE"
    else
        echo "Run: aws configure --profile coolify"
        echo "Then: export AWS_PROFILE=coolify"
    fi
    exit 1
fi

# Validate terraform.tfvars
echo ""
echo "=== Validating terraform.tfvars ==="

# Check for required variables
KEY_NAME=$(grep -E "^key_name" terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
if [ -z "$KEY_NAME" ] || [ "$KEY_NAME" = "your-key-pair-name" ]; then
    print_status "ERROR" "key_name not set in terraform.tfvars"
    echo "Please set a valid EC2 key pair name"
    exit 1
fi

print_status "OK" "key_name set to: $KEY_NAME"

# Check if key pair exists in AWS
REGION=$(grep -E "^region" terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" $PROFILE_FLAG &> /dev/null; then
    print_status "OK" "Key pair '$KEY_NAME' exists in region $REGION"
else
    print_status "ERROR" "Key pair '$KEY_NAME' not found in region $REGION"
    echo "Create the key pair in AWS console or update terraform.tfvars"
    exit 1
fi

# Check allowed_cidrs
ALLOWED_CIDRS=$(grep -E "^allowed_cidrs" terraform.tfvars || echo "")
if echo "$ALLOWED_CIDRS" | grep -q "0.0.0.0/0"; then
    print_status "WARN" "allowed_cidrs includes 0.0.0.0/0 (open to all IPs)"
    echo "Consider restricting to your IP address for better security"
fi

# Terraform validation
echo ""
echo "=== Terraform Validation ==="

# Format check
if terraform fmt -check &> /dev/null; then
    print_status "OK" "Terraform formatting is correct"
else
    print_status "WARN" "Terraform files need formatting"
    echo "Run: terraform fmt"
fi

# Initialize
echo "Initializing Terraform..."
if terraform init &> /dev/null; then
    print_status "OK" "Terraform initialized successfully"
else
    print_status "ERROR" "Terraform initialization failed"
    exit 1
fi

# Validate
echo "Validating Terraform configuration..."
if terraform validate &> /dev/null; then
    print_status "OK" "Terraform configuration is valid"
else
    print_status "ERROR" "Terraform validation failed"
    terraform validate
    exit 1
fi

# Plan
echo "Creating Terraform plan..."
if terraform plan -out=terraform.tfplan &> /dev/null; then
    print_status "OK" "Terraform plan created successfully"
else
    print_status "ERROR" "Terraform plan failed"
    terraform plan
    exit 1
fi

# Cost estimation (if available)
echo ""
echo "=== Cost Estimation ==="
print_status "OK" "Estimated monthly cost: ~$65-75"
echo "    - EC2 t4g.large: ~$53/month"
echo "    - 100GB GP3 storage: ~$8/month"
echo "    - 20GB root volume: ~$2/month"
echo "    - Elastic IP: ~$4/month"
echo "    - S3 backup storage: ~$2-5/month"
echo "    - CloudWatch logs: ~$1-2/month"

# Security recommendations
echo ""
echo "=== Security Recommendations ==="
print_status "OK" "Review security settings:"
echo "    - Update allowed_cidrs to restrict access to your IP"
echo "    - Ensure your EC2 key pair is secure"
echo "    - Consider enabling AWS CloudTrail for audit logging"
echo "    - Review IAM permissions for the deployment user"

echo ""
echo "=== Validation Complete ==="
print_status "OK" "All checks passed! Ready to deploy."
echo ""
echo "To deploy:"
echo "  terraform apply terraform.tfplan"
echo ""
echo "To destroy (when needed):"
echo "  terraform destroy"
