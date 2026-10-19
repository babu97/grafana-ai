# This stack reads BOTH lower layers: infra (how to reach the cluster) and
# platform (where Prometheus lives, which namespace Grafana watches).
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "gpu-demo/infra.tfstate"
    region = var.state_region
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "gpu-demo/platform.tfstate"
    region = var.state_region
  }
}

locals {
  infra    = data.terraform_remote_state.infra.outputs
  platform = data.terraform_remote_state.platform.outputs
}

# -----------------------------------------------------------------------------
# Traffic path:   k6 ──► vllm-router ──► vllm pod on T4 #1
#                                   └──► vllm pod on T4 #2
# -----------------------------------------------------------------------------
module "vllm" {
  source = "../../modules/vllm"

  replicas               = var.vllm_replicas
  image                  = var.vllm_image
  model                  = var.model
  gpu_memory_utilization = var.gpu_memory_utilization
  max_num_seqs           = var.max_num_seqs
}

module "router" {
  source = "../../modules/vllm-router"

  namespace             = module.vllm.namespace
  engine_label_selector = module.vllm.pod_label_selector
  routing_logic         = var.routing_logic
}

# Scenario 1 — "break the GPUs": ramp the request rate until they hit the wall.
module "k6_ramp" {
  source = "../../modules/k6-loadtest"

  name            = "k6-llm-ramp"
  namespace       = module.vllm.namespace
  target_base_url = module.router.base_url
  model           = module.vllm.served_model_name
  prometheus_url  = local.platform.prometheus_url

  stages        = var.k6_stages
  max_tokens    = var.k6_max_tokens
  prompt_repeat = var.k6_prompt_repeat
}

# Scenario 2 — "routing matters": multi-turn sessions with long shared
# histories. Run it once per routing_logic and compare the dashboards.
module "k6_sessions" {
  source = "../../modules/k6-loadtest"

  name            = "k6-llm-sessions"
  script          = "llm-sessions.js"
  namespace       = module.vllm.namespace
  target_base_url = module.router.base_url
  model           = module.vllm.served_model_name
  prometheus_url  = local.platform.prometheus_url

  stages     = var.k6_sessions_stages
  max_tokens = 64 # short answers: prefill (where the cache helps) dominates

  extra_env = {
    USERS          = tostring(var.k6_sessions_users)
    HISTORY_REPEAT = tostring(var.k6_sessions_history_repeat)
    SESSION_HEADER = "x-user-id"
  }
}

# -----------------------------------------------------------------------------
# Scenario 3 — a real app: the Black Friday RAG shopping assistant
# (llm-load-testing-demo). Its LLM calls go through the same router.
#   k6 black_friday.js ──► rag-app ──► postgres (pgvector)
#                                  └─► vllm-router ──► 2× vLLM
# -----------------------------------------------------------------------------
module "rag_app" {
  source = "../../modules/rag-app"

  image        = "${local.infra.rag_app_repository_url}:${var.rag_image_tag}"
  llm_base_url = "${module.router.base_url}/v1"
  llm_model    = module.vllm.served_model_name # "qwen2.5:3b" — same name as Ollama locally
  top_k        = var.rag_top_k
  max_top_k    = var.rag_max_top_k

  max_llm_in_flight = var.rag_max_in_flight
  admission_wait_s  = var.rag_admission_wait_s

  expose_publicly      = var.rag_expose_publicly
  public_allowed_cidrs = var.rag_public_allowed_cidrs

  # With HTTPS on, the ALB only accepts CloudFront (+ secret header).
  cloudfront_origin = var.rag_https ? {
    prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront[0].id
    verify_header  = random_password.origin_verify[0].result
  } : null
}

# --- HTTPS for the shop app via CloudFront (no domain needed) ---------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  count = var.rag_https ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

# Shared secret between CloudFront and the ALB (never shown to browsers).
resource "random_password" "origin_verify" {
  count   = var.rag_https ? 1 : 0
  length  = 32
  special = false
}

module "rag_https" {
  source = "../../modules/cloudfront-https"
  count  = var.rag_https ? 1 : 0

  name                 = "gpu-demo-rag"
  origin_domain        = module.rag_app.alb_hostname
  origin_verify_header = random_password.origin_verify[0].result
  # The viewer allowlist now lives at CloudFront.
  allowed_cidrs = var.rag_public_allowed_cidrs
  tags          = { Project = "gpu-demo" }
}

module "k6_rag" {
  source = "../../modules/k6-loadtest"

  name      = "k6-rag-blackfriday"
  namespace = module.rag_app.namespace
  # Single source of truth: run the script straight from the demo repo.
  script_path     = "${path.root}/../../llm-load-testing-demo/k6/black_friday.js"
  target_base_url = module.rag_app.base_url
  model           = module.vllm.served_model_name # unused by this script
  prometheus_url  = local.platform.prometheus_url

  extra_env = {
    PROFILE = var.rag_k6_profile
    TOP_K   = tostring(var.rag_top_k)
  }
}

module "dashboards" {
  source = "../../modules/grafana-dashboards"

  namespace = local.platform.monitoring_namespace
}
