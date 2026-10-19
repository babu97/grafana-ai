variable "namespace" {
  description = "Namespace for the dashboard ConfigMap. Grafana's sidecar watches all namespaces; keeping it next to Grafana is tidy."
  type        = string
}

variable "datasource_uid" {
  description = "kube-prometheus-stack provisions its Prometheus datasource with uid 'prometheus'."
  type        = string
  default     = "prometheus"
}
