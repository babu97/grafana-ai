# cp terraform.tfvars.example terraform.tfvars

# Rehearsals: cheap, uses your 64-vCPU Spot quota. g4dn.2xlarge is still 1x T4,
# listed as a fallback in case xlarge Spot capacity is short.
gpu_capacity_type  = "SPOT"
gpu_instance_types = ["g4dn.xlarge", "g4dn.2xlarge"]

# Talk day: switch to these and re-apply.
# gpu_capacity_type  = "ON_DEMAND"
# gpu_instance_types = ["g4dn.xlarge"]

# GPU nodes at creation (default 2: one vLLM replica each, router balances).
# Only applied when the node group is CREATED; a live cluster ignores changes.
# gpu_node_count = 1
