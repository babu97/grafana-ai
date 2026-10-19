data "aws_ssm_parameter" "sa_token" {
  name = "${var.ssm_prefix}/sa-token" # Grafana service account (Admin), glsa_...
}

data "aws_ssm_parameter" "prom_write_token" {
  name = "${var.ssm_prefix}/prom-write-token" # access policy token, metrics:write
}

module "dashboards" {
  source = "../../modules/grafana-cloud-dashboards"
}
