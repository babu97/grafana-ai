# Each stack has its own state. Order matters: build bottom-up, destroy top-down.
# `account` and `grafana-cloud` are deliberately NOT part of up/down — they
# outlive every rebuild (budget, dashboards, rehearsal data).
UP_ORDER   := infra platform workload
DOWN_ORDER := workload platform infra

.PHONY: account grafana-cloud up down fmt validate build-rag apply-% destroy-% plan-%

account: apply-account

grafana-cloud: apply-grafana-cloud

up: $(addprefix apply-,$(UP_ORDER))

down: $(addprefix destroy-,$(DOWN_ORDER))

init-%:
	terraform -chdir=stacks/$* init -upgrade

plan-%: init-%
	terraform -chdir=stacks/$* plan

apply-%: init-%
	terraform -chdir=stacks/$* apply

destroy-%:
	terraform -chdir=stacks/$* destroy

fmt:
	terraform fmt -recursive

validate:
	@for s in stacks/*; do echo "== $$s"; terraform -chdir=$$s init -backend=false -input=false >/dev/null && terraform -chdir=$$s validate || exit 1; done

# --- RAG app image (llm-load-testing-demo) -----------------------------------
# Your Mac is arm64, EKS nodes are amd64: buildx cross-builds via emulation.
# Tags the image with a unique tag AND "latest", and writes the tag to
# stacks/workload/rag-image.auto.tfvars (*.auto.tfvars load automatically),
# so the next `make apply-workload` rolls out exactly this build.
RAG_DIR  := llm-load-testing-demo
RAG_REPO  = $(shell terraform -chdir=stacks/infra output -raw rag_app_repository_url)
# Commit sha, plus "-dirty-<timestamp>" when there are uncommitted changes, so
# every build gets a unique tag and Terraform sees a change to roll out.
RAG_TAG  := $(shell git -C $(RAG_DIR) rev-parse --short HEAD)$(shell git -C $(RAG_DIR) diff --quiet HEAD || echo "-dirty-$$(date +%Y%m%d%H%M%S)")
REGION    = $(shell terraform -chdir=stacks/infra output -raw region)

build-rag:
	aws ecr get-login-password --region $(REGION) | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(RAG_REPO)))
	docker buildx build --platform linux/amd64 -f $(RAG_DIR)/app/Dockerfile \
	  -t $(RAG_REPO):$(RAG_TAG) -t $(RAG_REPO):latest --push $(RAG_DIR)
	@echo 'rag_image_tag = "$(RAG_TAG)"' > stacks/workload/rag-image.auto.tfvars
	@echo "Pushed $(RAG_REPO):$(RAG_TAG) (and :latest); wrote stacks/workload/rag-image.auto.tfvars"
	@echo "Deploy it with: make apply-workload"
