variable "folder_title" {
  type    = string
  default = "GPU demo (managed by Terraform)"
}

variable "datasource_uid" {
  description = "Grafana Cloud's built-in Prometheus datasource."
  type        = string
  default     = "grafanacloud-prom"
}
