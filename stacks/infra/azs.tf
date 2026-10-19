# -----------------------------------------------------------------------------
# Pick AZs automatically, so changing var.region is the only edit needed.
#
# An AZ qualifies if:
#   1. it offers EVERY GPU and system instance type we ask for, and
#   2. EKS supports it. A few AZs can't host EKS control plane ENIs; they're
#      listed by zone ID because zone NAMES are shuffled per account
#      (your us-east-1a is not my us-east-1a), but zone IDs are global.
# -----------------------------------------------------------------------------
locals {
  eks_unsupported_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]
  required_instance_types  = distinct(concat(var.gpu_instance_types, var.system_instance_types))
}

data "aws_availability_zones" "eks_supported" {
  state            = "available"
  exclude_zone_ids = local.eks_unsupported_zone_ids
}

# One lookup per instance type: "which AZs in this region sell it?"
data "aws_ec2_instance_type_offerings" "by_type" {
  for_each      = toset(local.required_instance_types)
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.key]
  }
}

locals {
  # setintersection(a, b, c...) keeps only AZs present in every set.
  # The "..." expands the list of sets into separate arguments.
  candidate_azs = sort(tolist(setintersection(
    toset(data.aws_availability_zones.eks_supported.names),
    [for o in data.aws_ec2_instance_type_offerings.by_type : toset(o.locations)]...
  )))

  azs = coalesce(var.azs, slice(local.candidate_azs, 0, min(var.az_count, length(local.candidate_azs))))
}

check "enough_azs" {
  assert {
    condition     = length(local.azs) >= 2
    error_message = "EKS needs subnets in at least 2 AZs, but only ${length(local.azs)} AZ(s) in ${var.region} offer all of: ${join(", ", local.required_instance_types)}."
  }
}
