output "ingress_class" {
  description = "IngressClass the controller handles."
  value       = "alb"
}

output "iam_role_arn" {
  value = module.pod_identity.iam_role_arn
}
