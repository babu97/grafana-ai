output "namespace" {
  value = var.namespace
}

output "grafana_service" {
  description = "Service name to port-forward to."
  value       = "${helm_release.kube_prometheus_stack.name}-grafana"
}

output "prometheus_service" {
  value = "${helm_release.kube_prometheus_stack.name}-kube-prometheus-stack-prometheus"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}

output "prometheus_url" {
  description = "In-cluster URL; layer 4's k6 Job remote-writes here."
  value       = "http://${helm_release.kube_prometheus_stack.name}-kube-prometheus-stack-prometheus.${var.namespace}.svc:9090"
}
