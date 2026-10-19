output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "base_url" {
  description = "In-cluster URL of the shopping assistant."
  value       = "http://${kubernetes_service_v1.app.metadata[0].name}.${kubernetes_namespace_v1.this.metadata[0].name}.svc:8080"
}

output "service_name" {
  value = kubernetes_service_v1.app.metadata[0].name
}

output "public_url" {
  description = "Public URL (null unless expose_publicly = true)."
  value       = var.expose_publicly ? "http://${kubernetes_ingress_v1.public[0].status[0].load_balancer[0].ingress[0].hostname}" : null
}

output "alb_hostname" {
  description = "Raw ALB hostname (CloudFront's origin)."
  value       = var.expose_publicly ? kubernetes_ingress_v1.public[0].status[0].load_balancer[0].ingress[0].hostname : null
}
