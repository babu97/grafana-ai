output "dashboards" {
  description = "Map of file name => dashboard JSON."
  value = {
    "gpu-breaking-point.json"   = jsonencode(local.dashboard)
    "vllm-router-overview.json" = local.router_overview
  }
}

output "gpu_breaking_point_uid" {
  value = local.dashboard.uid
}
