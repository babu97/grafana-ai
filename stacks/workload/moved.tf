# Renames are invisible to Terraform: without this, renaming `module.k6` to
# `module.k6_ramp` would destroy the old CronJob and create an identical new one.
# A `moved` block says "same object, new address" — the state is updated in place.
moved {
  from = module.k6
  to   = module.k6_ramp
}
