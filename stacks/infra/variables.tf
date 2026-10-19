variable "project" {
  type    = string
  default = "gpu-demo"
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "az_count" {
  description = "How many AZs to spread subnets across. AZs are picked automatically (see azs.tf)."
  type        = number
  default     = 3
}

variable "azs" {
  description = "Override the automatic AZ choice, e.g. [\"eu-west-1a\", \"eu-west-1b\"]. Leave null to auto-select."
  type        = list(string)
  default     = null
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "system_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "gpu_instance_types" {
  type    = list(string)
  default = ["g4dn.xlarge"]
}

variable "gpu_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "gpu_node_count" {
  description = "Applied at creation only — see modules/eks-cluster/variables.tf."
  type        = number
  default     = 2
}
