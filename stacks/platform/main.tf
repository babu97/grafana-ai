# -----------------------------------------------------------------------------
# Read the infra stack's outputs straight from its state file.
# This is how separate stacks pass values to each other: infra writes outputs,
# platform reads them. If infra isn't applied yet, this fails early and loudly.
# -----------------------------------------------------------------------------
data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "${path.module}/../infra/terraform.tfstate"
  }
}

locals {
  cluster = data.terraform_remote_state.infra.outputs
}

# Grafana Cloud credentials, if that stack has them. `defaults` keeps this
# working before stacks/grafana-cloud exists or has metrics credentials.
data "terraform_remote_state" "grafana_cloud" {
  backend = "local"
  config = {
    path = "${path.module}/../grafana-cloud/terraform.tfstate"
  }
  defaults = {
    prometheus_remote_write = null
  }
}

module "gpu_observability" {
  source = "../../modules/gpu-observability"

  remote_write = data.terraform_remote_state.grafana_cloud.outputs.prometheus_remote_write
}

# Turns Kubernetes Ingress objects into AWS Application Load Balancers.
# Used by the workload stack to expose ONLY the RAG shop app publicly.
module "aws_lb_controller" {
  source = "../../modules/aws-lb-controller"

  cluster_name = local.cluster.cluster_name
  region       = local.cluster.region
  vpc_id       = local.cluster.vpc_id
  tags         = { Project = "gpu-demo" }
}
