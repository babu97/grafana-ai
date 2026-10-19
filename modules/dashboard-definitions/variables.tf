variable "datasource_uid" {
  description = <<-EOT
    Prometheus datasource every panel queries. Differs per Grafana:
      in-cluster kube-prometheus-stack -> "prometheus"
      Grafana Cloud                    -> "grafanacloud-prom"
  EOT
  type        = string
}
