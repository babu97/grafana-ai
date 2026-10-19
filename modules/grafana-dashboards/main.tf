module "definitions" {
  source = "../dashboard-definitions"

  datasource_uid = var.datasource_uid
}

# Grafana's dashboard sidecar (enabled in layer 3) watches for ConfigMaps
# labelled grafana_dashboard=1 and loads the JSON inside them. No Grafana API
# calls, no provider for Grafana — just a Kubernetes object.
resource "kubernetes_config_map_v1" "breaking_point" {
  metadata {
    name      = "dashboard-gpu-breaking-point"
    namespace = var.namespace
    labels    = { grafana_dashboard = "1" }
  }

  data = {
    "gpu-breaking-point.json" = module.definitions.dashboards["gpu-breaking-point.json"]
  }
}

resource "kubernetes_config_map_v1" "router_overview" {
  metadata {
    name      = "dashboard-vllm-router-overview"
    namespace = var.namespace
    labels    = { grafana_dashboard = "1" }
  }

  data = {
    "vllm-router-overview.json" = module.definitions.dashboards["vllm-router-overview.json"]
  }
}
