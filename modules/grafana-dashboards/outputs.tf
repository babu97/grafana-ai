output "dashboard_uid" {
  value = module.definitions.gpu_breaking_point_uid
}

output "dashboard_path" {
  description = "Open on http://localhost:3000 after port-forwarding Grafana."
  value       = "/d/${module.definitions.gpu_breaking_point_uid}"
}
