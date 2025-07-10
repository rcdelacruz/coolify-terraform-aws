#!/bin/bash
# Setup AWS Profile for Coolify
# This script helps you configure a dedicated AWS profile for Coolify

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
        "INFO")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
    esac
}

echo "=== AWS Profile Setup for Coolify ==="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_status "ERROR" "AWS CLI is not installed"
    echo "Please install AWS CLI first:"
    echo "  macOS: brew install awscli"
    echo "  Linux: sudo apt install awscli"
    echo "  Windows: choco install awscli"
    exit 1
fi

print_status "OK" "AWS CLI is installed"

# Check if coolify profile already exists
if aws configure list-profiles 2>/dev/null | grep -q "coolify"; then
    print_status "WARN" "AWS profile 'coolify' already exists"
    echo ""
    read -p "Do you want to reconfigure it? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "INFO" "Using existing profile"
        export AWS_PROFILE=coolify
        aws sts get-caller-identity --profile coolify
        exit 0
    fi
fi

echo ""
print_status "INFO" "Setting up AWS profile 'coolify'"
echo ""
echo "You'll need:"
echo "  1. AWS Access Key ID"
echo "  2. AWS Secret Access Key"
echo "  3. Default region (e.g., us-east-1)"
echo ""
echo "If you don't have these, create them in AWS IAM Console:"
echo "  https://console.aws.amazon.com/iam/home#/users"
echo ""

read -p "Press Enter to continue..."

# Configure the profile
echo ""
print_status "INFO" "Configuring AWS profile 'coolify'..."
aws configure --profile coolify

# Test the profile
echo ""
print_status "INFO" "Testing the profile..."
if aws sts get-caller-identity --profile coolify &> /dev/null; then
    print_status "OK" "Profile configured successfully!"
    
    # Show account info
    AWS_ACCOUNT=$(aws sts get-caller-identity --profile coolify --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --profile coolify --query Arn --output text)
    
    echo ""
    echo "Account Details:"
    echo "  Account ID: $AWS_ACCOUNT"
    echo "  User: $AWS_USER"
    echo "  Profile: coolify"
    
else
    print_status "ERROR" "Profile configuration failed"
    echo "Please check your credentials and try again"
    exit 1
fi

# Set environment variable
echo ""
print_status "INFO" "Setting AWS_PROFILE environment variable..."
export AWS_PROFILE=coolify

# Check if we should add to shell profile
echo ""
read -p "Add 'export AWS_PROFILE=coolify' to your shell profile? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Detect shell
    if [[ $SHELL == *"zsh"* ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    elif [[ $SHELL == *"bash"* ]]; then
        SHELL_PROFILE="$HOME/.bashrc"
    else
        SHELL_PROFILE="$HOME/.profile"
    fi
    
    # Add to shell profile if not already there
    if ! grep -q "export AWS_PROFILE=coolify" "$SHELL_PROFILE" 2>/dev/null; then
        echo "" >> "$SHELL_PROFILE"
        echo "# AWS Profile for Coolify" >> "$SHELL_PROFILE"
        echo "export AWS_PROFILE=coolify" >> "$SHELL_PROFILE"
        print_status "OK" "Added to $SHELL_PROFILE"
        print_status "INFO" "Restart your terminal or run: source $SHELL_PROFILE"
    else
        print_status "INFO" "Already exists in $SHELL_PROFILE"
    fi
fi

echo ""
print_status "OK" "AWS profile setup complete!"
echo ""
echo "Next steps:"
echo "  1. Create EC2 key pair in AWS console"
echo "  2. Configure terraform.tfvars"
echo "  3. Run: cd terraform && ./validate.sh"
echo "  4. Deploy: terraform apply"
echo ""
echo "Current session is ready to use AWS profile 'coolify'"

# Show current profile status
echo ""
echo "=== Current AWS Configuration ==="
aws configure list --profile coolify
