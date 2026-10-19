output "dashboard_urls" {
  value = { for k, d in grafana_dashboard.this : k => d.url }
}
