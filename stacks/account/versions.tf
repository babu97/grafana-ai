terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in S3 (shared settings in ../backend.hcl), so any machine with
  # AWS access sees the same state. Locking stops two machines applying at once.
  backend "s3" {
    key = "gpu-demo/account.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "account"
    }
  }
}
