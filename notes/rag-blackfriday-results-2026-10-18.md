# RAG "Black Friday" results — 2026-10-18

App: llm-load-testing-demo (FastAPI + fastembed + pgvector hybrid search) on EKS,
LLM calls via vllm-router to 2× vLLM (Qwen2.5-3B fp16) on Tesla T4 (Spot).
Load: k6 `black_friday.js`, PROFILE=blackfriday, ramping-arrival-rate
1 → 4 → 8 → 12 → 16 req/s over 14 min, top_k=5 (~1,000-token prompts).
SLO (k6 thresholds): p95 time-to-first-word < 2 s, errors < 5 %.

| Same app, same 2 GPUs       | prefixaware (17:32)        | roundrobin (18:18)         |
|-----------------------------|----------------------------|----------------------------|
| GPUs doing work             | **1 of 2** (GPU 2 idle)    | **2 of 2**, ~50/50         |
| SLO broke at                | **~5.7 req/s**             | **~10.8 req/s**            |
| Peak queue                  | 233 on one GPU             | ~100 / ~120                |
| Requests served             | 3,964                      | **5,867**                  |
| Failed requests             | **5.24 %** (SLO fail)      | **0 %**                    |
| TTFT median                 | 25.4 s                     | **0.44 s**                 |
| TTFT p95                    | 1 m 59 s                   | 17.8 s (SLO fail at peak)  |
| Answer time median          | 47.6 s                     | **16.9 s**                 |
| k6 dropped iterations       | 1,683                      | 432                        |

Per-GPU ceiling for this workload: ~5.5–5.8 completed req/s per T4.
KV cache only ~22 % full at the wall -> the limit is COMPUTE, not memory.

## Why prefixaware failed here
Every RAG prompt starts with the same system prompt. Prefix-aware routing
sends each request to the backend with the longest cached prefix match —
always the same one. All traffic landed on one GPU; the other stayed idle.

## Talk points
1. Same strategy, opposite results: prefixaware made the chat-sessions workload
   ~60× faster (routing-results-2026-10-11.md) but halved RAG capacity.
2. Routing must match the traffic: long per-user histories -> prefix/session;
   shared system prompt + varied retrieved context -> roundrobin (or load-aware).
3. GPU util read 100 % on both GPUs from just 1 req/s. Useless as a capacity signal.
4. Two T4s really do give ~2× — but only if the router lets them.

## Fixed vs randomised questions — 2026-10-18 22:43 / 22:58 UTC (roundrobin, 2× T4)

k6 `black_friday.js`: QUESTIONS_MODE=fixed (30 questions) vs random
(product × need × budget × recipient: 4,606 distinct in 5,000 draws).

| Same app, same GPUs, same ramp | fixed 30 questions | randomised questions |
|--------------------------------|--------------------|----------------------|
| vLLM prefix-cache hit rate     | 97–100 %           | 24–40 %              |
| SLO (p95 < 2 s) broke at       | ~11 req/s (min 12) | ~7–8 req/s (min 7.5) |
| Max completed throughput       | ~11 req/s          | **~4.6 req/s**       |
| Requests served                | 5,867              | 3,458                |
| Failed requests                | 0 %                | **25.9 %** (895)     |
| First word, median             | 0.47 s             | **12.3 s**           |
| First word, p95                | 17.7 s             | **1 m 47 s**         |
| Answer time, median            | —                  | 1 m 9 s              |
| k6 dropped iterations          | 432                | 2,210                |
| Peak queue per GPU             | ~100               | ~400                 |

At the end of the random run, completions COLLAPSED from 4.6 to 0.55 req/s
while errors rose to ~3.9/s: requests hitting the app's 120 s LLM timeout,
GPUs busy on work nobody would receive (congestion collapse / goodput -> 0).

Also seen: T4s at their 70 W power cap (SM clock 1,335 MHz) from ~2 req/s/GPU;
cold Triton kernel JIT after a vLLM restart caused p95 spikes (1.7–4.3 s at
1–4 req/s) until warm — warm up before going on stage.

## Talk points
1. Repetitive load-test data lies: 30 fixed questions made the GPUs look
   2.4× more capable (prefix cache served ~all of every prompt).
2. Past the wall it doesn't degrade gracefully — it collapses: queues grow,
   timeouts fire, goodput drops toward zero while GPU util says 100 %.
3. Fixes to discuss: admission control / max queue (fail fast, e.g. 429),
   shorter timeouts, autoscaling on queue depth or TTFT — not GPU util.
