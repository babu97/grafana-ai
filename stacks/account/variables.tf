variable "project" {
  type    = string
  default = "gpu-demo"
}

variable "region" {
  description = "Quotas are per-region, so this must match the infra stack."
  type        = string
  default     = "eu-west-1"
}

variable "monthly_budget_usd" {
  type    = number
  default = 25
}

variable "alert_emails" {
  type = list(string)
}

variable "request_gpu_quota" {
  type    = bool
  default = false
}

variable "gpu_vcpu_quota" {
  type    = number
  default = 8
}
