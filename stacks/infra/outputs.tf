# The platform stack reads these via terraform_remote_state.

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks_cluster.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks_cluster.oidc_provider_arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.region}"
}

output "azs" {
  description = "AZs chosen by azs.tf."
  value       = local.azs
}

output "vpc_id" {
  description = "Used by the AWS Load Balancer Controller (platform stack)."
  value       = module.network.vpc_id
}
