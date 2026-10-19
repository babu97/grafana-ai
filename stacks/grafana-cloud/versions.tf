terraform {
  required_version = ">= 1.10"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.50"
    }
  }

  # Long-lived like `account`: NOT part of `make up` / `make down`, so your
  # dashboards and rehearsal data survive every cluster rebuild.
}

# Logs in to your Grafana Cloud instance as the `terraform` service account.
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_sa_token
}
