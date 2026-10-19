# -----------------------------------------------------------------------------
# Cost allocation tag: AWS billing ignores your resource tags until you
# activate the tag key here. Takes up to 24h to start showing in Cost Explorer
# and Budgets, and only counts spend from activation onwards.
# -----------------------------------------------------------------------------
resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = var.cost_tag_key
  status  = "Active"
}

# -----------------------------------------------------------------------------
# Budget: emails you when spend crosses each threshold, plus a forecast alert
# that fires early if AWS predicts you'll exceed the budget this month.
# Filtered to resources tagged <cost_tag_key>=<cost_tag_value>, so the rest of
# the account's spend doesn't count.
# -----------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Format is "user:<TagKey>$<TagValue>" — "user:" marks a user-defined tag.
  # format() avoids HCL's "$${" escape, which would produce a literal "${".
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:%s$%s", var.cost_tag_key, var.cost_tag_value)]
  }

  # One notification block per threshold, generated from the list.
  dynamic "notification" {
    for_each = var.alert_thresholds_percent
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_emails
  }
}

# -----------------------------------------------------------------------------
# GPU quota: "Running On-Demand G and VT instances" (vCPU-based, per region).
# Applying this FILES A REQUEST; it is not instant. `terraform destroy` does
# NOT lower the quota back — it just forgets about it.
# -----------------------------------------------------------------------------
resource "aws_servicequotas_service_quota" "gpu_on_demand" {
  count = var.request_gpu_quota ? 1 : 0

  service_code = "ec2"
  quota_code   = "L-DB2E81BA"
  value        = var.gpu_vcpu_quota
}

# Read-only view of the current quota, so the output always shows the real value.
data "aws_servicequotas_service_quota" "gpu_on_demand" {
  service_code = "ec2"
  quota_code   = "L-DB2E81BA"
}
