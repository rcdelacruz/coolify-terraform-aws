# Terraform versions and provider requirements
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Backend configuration (uncomment and configure for production)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "coolify-multi-server/terraform.tfstate"
  #   region = "us-east-1"
  # }
}
