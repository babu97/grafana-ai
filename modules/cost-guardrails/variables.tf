variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly spend limit in USD. AWS Budgets only works in USD (~$25 ≈ £20)."
  type        = number
}

variable "cost_tag_key" {
  description = "Tag key the budget filters on. Must match the default_tags in the other stacks."
  type        = string
  default     = "Project"
}

variable "cost_tag_value" {
  description = "Only spend on resources with this tag value counts toward the budget."
  type        = string
}

variable "alert_emails" {
  description = "Email addresses that receive budget alerts."
  type        = list(string)
}

variable "alert_thresholds_percent" {
  description = "Send an alert when ACTUAL spend crosses each of these % of the budget."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "request_gpu_quota" {
  description = "File a Service Quotas increase for on-demand G/VT instance vCPUs. Set false once approved."
  type        = bool
  default     = false
}

variable "gpu_vcpu_quota" {
  description = "Requested vCPU quota for G and VT instances. g4dn.xlarge = 4 vCPUs."
  type        = number
  default     = 8
}
