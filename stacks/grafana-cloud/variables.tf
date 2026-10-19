variable "grafana_url" {
  description = "Your Grafana Cloud stack, e.g. https://<stack>.grafana.net"
  type        = string
}

# --- Secrets live in AWS SSM Parameter Store (SecureString), not in files ----
# Store/rotate them with:
#   aws ssm put-parameter --overwrite --type SecureString \
#     --name /gpu-demo/grafana-cloud/sa-token         --value 'glsa_...'
#   aws ssm put-parameter --overwrite --type SecureString \
#     --name /gpu-demo/grafana-cloud/prom-write-token --value 'glc_...=='
variable "ssm_prefix" {
  type    = string
  default = "/gpu-demo/grafana-cloud"
}

variable "ssm_region" {
  type    = string
  default = "eu-west-1"
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

