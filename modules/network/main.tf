# -----------------------------------------------------------------------------
# Subnet maths: carve the /16 into one /20 private + one /24 public per AZ.
#   cidrsubnet("10.0.0.0/16", 4, i)     -> 10.0.0.0/20, 10.0.16.0/20, ...  (4096 IPs each)
#   cidrsubnet("10.0.0.0/16", 8, 48+i)  -> 10.0.48.0/24, 10.0.49.0/24, ... (256 IPs each)
# Private subnets are big because the VPC CNI gives every pod a real VPC IP.
# -----------------------------------------------------------------------------
locals {
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.cidr, 4, i)]
  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, 48 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Nodes live in private subnets and reach the internet (image pulls, Hugging
  # Face downloads) through NAT. One NAT instead of one-per-AZ saves ~$0.10/hr;
  # fine for a demo, a single point of failure in production.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # These tags tell the AWS Load Balancer Controller which subnets to use for
  # internet-facing vs internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}
