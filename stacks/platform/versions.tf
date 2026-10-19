terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.59"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# The AWS Load Balancer Controller needs an IAM role (created in AWS).
provider "aws" {
  region = local.cluster.region

  default_tags {
    tags = {
      Project   = "gpu-demo"
      ManagedBy = "terraform"
      Stack     = "platform"
    }
  }
}

# -----------------------------------------------------------------------------
# How Terraform logs in to the cluster.
#
# Endpoint + CA come from the infra stack's state (see main.tf). The token
# comes from `aws eks get-token`, run fresh on every Terraform command, using
# your normal AWS credentials — no kubeconfig file needed, nothing expires
# mid-apply. This is why infra and platform are separate stacks: these values
# must already exist when this provider is configured.
# -----------------------------------------------------------------------------
provider "helm" {
  kubernetes = {
    host                   = local.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster.cluster_name, "--region", local.cluster.region]
    }
  }
}
