variable "namespace" {
  type = string
}

variable "name" {
  type    = string
  default = "k6-llm-ramp"
}

variable "script" {
  description = "File in modules/k6-loadtest/scripts/ to run."
  type        = string
  default     = "llm-ramp.js"
}

variable "script_path" {
  description = "Full path to a k6 script elsewhere (e.g. the RAG demo repo). Overrides `script`."
  type        = string
  default     = null
}

variable "extra_env" {
  description = "Extra environment variables for the script."
  type        = map(string)
  default     = {}
}

variable "image" {
  type    = string
  default = "grafana/k6:2.3.0"
}

variable "target_base_url" {
  description = "OpenAI-compatible base URL to load: the router, or a vLLM Service directly."
  type        = string
}

variable "model" {
  description = "Served model name to put in each request."
  type        = string
}

variable "prometheus_url" {
  description = "Prometheus base URL; k6 pushes to <url>/api/v1/write."
  type        = string
}

# --- Load shape: tune these in rehearsal until the wall lands on cue ---------

variable "stages" {
  description = "ramping-arrival-rate stages: target = new requests per second."
  type = list(object({
    target   = number
    duration = string
  }))
  default = [
    { target = 1, duration = "1m" },  # warm-up: dashboard looks healthy
    { target = 4, duration = "2m" },  # climb: GPU util and KV cache rise
    { target = 10, duration = "3m" }, # push past the ceiling
    { target = 10, duration = "2m" }, # hold: queue + latency explode
    { target = 0, duration = "30s" },
  ]
}

variable "max_tokens" {
  description = "Output tokens per request."
  type        = number
  default     = 256
}

variable "prompt_repeat" {
  description = "Prompt filler repeats (~50 tokens each). 20 ≈ 1k-token prompt."
  type        = number
  default     = 20
}

variable "max_vus" {
  type    = number
  default = 400
}
