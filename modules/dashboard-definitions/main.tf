# -----------------------------------------------------------------------------
# Dashboard definitions only — no providers, no resources. Takes a datasource
# uid, returns dashboard JSON. Used by:
#   modules/grafana-dashboards        -> ConfigMaps for the in-cluster Grafana
#   modules/grafana-cloud-dashboards  -> grafana_dashboard in Grafana Cloud
# One source of truth, two Grafanas.
# -----------------------------------------------------------------------------
locals {
  # Your router dashboard, kept as a plain JSON file so it can be edited in
  # Grafana and re-exported. templatefile() swaps ${DS_UID} for the right uid.
  router_overview = templatefile("${path.module}/dashboards/vllm-router-overview.json", {
    DS_UID = var.datasource_uid
  })
}
