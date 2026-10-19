output "vllm_port_forward" {
  description = "Talk to vLLM from your laptop (for a quick curl test)."
  value       = "kubectl -n ${module.vllm.namespace} port-forward svc/${module.vllm.service_name} 8000:8000"
}

output "vllm_logs" {
  value = "kubectl -n ${module.vllm.namespace} logs -f deploy/${module.vllm.service_name}"
}

output "k6_ramp_run" {
  value = module.k6_ramp.run_command
}

output "k6_sessions_run" {
  value = module.k6_sessions.run_command
}

output "routing_logic" {
  value = module.router.routing_logic
}

output "router_port_forward" {
  value = "kubectl -n ${module.vllm.namespace} port-forward svc/${module.router.service_name} 8001:8001"
}

output "dashboard_url" {
  value = "http://localhost:3000${module.dashboards.dashboard_path}"
}

output "router_dashboard_url" {
  value = "http://localhost:3000/d/vllm-router-overview"
}

output "rag_port_forward" {
  value = "kubectl -n ${module.rag_app.namespace} port-forward svc/${module.rag_app.service_name} 8080:8080"
}

output "k6_rag_run" {
  value = module.k6_rag.run_command
}

output "rag_public_url" {
  value = module.rag_app.public_url
}

output "rag_https_url" {
  value = var.rag_https ? module.rag_https[0].https_url : null
}
