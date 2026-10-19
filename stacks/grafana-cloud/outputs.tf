output "dashboard_urls" {
  value = { for k, path in module.dashboards.dashboard_urls : k => path }
}

# The platform stack reads this (terraform_remote_state) to configure
# Prometheus remote_write. null until prom_username + prom_write_token are set.
output "prometheus_remote_write" {
  sensitive = true
  value = var.prom_username == null || var.prom_write_token == null ? null : {
    url      = var.prom_remote_write_url
    username = var.prom_username
    password = var.prom_write_token
  }
}
