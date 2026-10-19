output "base_url" {
  description = "In-cluster OpenAI-compatible endpoint (load-balanced)."
  value       = "http://${kubernetes_service_v1.router.metadata[0].name}.${var.namespace}.svc:${local.port}"
}

output "service_name" {
  value = kubernetes_service_v1.router.metadata[0].name
}

output "routing_logic" {
  value = var.routing_logic
}
