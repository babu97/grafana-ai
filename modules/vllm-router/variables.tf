variable "namespace" {
  description = "Namespace of the router AND the vLLM pods it discovers."
  type        = string
}

variable "name" {
  description = "Also the Service name, which becomes the Prometheus `job` label. Must match /^vllm-router-/ for the router dashboard's Site variable."
  type        = string
  default     = "vllm-router-demo"
}

variable "image" {
  description = "vLLM production-stack router."
  type        = string
  default     = "lmcache/lmstack-router:v0.1.13"
}

variable "engine_label_selector" {
  description = "Kubernetes label selector for the vLLM engine pods to balance across."
  type        = string
}

variable "engine_port" {
  type    = number
  default = 8000
}

variable "routing_logic" {
  description = <<-EOT
    How the router picks a backend for each request:
      roundrobin  — take turns. Simple, even spread, ignores what's cached where.
      session     — same session id (the session_key header) -> same backend.
      prefixaware — send to the backend that already served the longest
                    matching prompt prefix, so its KV prefix cache is reused.
    Not offered here: kvaware and loadaware. Both ask an LMCache controller
    which backend holds which KV blocks; without LMCache (not deployed) they
    silently fall back to session-hash routing.
  EOT
  type        = string
  default     = "roundrobin"

  validation {
    condition     = contains(["roundrobin", "session", "prefixaware"], var.routing_logic)
    error_message = "routing_logic must be roundrobin, session or prefixaware (kvaware/loadaware need LMCache, not deployed here)."
  }
}

variable "session_key" {
  description = "HTTP header carrying the session id for routing_logic = session. k6 sends it."
  type        = string
  default     = "x-user-id"
}
