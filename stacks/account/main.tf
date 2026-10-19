# Budget alert recipients come from SSM, so no e-mail address lives in git.
data "aws_ssm_parameter" "alert_emails" {
  name = var.alert_emails_ssm_parameter
}

module "cost_guardrails" {
  source = "../../modules/cost-guardrails"

  name               = var.project
  cost_tag_value     = var.project
  monthly_budget_usd = var.monthly_budget_usd
  alert_emails       = split(",", data.aws_ssm_parameter.alert_emails.value)
  request_gpu_quota  = var.request_gpu_quota
  gpu_vcpu_quota     = var.gpu_vcpu_quota
}

# Remote state for ALL stacks. Created here first (with local state), then
# this stack's own state moves into it too — see stacks/backend.hcl.
module "terraform_state" {
  source = "../../modules/terraform-state"

  bucket_name = "gpu-demo-tfstate-7cf9d370"
}
