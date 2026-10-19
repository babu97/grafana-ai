locals {
  labels = { "app.kubernetes.io/name" = var.name }
  port   = 8000
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

# -----------------------------------------------------------------------------
# vLLM Deployment — one replica per T4.
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "vllm" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  # Startup includes pulling a ~10 GB image and downloading the model, so
  # don't let Terraform give up after the default 10 minutes.
  timeouts {
    create = "30m"
    update = "30m"
  }

  spec {
    # One replica per GPU node: each pod asks for nvidia.com/gpu = 1, so the
    # scheduler can't put two on the same T4.
    replicas = var.replicas

    # Kubernetes marks a Deployment "failed" if it isn't ready within this
    # window (default 600s). Must cover the startup probe's 20-minute budget.
    progress_deadline_seconds = 1800

    # Only one GPU: kill the old pod before starting a new one, otherwise the
    # new pod sits Pending forever waiting for a free GPU.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        # The vllm-router discovers engines by listing pods with
        # app.kubernetes.io/name=vllm, and reads the "model" label to group them.
        # Label values can't contain ":" — so "qwen2.5:3b" becomes "qwen2.5-3b" here.
        labels = merge(local.labels, { model = replace(var.served_model_name, ":", "-") })
      }

      spec {
        # Kubernetes injects <SERVICE>_PORT=tcp://ip:port env vars for every
        # Service in the namespace. Our Service is named "vllm", so the pod
        # gets VLLM_PORT=tcp://... — which vLLM reads as ITS OWN setting and
        # crashes. Service links are a legacy discovery mechanism (DNS
        # replaced them), so switch them off.
        enable_service_links = false

        # Land on the GPU node and tolerate its taint (both set in layer 2).
        node_selector = { workload = "gpu" }
        toleration {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name  = "vllm"
          image = var.image

          # The image's ENTRYPOINT is `vllm serve`; these are its arguments.
          args = concat([
            var.model,
            # First name is the main one (used in vLLM's metrics); the rest are aliases.
            "--served-model-name", var.served_model_name,
            ], var.served_model_aliases, [
            "--port", tostring(local.port),
            # T4 = compute capability 7.5: no bfloat16 support. vLLM refuses
            # bf16 on it, and Qwen's default dtype is bf16 — so force fp16.
            "--dtype", "half",
            "--gpu-memory-utilization", tostring(var.gpu_memory_utilization),
            "--max-model-len", tostring(var.max_model_len),
            "--max-num-seqs", tostring(var.max_num_seqs),
          ], var.extra_args)

          port {
            name           = "http"
            container_port = local.port
          }

          resources {
            # This is what the device plugin (layer 3) makes possible.
            limits = {
              "nvidia.com/gpu" = "1"
              memory           = "13Gi"
            }
            requests = {
              cpu    = "2"
              memory = "10Gi"
            }
          }

          volume_mount {
            name       = "hf-cache"
            mount_path = "/root/.cache/huggingface"
          }
          volume_mount {
            name       = "shm"
            mount_path = "/dev/shm"
          }

          # Model download + load + CUDA graph capture can take ~5-10 min on a
          # fresh node. startup_probe allows up to 20 min before restarting;
          # readiness then gates traffic.
          startup_probe {
            http_get {
              path = "/health"
              port = local.port
            }
            period_seconds    = 10
            failure_threshold = 120
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = local.port
            }
            period_seconds = 5
          }
        }

        # Model weights cached on the node's 100 GB disk. Survives pod restarts
        # (not node replacement), so a redeploy doesn't re-download.
        volume {
          name = "hf-cache"
          empty_dir {}
        }
        # PyTorch uses shared memory; the container default (64 MB) is too small.
        volume {
          name = "shm"
          empty_dir {
            medium     = "Memory"
            size_limit = "2Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "vllm" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels
    port {
      name        = "http"
      port        = local.port
      target_port = local.port
    }
  }
}

# -----------------------------------------------------------------------------
# ServiceMonitor — tells the Prometheus Operator to scrape vLLM's /metrics.
#
# ServiceMonitor is a Custom Resource, so there's no typed Terraform resource
# for it; kubernetes_manifest takes any Kubernetes object as an HCL map.
# Gotcha: kubernetes_manifest needs the CRD to already exist at PLAN time —
# one more reason this lives in a separate stack from layer 3.
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = var.name
      namespace = kubernetes_namespace_v1.this.metadata[0].name
      labels    = local.labels
    }
    spec = {
      selector = { matchLabels = local.labels }
      endpoints = [{
        port     = "http"
        path     = "/metrics"
        interval = "5s"
      }]
    }
  }
}
