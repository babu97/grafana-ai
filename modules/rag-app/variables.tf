variable "namespace" {
  type    = string
  default = "rag"
}

variable "image" {
  description = "RAG app image (built by `make build-rag`), e.g. <ecr-repo>:latest."
  type        = string
}

variable "replicas" {
  description = "App pods. Each embeds questions on CPU; add one if app CPU becomes the bottleneck."
  type        = number
  default     = 1
}

variable "llm_base_url" {
  description = "OpenAI-compatible endpoint, incl. /v1 — the vllm-router."
  type        = string
}

variable "llm_model" {
  description = "Must match vLLM's --served-model-name (NOT the Ollama tag qwen2.5:3b)."
  type        = string
}

variable "top_k" {
  description = "Default products retrieved per question. More = longer prompts = more KV cache per request."
  type        = number
  default     = 5

  validation {
    condition     = var.top_k >= 1
    error_message = "top_k must be at least 1."
  }
}

variable "max_top_k" {
  description = <<-EOT
    Upper limit for top_k, enforced by the API and shown in the page.
    Each product adds ~160 prompt tokens (measured: top_k 5 = ~1,000 tokens).
    vLLM's max_model_len is 4,096 = prompt + up to max_tokens (400) of answer,
    so ~20 products is the ceiling before vLLM rejects the request.
  EOT
  type        = number
  default     = 15

  validation {
    condition     = var.max_top_k >= 1 && var.max_top_k <= 20
    error_message = "max_top_k must be 1-20: more products overflow the model's 4,096-token context."
  }
}

variable "max_tokens" {
  type    = number
  default = 400
}

variable "postgres_image" {
  type    = string
  default = "pgvector/pgvector:pg16"
}

# --- Public access (AWS ALB via the AWS Load Balancer Controller) -------------

variable "expose_publicly" {
  description = "Create an internet-facing ALB for the shop app. Off by default."
  type        = bool
  default     = false
}

variable "public_allowed_cidrs" {
  description = "Who may reach the ALB. Your IP (x.x.x.x/32) for rehearsals; 0.0.0.0/0 opens it to everyone."
  type        = list(string)
  default     = []

}

variable "cloudfront_origin" {
  description = <<-EOT
    When set, the ALB accepts ONLY CloudFront: its security group allows just
    CloudFront's AWS-managed prefix list, and the listener requires the secret
    X-Origin-Verify header that CloudFront adds. public_allowed_cidrs is then
    ignored here (the allowlist moves to CloudFront). null = direct ALB access.
  EOT
  type = object({
    prefix_list_id = string
    verify_header  = string
  })
  default   = null
  sensitive = true
}
