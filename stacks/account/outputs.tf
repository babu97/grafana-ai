output "budget_name" {
  value = module.cost_guardrails.budget_name
}

output "gpu_vcpu_quota_current" {
  value = module.cost_guardrails.gpu_vcpu_quota_current
}

output "gpu_vcpu_quota_requested" {
  value = module.cost_guardrails.gpu_vcpu_quota_requested
}
