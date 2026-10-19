output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_name" {
  value = kubernetes_service_v1.vllm.metadata[0].name
}

output "base_url" {
  description = "In-cluster OpenAI-compatible endpoint."
  value       = "http://${kubernetes_service_v1.vllm.metadata[0].name}.${kubernetes_namespace_v1.this.metadata[0].name}.svc:8000"
}

output "served_model_name" {
  value = var.served_model_name
}

output "pod_label_selector" {
  description = "Label selector matching the vLLM engine pods (used by the router)."
  value       = join(",", [for k, v in local.labels : "${k}=${v}"])
}
