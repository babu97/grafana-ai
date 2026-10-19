# -----------------------------------------------------------------------------
# "Breaking a T4" dashboard, built as HCL data and turned into JSON.
#
# Read top to bottom it tells the story of the talk:
#   GPU      — the hardware is busy (and VRAM looks "full" from the start!)
#   vLLM     — KV cache fills, requests start queueing, preemptions begin
#   Latency  — what users feel: TTFT and queue time explode
#   k6       — the load we're applying, and when k6 itself can't keep up
#
# Each row is a list of panels; the for-expressions below lay them out on
# Grafana's 24-column grid so you only describe WHAT to show, not WHERE.
# -----------------------------------------------------------------------------
locals {
  ds = { type = "prometheus", uid = var.datasource_uid }

  # The router re-exports vllm:num_requests_* under the SAME names as the
  # engines (with a `server` label). Engine-only panels filter on job="vllm"
  # (the vLLM Service name) so router copies aren't double-counted.
  # Panels below show one line per engine pod, so the 2 GPUs are visible.

  # "Have we hit the ceiling?" in one expression: 0 = headroom, 1 = requests
  # queueing (no free slots), 2-3 = shoppers waiting longer than the SLO.
  # Each side falls back to 0 when idle, when there is no data to compare.
  ceiling_state = join(" + ", [
    "((sum(vllm:num_requests_waiting{job=\"vllm\"}) > bool 0) or vector(0))",
    "2 * ((histogram_quantile(0.95, sum by (le) (rate(rag_ttft_seconds_bucket[1m]))) > bool ${var.ttft_slo_seconds}) or vector(0))",
  ])

  rows = [
    {
      # The punchline in four panels. The ceiling is where "completed" stops
      # following "sent"; past it, "good answers" falls (congestion collapse).
      title = "Capacity: have we hit the ceiling?"
      panels = [
        {
          title = "Have we hit the ceiling?", type = "stat", unit = "none"
          targets = [
            { expr = local.ceiling_state, legend = "state" },
          ]
          thresholds = [
            { color = "green", value = null },
            { color = "orange", value = 1 },
            { color = "red", value = 2 },
          ]
          mappings = [
            { type = "value", options = { "0" = { text = "OK: headroom" } } },
            { type = "value", options = { "1" = { text = "AT CEILING: queueing" } } },
            { type = "range", options = { from = 2, to = 3, result = { text = "OVER: SLO broken" } } },
          ]
          options = {
            colorMode     = "background"
            graphMode     = "none"
            justifyMode   = "center"
            textMode      = "value"
            reduceOptions = { calcs = ["lastNotNull"], fields = "", values = false }
          }
        },
        {
          title = "Sent vs completed vs good answers", unit = "reqps"
          targets = [
            { expr = "sum(rate(k6_http_reqs_total[1m]))", legend = "sent (k6)" },
            { expr = "sum(rate(vllm:request_success_total{job=\"vllm\"}[1m]))", legend = "completed (GPUs)" },
            { expr = "sum(rate(rag_ttft_seconds_bucket{le=\"${format("%.1f", var.ttft_slo_seconds)}\"}[1m]))", legend = "good: first word < ${var.ttft_slo_seconds} s" },
            { expr = "sum(rate(rag_rejected_total[1m]))", legend = "rejected (429 busy)" },
          ]
        },
        {
          title = "Request slots: running vs capacity", unit = "short"
          targets = [
            { expr = "count(vllm:num_requests_running{job=\"vllm\"}) * ${var.max_num_seqs}", legend = "capacity (${var.max_num_seqs} per GPU)" },
            { expr = "sum(vllm:num_requests_running{job=\"vllm\"})", legend = "running" },
            { expr = "sum(vllm:num_requests_waiting{job=\"vllm\"})", legend = "waiting (no free slot)" },
          ]
        },
        {
          title = "Shopper time to first word vs SLO", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.95, sum by (le) (rate(rag_ttft_seconds_bucket[1m])))", legend = "p95" },
          ]
          thresholds = [
            { color = "green", value = null },
            { color = "red", value = var.ttft_slo_seconds },
          ]
          threshold_style = "line+area"
        },
      ]
    },
    {
      title = "GPU (DCGM exporter)"
      panels = [
        {
          title = "GPU utilisation", unit = "percent", max = 100
          targets = [
            { expr = "DCGM_FI_DEV_GPU_UTIL", legend = "{{Hostname}} any kernel running" },
            { expr = "DCGM_FI_PROF_PIPE_TENSOR_ACTIVE * 100", legend = "{{Hostname}} tensor cores busy" },
          ]
        },
        {
          # vLLM pre-allocates ~90% of VRAM at startup for weights + KV cache,
          # so this is flat-and-high before any load. That's a talk point:
          # VRAM usage tells you nothing about saturation — KV cache usage does.
          title = "VRAM used", unit = "percent", max = 100
          targets = [
            { expr = "DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100", legend = "{{Hostname}} framebuffer used" },
          ]
        },
        {
          title = "Power", unit = "watt"
          targets = [
            { expr = "DCGM_FI_DEV_POWER_USAGE", legend = "{{Hostname}} power (T4 cap 70 W)" },
          ]
        },
        {
          title = "Temperature", unit = "celsius"
          targets = [
            { expr = "DCGM_FI_DEV_GPU_TEMP", legend = "{{Hostname}} GPU" },
            { expr = "DCGM_FI_DEV_MEMORY_TEMP", legend = "{{Hostname}} memory" },
          ]
        },
      ]
    },
    {
      title = "vLLM engine"
      panels = [
        {
          title = "KV cache usage", unit = "percent", max = 100
          targets = [
            { expr = "vllm:kv_cache_usage_perc{job=\"vllm\"} * 100", legend = "{{pod}} KV cache used" },
          ]
        },
        {
          title = "Requests: running vs waiting", unit = "short"
          targets = [
            { expr = "vllm:num_requests_running{job=\"vllm\"}", legend = "{{pod}} running (batched on GPU)" },
            { expr = "vllm:num_requests_waiting{job=\"vllm\"}", legend = "{{pod}} waiting (queued)" },
          ]
        },
        {
          title = "Preemptions / s", unit = "short"
          targets = [
            { expr = "rate(vllm:num_preemptions_total[1m])", legend = "{{pod}} requests evicted from KV cache" },
          ]
        },
        {
          title = "Throughput", unit = "short"
          targets = [
            { expr = "rate(vllm:generation_tokens_total[1m])", legend = "{{pod}} output tokens/s" },
            { expr = "rate(vllm:request_success_total[1m])", legend = "{{pod}} completed requests/s" },
          ]
        },
      ]
    },
    {
      title = "Latency (what users feel)"
      panels = [
        {
          title = "Time to first token", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.50, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[1m])))", legend = "p50" },
            { expr = "histogram_quantile(0.99, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[1m])))", legend = "p99" },
          ]
        },
        {
          title = "Queue time", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.99, sum by (le) (rate(vllm:request_queue_time_seconds_bucket[1m])))", legend = "p99 time waiting for a slot" },
          ]
        },
        {
          title = "End-to-end request latency", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.50, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[1m])))", legend = "p50" },
            { expr = "histogram_quantile(0.99, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[1m])))", legend = "p99" },
          ]
        },
      ]
    },
    {
      # The shopper's view vs the GPU's view: app TTFT includes retrieval and
      # router time; the gap to vLLM's own TTFT shows where time is spent.
      title = "RAG shopping assistant (end-to-end)"
      panels = [
        {
          title = "Shopper time to first word", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.50, sum by (le) (rate(rag_ttft_seconds_bucket[1m])))", legend = "app p50" },
            { expr = "histogram_quantile(0.95, sum by (le) (rate(rag_ttft_seconds_bucket[1m])))", legend = "app p95 (SLO: < 2 s)" },
            { expr = "histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket{job=\"vllm\"}[1m])))", legend = "vLLM only p95" },
          ]
        },
        {
          title = "Retrieval (embed + pgvector search)", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.50, sum by (le) (rate(rag_retrieval_seconds_bucket[1m])))", legend = "p50" },
            { expr = "histogram_quantile(0.95, sum by (le) (rate(rag_retrieval_seconds_bucket[1m])))", legend = "p95" },
          ]
        },
        {
          title = "Requests in flight (app)", unit = "short"
          targets = [
            { expr = "sum(rag_requests_in_flight)", legend = "in flight" },
            { expr = "max(rag_admission_limit) > 0", legend = "admission limit" },
          ]
        },
        {
          title = "Errors / s by stage", unit = "short"
          targets = [
            { expr = "sum by (stage) (rate(rag_errors_total[1m]))", legend = "{{stage}}" },
          ]
        },
      ]
    },
    {
      # The punchline: request SIZE stays flat while time-to-first-word
      # explodes — requests aren't getting more expensive, they're queueing.
      title = "Tokens per request (shopping assistant)"
      panels = [
        {
          title = "Tokens per request (average)", unit = "short"
          targets = [
            { expr = "sum(rate(rag_prompt_tokens_sum[1m])) / sum(rate(rag_prompt_tokens_count[1m]))", legend = "prompt (in)" },
            { expr = "sum(rate(rag_output_tokens_sum[1m])) / sum(rate(rag_output_tokens_count[1m]))", legend = "answer (out)" },
          ]
        },
        {
          title = "Token throughput (all shoppers)", unit = "short"
          targets = [
            { expr = "sum(rate(rag_prompt_tokens_sum[1m]))", legend = "prompt tokens/s read" },
            { expr = "sum(rate(rag_output_tokens_sum[1m]))", legend = "answer tokens/s written" },
          ]
        },
        {
          title = "Writing speed: time per answer token", unit = "s"
          targets = [
            { expr = "histogram_quantile(0.50, sum by (le) (rate(vllm:inter_token_latency_seconds_bucket{job=\"vllm\"}[1m])))", legend = "p50" },
            { expr = "histogram_quantile(0.95, sum by (le) (rate(vllm:inter_token_latency_seconds_bucket{job=\"vllm\"}[1m])))", legend = "p95" },
          ]
        },
      ]
    },
    {
      title = "k6 load"
      panels = [
        {
          title = "Request rate", unit = "reqps"
          targets = [
            { expr = "sum(rate(k6_http_reqs_total[1m]))", legend = "sent" },
            { expr = "sum(rate(k6_dropped_iterations_total[1m]))", legend = "dropped (k6 out of VUs)" },
          ]
        },
        {
          title = "k6 request duration", unit = "s"
          targets = [
            { expr = "max(k6_http_req_duration_p50)", legend = "p50" },
            { expr = "max(k6_http_req_duration_p99)", legend = "p99" },
          ]
        },
        {
          title = "Failed requests", unit = "percent", max = 100
          targets = [
            { expr = "max(k6_http_req_failed_rate) * 100", legend = "failed" },
          ]
        },
      ]
    },
  ]

  row_height   = 8
  row_stride   = local.row_height + 1 # +1 for the row header
  ref_ids      = ["A", "B", "C", "D", "E"]
  grid_columns = 24

  panels = flatten([
    for ri, row in local.rows : concat(
      # The collapsible row header.
      [{
        id        = ri * 100 + 1
        type      = "row"
        title     = row.title
        collapsed = false
        panels    = []
        gridPos   = { x = 0, y = ri * local.row_stride, w = local.grid_columns, h = 1 }
      }],
      # The panels in that row, equal width.
      [for pi, p in row.panels : {
        id         = ri * 100 + pi + 2
        type       = try(p.type, "timeseries")
        title      = p.title
        datasource = local.ds
        gridPos = {
          x = pi * floor(local.grid_columns / length(row.panels))
          y = ri * local.row_stride + 1
          w = floor(local.grid_columns / length(row.panels))
          h = local.row_height
        }
        fieldConfig = {
          # merge() + a filtered map adds "max" only for panels that set it;
          # likewise thresholds/mappings, and a threshold line on the graph.
          defaults = merge(
            { unit = p.unit, min = 0 },
            { for k, v in { max = try(p.max, null) } : k => v if v != null },
            try({ thresholds = { mode = "absolute", steps = p.thresholds }, color = { mode = "thresholds" } }, {}),
            try({ mappings = p.mappings }, {}),
            try({ custom = { thresholdsStyle = { mode = p.threshold_style } } }, {}),
          )
          overrides = []
        }
        options = try(p.options, {
          legend  = { displayMode = "list", placement = "bottom", showLegend = true }
          tooltip = { mode = "multi", sort = "desc" }
        })
        targets = [for ti, t in p.targets : {
          refId        = local.ref_ids[ti]
          datasource   = local.ds
          expr         = t.expr
          legendFormat = t.legend
        }]
      }],
    )
  ])

  dashboard = {
    uid           = "gpu-breaking-point"
    title         = "Breaking a T4: vLLM under load"
    tags          = ["gpu", "vllm", "k6"]
    timezone      = "browser"
    schemaVersion = 39
    refresh       = "5s"
    time          = { from = "now-15m", to = "now" }
    panels        = local.panels
  }
}
