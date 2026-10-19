terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
  }

  # Local state at stacks/infra/terraform.tfstate. The platform stack reads it
  # with a terraform_remote_state data source to find the cluster.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "infra"
    }
  }
}
