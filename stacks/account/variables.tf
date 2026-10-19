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

variable "alert_emails_ssm_parameter" {
  description = "SSM StringList with the budget alert e-mails (kept out of git). Set with: aws ssm put-parameter --type StringList --name /gpu-demo/account/alert-emails --value 'a@x.com,b@y.com'"
  type        = string
  default     = "/gpu-demo/account/alert-emails"
}

variable "request_gpu_quota" {
  type    = bool
  default = false
}

variable "gpu_vcpu_quota" {
  type    = number
  default = 8
}
