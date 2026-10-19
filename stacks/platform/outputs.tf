output "grafana_port_forward" {
  value = "kubectl -n ${module.gpu_observability.namespace} port-forward svc/${module.gpu_observability.grafana_service} 3000:80"
}

output "prometheus_port_forward" {
  value = "kubectl -n ${module.gpu_observability.namespace} port-forward svc/${module.gpu_observability.prometheus_service} 9090:9090"
}

output "grafana_admin_password" {
  description = "Show with: terraform -chdir=stacks/platform output -raw grafana_admin_password"
  value       = module.gpu_observability.grafana_admin_password
  sensitive   = true
}

output "monitoring_namespace" {
  value = module.gpu_observability.namespace
}

output "prometheus_url" {
  value = module.gpu_observability.prometheus_url
}

output "ingress_class" {
  value = module.aws_lb_controller.ingress_class
}
