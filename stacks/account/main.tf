module "cost_guardrails" {
  source = "../../modules/cost-guardrails"

  name               = var.project
  cost_tag_value     = var.project
  monthly_budget_usd = var.monthly_budget_usd
  alert_emails       = var.alert_emails
  request_gpu_quota  = var.request_gpu_quota
  gpu_vcpu_quota     = var.gpu_vcpu_quota
}
