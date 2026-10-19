variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "chart_version" {
  type    = string
  default = "3.6.0"
}

variable "tags" {
  description = "Added to every AWS resource the controller creates (ALBs, target groups, security groups) — so they count in the Project budget."
  type        = map(string)
  default     = {}
}
