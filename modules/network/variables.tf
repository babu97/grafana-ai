variable "name" {
  description = "Name prefix for the VPC and its resources."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name, used for the subnet discovery tag."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. Pick AZs that offer your GPU instance type."
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
