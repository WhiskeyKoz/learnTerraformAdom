terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state (recommended once the project is stable / shared).
  # Create the bucket once, outside this config, then uncomment and run
  # `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket       = "<your-tf-state-bucket>"
  #   key          = "phase1/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true # native S3 state locking (Terraform >= 1.10)
  # }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags automatically - no need to repeat them.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
