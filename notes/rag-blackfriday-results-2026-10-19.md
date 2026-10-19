# RAG "Black Friday" results — 2026-10-19 (admission control)

Same setup as 2026-10-18: RAG shop app -> vllm-router -> 2× vLLM (Qwen2.5-3B
fp16) on Tesla T4 Spot (g4dn.2xlarge / g4dn.xlarge — Spot gave whatever it had).
Load: k6 `black_friday.js`, PROFILE=blackfriday, random questions,
1 -> 16 req/s over 14 min. SLO: p95 time-to-first-word < 2 s, errors < 5 %.
Times are local (UTC+1).

| Run | Start | Setup                               | k6     | Failed  | Answered | TTFT p95 | Rejected 429 |
|-----|-------|-------------------------------------|--------|---------|----------|----------|--------------|
| 1   | 13:43 | roundrobin, cold GPUs               | FAIL   | 24.5 %  | ~2,590   | ~3 min   | —            |
| 2   | 14:04 | **prefixaware**                     | FAIL   | **73.9 %** | ~940  | ~2 min   | —            |
| 3   | 14:21 | roundrobin, **lost a GPU to Spot**  | FAIL   | 61.9 %  | ~1,370   | ~2 min   | —            |
| 4   | 14:49 | roundrobin, warm                    | FAIL   | 24.2 %  | ~2,590   | ~3 min   | —            |
| 5   | 15:09 | roundrobin + **admission 128**      | **PASS** | **0 %** | **~2,910** | **1.68 s** | 3,297     |
| 6   | 15:41 | roundrobin + admission 128          | PASS   | 0 %     | ~2,900   | 1.70 s   | 3,307        |
| 7   | 16:00 | no admission, **top_k 15** (~3k-token prompts) | FAIL | **94.7 %** | ~190 | 63 s | — |

Runs 1/4 and 5/6 reproduce each other almost exactly.

## The ceiling (run 1, minute by minute, both GPUs)
| Time  | Done/s | Running | Waiting | KV  | TTFT p95 | Latency p50 |
|-------|--------|---------|---------|-----|----------|-------------|
| 13:45 | 1.5    | 16      | 0       | 5 % | 0.5 s    | 6 s         |
| 13:47 | 3.4    | 87      | 0       | 23 %| 0.7 s    | 18 s        |
| 13:48 | 3.0    | 170     | 0       | 43 %| 3.5 s    | 29 s        |
| 13:49 | 3.8    | **255** | **18**  | 63 %| 4 s      | 45 s        |
| 13:51 | **4.7**| 253     | 293     | 63 %| 53 s     | 78 s        |
| 13:54 | 4.4    | 253     | 740     | 64 %| 156 s    | 166 s       |
| 13:56 | **1.3**| 255     | 737     | 63 %| 156 s    | 171 s       |

- Ceiling ~4.6 completed req/s for 2 T4s (matches 2026-10-18 random questions).
- The wall is `--max-num-seqs 128` per GPU (running pins at 256), NOT memory:
  KV cache sat at 63 %.
- Past it: congestion collapse, goodput 4.7 -> 1.3 req/s while GPUs stay busy.
- Signals that agree: completed stops following sent; running hits 128/GPU;
  waiting > 0; TTFT p95 jumps. GPU util (100 % from 1 req/s) does not.

## Admission control (built today)
App counts requests in flight; at `MAX_LLM_IN_FLIGHT=128` (total, ~64/GPU) a
new one waits up to `ADMISSION_WAIT_S=0.5`, then gets 429 "busy" + Retry-After.
Limit chosen from run 1: TTFT p95 0.7 s at ~90 running, 3.5 s at ~170.
- vLLM never queues (pending = 0 the whole run): the queue moved to the front door.
- More answers (+13 %), all fast; the rest get an instant honest "no".
- Whole-answer p95 still ~41 s: 128 answers written at once -> each writes
  slowly. Lower limit = faster writing, more 429s.
- Toggle for the talk: `rag_max_in_flight = 0` (collapse) vs `128` (healthy).

## Timeouts along the path (why runs 2-4 have median = p90 = 2m0s)
| Layer                     | Limit | On hit                      |
|---------------------------|-------|-----------------------------|
| CloudFront (public URL)   | 60 s to first byte | 504            |
| ALB                       | 180 s idle | —                      |
| App -> vLLM (AsyncOpenAI) | 120 s read | 502 "Model stream failed" |
| k6 -> app                 | 180 s | counted failed              |
| vLLM                      | none  | queues forever              |
k6 calls the app in-cluster, so CloudFront's 60 s doesn't apply to tests —
but real shoppers on the public URL fail at 60 s.

## Spot
Two T4 reclaims in ~2 h: 14:22:59 ("no Spot capacity available") and ~14:38.
EKS replaced each node in ~2 min; new vLLM pod ready ~10-15 min later (image
pull + model + compile). Run 3 shows the cost: 62 % failed.
-> Talk day must be ON_DEMAND.

## Run 7: breaking it completely (top_k 15, no admission control)
- Wall = **memory** this time: KV cache 98 % with only ~64 running per GPU
  (vs 128 running at 63 % KV with top_k 5). Longer prompts -> half the concurrency.
- 16:07 first preemptions. 16:07:30 prompt throughput -> 0; running drained to 0,
  KV -> 0 %, while ~300 per GPU sat waiting (`reason="capacity"`). **0 completed
  req/s for 8 minutes.** No crash, no restarts, no errors in logs.
- Recovered by itself once k6 stopped and abandoned requests were dropped.
- Root cause not found: looks like a vLLM v0.30 scheduler stall after preemption
  (idle engine + free KV + full queue), not plain overload. Worth investigating
  before relying on it in a live demo.

## Talk points
1. "Completed stops following sent" IS the ceiling. Capacity row shows it.
2. Losing a GPU to Spot (62 %) ≈ choosing prefixaware for RAG (74 %): both
   leave half the hardware idle.
3. A timeout isn't a strategy: when it fires the GPU time is spent and the
   shopper is gone. Saying "busy" early: 24 % -> 0 % failed, minutes -> <2 s.
