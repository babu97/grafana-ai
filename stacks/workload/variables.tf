# The rehearsal knobs. Change in terraform.tfvars, `make apply-workload`, re-run k6.

variable "model" {
  type    = string
  default = "Qwen/Qwen2.5-3B-Instruct"
}

variable "vllm_image" {
  type    = string
  default = "vllm/vllm-openai:v0.30.0"
}

variable "gpu_memory_utilization" {
  description = "Lower = smaller KV cache = the wall arrives sooner."
  type        = number
  default     = 0.90
}

variable "max_num_seqs" {
  type    = number
  default = 128
}

variable "k6_stages" {
  type = list(object({
    target   = number
    duration = string
  }))
  default = [
    { target = 1, duration = "1m" },
    { target = 4, duration = "2m" },
    { target = 10, duration = "3m" },
    { target = 10, duration = "2m" },
    { target = 0, duration = "30s" },
  ]
}

variable "k6_max_tokens" {
  type    = number
  default = 256
}

variable "k6_prompt_repeat" {
  type    = number
  default = 20
}

# --- Load balancing ----------------------------------------------------------

variable "vllm_replicas" {
  description = "One per GPU node. Needs that many GPU nodes up."
  type        = number
  default     = 2
}

variable "routing_logic" {
  description = "roundrobin | session | prefixaware. Change + apply to switch strategy live."
  type        = string
  default     = "roundrobin"
}

variable "k6_sessions_stages" {
  type = list(object({
    target   = number
    duration = string
  }))
  default = [
    { target = 2, duration = "1m" },
    { target = 6, duration = "4m" },
    { target = 0, duration = "30s" },
  ]
}

variable "k6_sessions_users" {
  description = "Distinct chat users. More users = more distinct prefixes competing for cache."
  type        = number
  default     = 40
}

variable "k6_sessions_history_repeat" {
  description = "Conversation history length, ~27 tokens per repeat (measured: 30 ≈ 870-token prompts)."
  type        = number
  default     = 30
}

# --- RAG app (llm-load-testing-demo) -----------------------------------------

variable "rag_image_tag" {
  description = "Tag pushed by `make build-rag` (git short sha, or latest)."
  type        = string
  default     = "latest"
}

variable "rag_top_k" {
  description = "Default products retrieved per question (and what k6 sends). More = longer prompts."
  type        = number
  default     = 5
}

variable "rag_max_top_k" {
  description = "Most products a shopper may request (1-20). Enforced by the API and the page."
  type        = number
  default     = 15
}

variable "rag_k6_profile" {
  description = "smoke (1 question/min for 3 min) or blackfriday (ramp to 16 req/s over 14 min)."
  type        = string
  default     = "blackfriday"
}

variable "rag_expose_publicly" {
  description = "Create an internet-facing ALB for the shop app (only the shop app)."
  type        = bool
  default     = false
}

variable "rag_public_allowed_cidrs" {
  description = "Allowed client CIDRs for the ALB, e.g. [\"<your-ip>/32\"]."
  type        = list(string)
  default     = []
}

variable "rag_https" {
  description = "Put CloudFront (HTTPS, *.cloudfront.net cert) in front of the shop app; the ALB then only accepts CloudFront. Needs rag_expose_publicly = true."
  type        = bool
  default     = false
}
