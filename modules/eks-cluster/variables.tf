variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Must be in STANDARD support — extended support bills $0.60/hr instead of $0.10/hr. Check: aws eks describe-cluster-versions"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and the nodes."
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "Who may reach the Kubernetes API over the internet. Tighten to your IP (x.x.x.x/32) if you like."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# --- System (CPU) node group: CoreDNS, Prometheus, Grafana, k6 ---------------

variable "system_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "system_disk_size_gb" {
  description = "Root volume for system nodes (container images: router ~5.5 GB, Prometheus, Grafana, k6)."
  type        = number
  default     = 60
}

# --- GPU node group: vLLM + DCGM exporter only ------------------------------

variable "gpu_instance_types" {
  description = "Keep to the g4dn family to stay on Tesla T4s."
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

variable "gpu_capacity_type" {
  description = "SPOT for cheap rehearsals, ON_DEMAND for talk day (no interruptions)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "gpu_node_count" {
  description = <<-EOT
    GPU nodes at CREATION time. One vLLM replica per node (1 T4 each); 2 lets
    the router load-balance. NOTE: the EKS module ignores desired_size after
    creation (so autoscalers can own it) — changing this on a live cluster does
    nothing. Scale a live cluster with:
      aws eks update-nodegroup-config --cluster-name gpu-demo --nodegroup-name <gpu-...> \
        --scaling-config minSize=0,maxSize=2,desiredSize=N
  EOT
  type        = number
  default     = 2
}

variable "gpu_disk_size_gb" {
  description = "Root volume. The vLLM image (~10 GB) and model weights are cached here."
  type        = number
  default     = 100
}

variable "tags" {
  type    = map(string)
  default = {}
}
