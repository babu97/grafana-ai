variable "grafana_url" {
  description = "Your Grafana Cloud stack, e.g. https://<stack>.grafana.net"
  type        = string
}

variable "grafana_sa_token" {
  description = "Service account token (glsa_...) with Editor role."
  type        = string
  sensitive   = true
}

# --- Metrics push (used by the platform stack's Prometheus remote_write) -----

variable "prom_remote_write_url" {
  description = "grafana.com -> stack -> Prometheus -> Details -> Remote Write Endpoint (.../api/prom/push)."
  type        = string
}

variable "prom_username" {
  description = "Prometheus Username / Instance ID (a number). null = metrics push not configured yet."
  type        = string
  default     = null
}

variable "prom_write_token" {
  description = "Access policy token (glc_...) with metrics:write."
  type        = string
  default     = null
  sensitive   = true
}
