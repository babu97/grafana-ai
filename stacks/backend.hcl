# Shared S3 backend settings for every stack (each stack sets its own `key`).
# Used via: terraform init -backend-config=../backend.hcl  (the Makefile does this)
bucket       = "gpu-demo-tfstate-7cf9d370" # created by stacks/account
region       = "eu-west-1"
encrypt      = true
use_lockfile = true # S3-native state locking (Terraform >= 1.10), no DynamoDB
