variable "namespace" {
  type    = string
  default = "llm"
}

variable "name" {
  type    = string
  default = "vllm"
}

variable "replicas" {
  description = "vLLM pods. Each takes a whole T4, so this must be <= number of GPU nodes."
  type        = number
  default     = 1
}

variable "image" {
  description = "Default build is CUDA 13 (needs NVIDIA driver >= 580; EKS AL2023 NVIDIA AMI ships 580.x). The -cu129 tag crashes on import (torchvision/torch mismatch) — avoid. v0.30.0 still compiles kernels for the T4 (sm_75)."
  type        = string
  default     = "vllm/vllm-openai:v0.30.0"
}

variable "model" {
  description = "Hugging Face model ID. Ungated, so no HF token needed. ~6 GB of weights in fp16."
  type        = string
  default     = "Qwen/Qwen2.5-3B-Instruct"
}

variable "served_model_name" {
  description = "Name clients put in the `model` field. Matches Ollama's tag, so the same app config works on a laptop (Ollama) and on EKS (vLLM)."
  type        = string
  default     = "qwen2.5:3b"
}

variable "served_model_aliases" {
  description = "Extra names vLLM also answers to (old clients keep working)."
  type        = list(string)
  default     = ["qwen-3b"]
}

# --- The "how fast does it break" knobs --------------------------------------

variable "gpu_memory_utilization" {
  description = <<-EOT
    Fraction of the T4's 15 GB vLLM may use. Weights (~6 GB) + activations come
    out first; whatever is left becomes KV cache. LOWER = smaller KV cache =
    the wall arrives at a lower request rate. 0.90 ≈ 6 GB KV, 0.60 ≈ 1.5 GB KV.
  EOT
  type        = number
  default     = 0.90
}

variable "max_model_len" {
  description = "Max tokens (prompt + output) per request."
  type        = number
  default     = 4096
}

variable "max_num_seqs" {
  description = "Max requests vLLM batches at once. Beyond this they queue (num_requests_waiting)."
  type        = number
  default     = 128
}

variable "extra_args" {
  description = "Any other `vllm serve` flags."
  type        = list(string)
  default     = []
}
