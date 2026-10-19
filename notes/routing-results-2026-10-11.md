# Routing strategy results — 2026-10-11

Setup: 2× g4dn.xlarge (Tesla T4, Spot), vLLM v0.30.0, Qwen2.5-3B-Instruct fp16,
KV cache 169,856 tokens per GPU, vllm-router (production-stack v0.1.13).
Load: k6 `llm-sessions.js`, ramping-arrival-rate 2 → 6 req/s, 64 output tokens.
Metrics: Prometheus, 2-minute window at the end of each 5.5-minute run.

## Run A — working set FITS one GPU (40–160 users × ~870-token history, ≤139k tokens)

| Strategy   | Prefix-cache hit rate | TTFT p50        |
|------------|-----------------------|-----------------|
| roundrobin | 83–90 %               | 0.15–0.18 s     |

Routing doesn't matter here: every GPU can cache every user's history.

## Run B — working set EXCEEDS one GPU (120 users × ~2.9k-token prompts ≈ 300k+ tokens)

| Metric (per GPU)              | roundrobin      | prefixaware     |
|-------------------------------|-----------------|-----------------|
| Prefix-cache hit rate         | 52 % / 55 %     | **93 % / 98 %** |
| TTFT p50                      | 23.2 s / 7.9 s  | **0.39 s / 0.18 s** |
| TTFT p99 (both GPUs)          | 46.4 s          | **5.0 s**       |
| Completed req/s               | 1.08 / 0.80     | **2.47 / 1.82** |
| Max waiting requests (2 min)  | 76 / 60         | **3 / 0**       |
| GPU utilisation (DCGM)        | 100 % / 100 %   | 100 % / 100 %   |

## Talk points

1. **Same GPUs, same load, ~20–60× better TTFT** — only the routing changed.
2. **GPU utilisation is 100 % in both runs.** It cannot tell a healthy cluster
   from a drowning one. Prefix-cache hit rate, queue depth and TTFT can.
3. **Routing only matters once the working set > one GPU's KV cache.** Below
   that (Run A) round-robin is fine. Size it: users × history tokens vs
   `GPU KV cache size` from the vLLM startup log.
4. **Prefix-aware trades balance for locality**: 2.47 vs 1.82 req/s per GPU.
   That's what `loadaware` (cache match minus a load penalty) addresses —
   but in vllm-router it needs an LMCache controller; not tested here.

## Rehearsal 2 — 2026-10-18 (fresh cluster, same settings, 2.5 min into each run)

| Metric (per GPU)       | roundrobin (14:28 UTC) | prefixaware (15:03 UTC) |
|------------------------|------------------------|-------------------------|
| Prefix-cache hit rate  | 49 % / 44 %            | **89 % / 88 %**         |
| TTFT p50               | 14.6 s / 13.0 s        | **0.21 s / 0.24 s**     |
| Waiting requests       | 10 / 5                 | **0 / 0**               |
| Completed req/s        | 0.62 / 0.36            | **1.36 / 1.64**         |
| GPU utilisation        | 100 % / 100 %          | 100 % / 100 %           |
| Failed requests        | 0 %                    | 0 %                     |

Reproduced on a fresh cluster: same story, same magnitude.
