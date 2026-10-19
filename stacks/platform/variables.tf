
# Where the other stacks' state lives (same bucket as stacks/backend.hcl).
variable "state_bucket" {
  type    = string
  default = "gpu-demo-tfstate-7cf9d370"
}

variable "state_region" {
  type    = string
  default = "eu-west-1"
}
