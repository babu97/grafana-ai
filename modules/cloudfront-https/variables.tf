variable "name" {
  type = string
}

variable "origin_domain" {
  description = "The ALB hostname CloudFront forwards to (plain HTTP inside AWS)."
  type        = string
}

variable "origin_verify_header" {
  description = "Secret header value CloudFront adds; the ALB only answers requests that carry it."
  type        = string
  sensitive   = true
}

variable "allowed_cidrs" {
  description = "IPv4 CIDRs allowed through CloudFront. [\"0.0.0.0/0\"] = everyone."
  type        = list(string)
}

variable "origin_read_timeout" {
  description = "Seconds CloudFront waits for the first byte. Max 60 without an AWS quota increase; under overload, slower answers become 504."
  type        = number
  default     = 60
}

variable "tags" {
  type    = map(string)
  default = {}
}
