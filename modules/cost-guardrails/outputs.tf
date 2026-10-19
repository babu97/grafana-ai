output "budget_name" {
  value = aws_budgets_budget.monthly.name
}

output "gpu_vcpu_quota_current" {
  description = "Currently approved G/VT vCPU quota in this region."
  value       = data.aws_servicequotas_service_quota.gpu_on_demand.value
}

output "gpu_vcpu_quota_requested" {
  value = var.request_gpu_quota ? var.gpu_vcpu_quota : null
}
