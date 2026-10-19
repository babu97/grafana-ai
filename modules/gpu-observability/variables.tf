variable "namespace" {
  description = "Namespace for Prometheus, Grafana and the DCGM exporter."
  type        = string
  default     = "monitoring"
}

# Pin chart versions so a rebuild tomorrow installs exactly what worked today.
variable "device_plugin_chart_version" {
  type    = string
  default = "0.20.1"
}

variable "kube_prometheus_stack_chart_version" {
  type    = string
  default = "92.1.0"
}

variable "dcgm_exporter_chart_version" {
  type    = string
  default = "4.8.4"
}

variable "gpu_scrape_interval" {
  description = "How often Prometheus scrapes GPU metrics. Short = smoother 'wall' on stage, more load."
  type        = string
  default     = "5s"
}

variable "prometheus_retention" {
  description = "Data only needs to outlive one rehearsal; the cluster is destroyed after anyway."
  type        = string
  default     = "1d"
}

variable "remote_write" {
  description = "Push a filtered copy of metrics to Grafana Cloud. null = off (local Prometheus only)."
  type = object({
    url      = string
    username = string
    password = string
  })
  default   = null
  sensitive = true
}

variable "remote_write_keep_regex" {
  description = "Only metric names matching this are sent — keeps us inside the free tier's 10k series."
  type        = string
  default     = "DCGM_.*|vllm:.*|k6_.*|rag_.*|router_.*|up"
}

variable "cluster_label" {
  description = "Added to every series sent to Grafana Cloud, so rebuilds/rehearsals stay distinguishable."
  type        = string
  default     = "gpu-demo"
}
