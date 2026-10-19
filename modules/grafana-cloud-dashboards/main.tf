# Same dashboards as the in-cluster Grafana, generated from the same
# definitions — only the datasource uid differs.
module "definitions" {
  source = "../dashboard-definitions"

  datasource_uid = var.datasource_uid
}

resource "grafana_folder" "talk" {
  title = var.folder_title
}

# for_each over a map: one grafana_dashboard per JSON, keyed by file name.
# Add a dashboard to dashboard-definitions and it appears here automatically.
resource "grafana_dashboard" "this" {
  for_each = module.definitions.dashboards

  folder      = grafana_folder.talk.uid
  config_json = each.value

  # Terraform is the source of truth: edits made in the UI get overwritten
  # on the next apply (export them back into the repo instead).
  overwrite = true
}
