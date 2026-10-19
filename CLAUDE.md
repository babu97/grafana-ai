# gpu-demo: breaking T4 GPUs with vLLM, observed with Grafana

Infrastructure for a Grafana meetup talk: self-hosted vLLM on AWS EKS GPUs,
loaded with k6 until it breaks, with every layer visible in Grafana.
Everything is Terraform. The owner is learning Terraform: explain concepts,
build layer by layer, show a plan before applying.

## Working agreements
- Propose 2-3 options with a recommendation before implementing; plan, then build.
- **Ask before any apply that starts billing** (GPU nodes, cluster). Remind to
  `make down` (or scale GPUs to 0) after sessions.
- The AWS account is **shared with other workloads**: budget is filtered on tag
  `Project=gpu-demo`; Route 53 zones in the account belong to others — never
  use them without explicit OK.
- Never commit secrets. Secrets live in AWS SSM (see below), state in S3.

## Layout
```
modules/            reusable modules (most wrap terraform-aws-modules)
stacks/             things you apply — each has its own S3 state key
  account/          budget + cost tag + S3 state bucket      (long-lived, NOT in up/down)
  grafana-cloud/    Grafana Cloud folder + dashboards         (long-lived, NOT in up/down)
  infra/            VPC, EKS 1.36, system + GPU node groups, ECR
  platform/         device plugin, kube-prometheus-stack, DCGM, AWS LB controller
  workload/         vLLM x2, vllm-router, RAG shop app, k6 CronJobs, dashboards, CloudFront
  backend.hcl       shared S3 backend settings
notes/              measured results (read these before re-running experiments)
../llm-load-testing-demo  (sibling folder) the RAG shop app — separate repo
```
Order: `make up` = infra → platform → workload; `make down` = reverse.
Stacks read each other via `terraform_remote_state` (S3).

## Everyday commands
```bash
make bootstrap            # new machine: tools, app repo, terraform init
make up / make down       # build / destroy cluster layers (asks for "yes" per stack)
make plan-<stack> / make apply-<stack> / make destroy-<stack>
make build-rag            # build+push app image (amd64), writes rag-image.auto.tfvars
make apply-workload       # roll out app/router/k6/dashboard changes
aws eks update-kubeconfig --name gpu-demo --region eu-west-1
kubectl -n rag create job --from=cronjob/k6-rag-blackfriday bf-$(date +%s)   # Black Friday load
kubectl -n llm create job --from=cronjob/k6-llm-sessions s-$(date +%s)        # routing demo
```
Scale GPUs without destroying (Terraform ignores desired_size after creation):
`aws eks update-nodegroup-config --cluster-name gpu-demo --nodegroup-name <gpu-...> --scaling-config minSize=0,maxSize=2,desiredSize=N`

## State and secrets
- State: S3 bucket `gpu-demo-tfstate-7cf9d370` (eu-west-1, versioned, encrypted,
  `use_lockfile` locking), key `gpu-demo/<stack>.tfstate`. Never edit by hand.
- Secrets (SSM Parameter Store, eu-west-1):
  - `/gpu-demo/grafana-cloud/sa-token` — Grafana SA token (role **Admin**; Editor can't manage folders)
  - `/gpu-demo/grafana-cloud/prom-write-token` — access-policy token with **metrics:write**
  - `/gpu-demo/account/alert-emails` — budget alert recipients
- Non-secret settings: `stacks/*/config.auto.tfvars` (committed).
- State still contains generated secrets (Grafana admin pw, Postgres pw,
  CloudFront origin header) — it's encrypted in S3.

## What's deployed (when up)
- 2x g4dn.xlarge Tesla T4 (Spot for rehearsals; ON_DEMAND on talk day) + 2x t3.large system nodes (60 GB disk).
- vLLM v0.30.0 (CUDA 13 image), Qwen/Qwen2.5-3B-Instruct, `--dtype half`, served as
  **`qwen2.5:3b`** (alias `qwen-3b`) — same name as Ollama locally. KV cache ~169,856 tokens/T4.
- vllm-router (lmcache/lmstack-router v0.1.13), Service `vllm-router-demo`, routing
  `roundrobin|session|prefixaware` (set `routing_logic` in workload config).
- RAG shop app (namespace `rag`): FastAPI + fastembed (CPU) + pgvector; only the
  LLM call uses GPUs. Public via ALB (locked to CloudFront prefix list + secret
  header) + CloudFront HTTPS (`*.cloudfront.net`, open to all). `/metrics` blocked.
- Prometheus remote_writes only `DCGM_|vllm:|k6_|rag_|router_|up` to Grafana Cloud
  (label `cluster="gpu-demo"`, ~1k series). Dashboards defined once in
  `modules/dashboard-definitions`, deployed to in-cluster Grafana and Grafana Cloud.

## Gotchas learnt the hard way
- T4 (sm_75): no bf16 → `--dtype half`. Use vLLM default (CUDA 13) image; `-cu129` tag crashes (torchvision mismatch). Driver on AL2023 NVIDIA AMI is 580.x.
- Service named `vllm` injects `VLLM_PORT=tcp://…` → vLLM crash. Fixed with `enable_service_links = false`.
- Deployment `progress_deadline_seconds = 1800` (model download/compile is slow).
- Router image is ~5.5 GB → system nodes need 60 GB disks (20 GB → evictions).
- EKS module ignores `desired_size` after creation → `gpu_node_count` only matters at creation.
- `make down` can hang on an orphaned `amazon-vpc-cni` ENI blocking SG/VPC deletion — delete the available ENI tagged `eks:eni:owner=amazon-vpc-cni`.
- After a vLLM restart, Triton kernels JIT-compile under load → latency spikes. **Warm up before demos.**
- Router re-exports `vllm:num_requests_*` → engine panels filter `job="vllm"`.
- kube-prometheus-stack needs `serviceMonitorSelectorNilUsesHelmValues=false`.
- Grafana Cloud `glc_` tokens end in `=`/`==` — copy fully; check scope is write.
- `loadaware`/`kvaware` routing need LMCache — without it they silently fall back.
- CloudFront waits max 60 s for first byte → overloaded answers become 504.
- Kubernetes label values can't contain `:` (`qwen2.5:3b` → label `qwen2.5-3b`).
- **Default kubectl context on the owner's machine is another team's cluster** (`adhki`, eu-west-2).
  Never run kubectl against it; use a separate kubeconfig (`aws eks update-kubeconfig ... --kubeconfig <file>`).
- Destroy needs the app repo cloned too (workload reads `k6/black_friday.js` via `file()`).
- Spot T4s in eu-west-1 get reclaimed (2× in 2 h on 2026-10-19); replacement vLLM pod needs ~10-15 min.
- Grafana Cloud dashboards are Terraform-managed: "Save" in the UI is overwritten on the next apply.
- App → vLLM timeout is 120 s (`AsyncOpenAI(timeout=120)`); median = p90 = 2m0s in k6 means that timeout.

## Results so far (details in notes/)
- Chat sessions, 2 GPUs: prefixaware vs roundrobin → TTFT p50 0.2 s vs 14 s, cache hits ~90 % vs ~45 % — once working set > one GPU's KV cache.
- RAG with a shared system prompt: prefixaware sends ALL traffic to one GPU (other idle) → SLO broke at ~5.7 req/s vs ~10.8 with roundrobin.
- Fixed 30 k6 questions: prefix cache ~97 % → looked like ~11 req/s capacity. Randomised questions (default now): ~4.6 req/s real capacity, 26 % errors, congestion collapse (goodput → 0.55 req/s) past the wall.
- GPU util reads 100 % from ~1 req/s — useless for capacity. T4s hit 70 W power cap.
- Per-T4 ceiling (RAG, varied prompts): ~2.3 req/s. The wall is `max_num_seqs` 128/GPU (KV only 63 %).
- Admission control (`rag_max_in_flight = 128`): failed 24 % → 0 %, TTFT p95 ~3 min → 1.7 s, +13 % answered
  (2026-10-19, reproduced twice). Set 0 to show the collapse.

## Ideas not yet built
Autoscaling on queue depth/TTFT,
k6 results to Grafana Cloud k6 (`-o cloud`), WAF rate limit on CloudFront,
custom domain for the shop URL, LMCache for kvaware/loadaware routing.
