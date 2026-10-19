variable "datasource_uid" {
  description = <<-EOT
    Prometheus datasource every panel queries. Differs per Grafana:
      in-cluster kube-prometheus-stack -> "prometheus"
      Grafana Cloud                    -> "grafanacloud-prom"
  EOT
  type        = string
}

variable "max_num_seqs" {
  description = "vLLM --max-num-seqs per GPU (keep in sync with the workload stack). Drawn as the capacity line."
  type        = number
  default     = 128
}

variable "ttft_slo_seconds" {
  description = "Shopper time-to-first-word SLO. Must match a rag_ttft_seconds bucket boundary (le) and the k6 threshold."
  type        = number
  default     = 2
}
