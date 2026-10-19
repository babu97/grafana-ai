output "dashboard_urls" {
  value = { for k, path in module.dashboards.dashboard_urls : k => path }
}

# The platform stack reads this (terraform_remote_state) to configure
# Prometheus remote_write. null until prom_username is set.
output "prometheus_remote_write" {
  sensitive = true
  value = var.prom_username == null ? null : {
    url      = var.prom_remote_write_url
    username = var.prom_username
    password = data.aws_ssm_parameter.prom_write_token.value
  }
}
