terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.50"
    }
  }

  # State lives in S3 (shared settings in ../backend.hcl), so any machine with
  # AWS access sees the same state. Locking stops two machines applying at once.
  backend "s3" {
    key = "gpu-demo/grafana-cloud.tfstate"
  }

  # Long-lived like `account`: NOT part of `make up` / `make down`, so your
  # dashboards and rehearsal data survive every cluster rebuild.
}

# Only used to read the Grafana tokens from SSM Parameter Store.
provider "aws" {
  region = var.ssm_region
}

# Logs in to your Grafana Cloud instance as the `terraform` service account.
# The token comes from SSM (encrypted), not from a file on disk.
provider "grafana" {
  url  = var.grafana_url
  auth = data.aws_ssm_parameter.sa_token.value
}
