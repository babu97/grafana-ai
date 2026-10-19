# cp terraform.tfvars.example terraform.tfvars
# Rehearsal loop: change a knob -> make apply-workload -> run k6 -> watch Grafana.

# --- Load-balancing demo -----------------------------------------------------
# Switch strategy, apply (~30s, router pod restarts), re-run the sessions test.
#   roundrobin | session | prefixaware   (loadaware/kvaware need LMCache)
routing_logic = "roundrobin"

# vllm_replicas = 2   # one per GPU node

# --- "Break the GPUs" knobs ----------------------------------------------------
# Make the KV cache wall arrive sooner (default 0.90).
# gpu_memory_utilization = 0.60

# Bigger prompts/outputs = more KV cache per request = earlier wall.
# k6_prompt_repeat = 40   # ~2k-token prompts
# k6_max_tokens    = 512

# Load shape (new requests per second).
# k6_stages = [
#   { target = 1,  duration = "1m" },
#   { target = 6,  duration = "2m" },
#   { target = 6,  duration = "2m" },
#   { target = 0,  duration = "30s" },
# ]

# --- Sessions workload (routing demo) ------------------------------------------
k6_sessions_users          = 120 # x ~2.5k tokens = ~300k: > one T4 KV cache (169k), < two
k6_sessions_history_repeat = 90  # ~27 tokens per repeat -> ~2.5k-token history per user

# --- Public access to the RAG shop app (AWS ALB) -------------------------------
# Only the shop app is exposed. Allowlist your IP for rehearsals;
# ["0.0.0.0/0"] opens it to the world (e.g. audience QR code on talk day).
rag_expose_publicly      = true
rag_public_allowed_cidrs = ["0.0.0.0/0"] # open to everyone

# --- RAG retrieval limits --------------------------------------------------------
# rag_top_k     = 5    # default products per question (k6 uses this too)
# rag_max_top_k = 15   # 1-20; each product adds ~160 prompt tokens

# --- Admission control (429 "busy" instead of a 2-minute wait) ---------------
# Set to 0 to turn it off and show the collapse again. Measured on 2 T4s:
# TTFT p95 0.7 s at ~90 requests running, 3.5 s at ~170 -> 128 holds the SLO.
rag_max_in_flight    = 128
rag_admission_wait_s = 0.5

# HTTPS via CloudFront (*.cloudfront.net). The ALB then only accepts CloudFront.
rag_https = true
