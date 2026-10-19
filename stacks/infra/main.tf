locals {
  name = var.project

  # Provider default_tags cover resources Terraform creates directly, but NOT
  # the EC2 instances/volumes EKS launches from a launch template. Passing tags
  # into the modules puts them on those too, so the GPU node shows up in the
  # Project=gpu-demo budget.
  tags = { Project = var.project }
}

module "network" {
  source = "../../modules/network"

  name         = "${local.name}-vpc"
  cluster_name = local.name
  azs          = local.azs
  tags         = local.tags
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # Module-to-module wiring: network outputs feed straight into the cluster.
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  system_instance_types = var.system_instance_types
  gpu_instance_types    = var.gpu_instance_types
  gpu_capacity_type     = var.gpu_capacity_type
  gpu_node_count        = var.gpu_node_count

  tags = local.tags
}
