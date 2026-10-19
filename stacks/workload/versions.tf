terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# For CloudFront (HTTPS in front of the RAG app's ALB).
provider "aws" {
  region = local.infra.region

  default_tags {
    tags = {
      Project   = "gpu-demo"
      ManagedBy = "terraform"
      Stack     = "workload"
    }
  }
}

# Same login pattern as the platform stack's helm provider: endpoint + CA from
# the infra state, a fresh token from `aws eks get-token` on every run.
provider "kubernetes" {
  host                   = local.infra.cluster_endpoint
  cluster_ca_certificate = base64decode(local.infra.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.infra.cluster_name, "--region", local.infra.region]
  }
}
