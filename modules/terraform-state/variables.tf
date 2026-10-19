variable "bucket_name" {
  description = "Globally unique. Also hard-coded in stacks/backend.hcl (backend blocks can't use variables)."
  type        = string
}

variable "noncurrent_version_days" {
  description = "Keep old state versions this long — your undo button for a bad apply."
  type        = number
  default     = 90
}
