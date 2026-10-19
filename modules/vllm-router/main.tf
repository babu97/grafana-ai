locals {
  labels = { "app.kubernetes.io/name" = var.name }
  port   = 8001
}

# -----------------------------------------------------------------------------
# RBAC — the router finds vLLM pods by watching the Kubernetes API, so it needs
# its own identity (ServiceAccount) with permission to read pods in this
# namespace (Role) and the link between the two (RoleBinding).
# "patch" is used by the router's sleep-mode feature to label pods.
# -----------------------------------------------------------------------------
resource "kubernetes_service_account_v1" "router" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
}

resource "kubernetes_role_v1" "router" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "router" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.router.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.router.metadata[0].name
    namespace = var.namespace
  }
}

# -----------------------------------------------------------------------------
# The router: an OpenAI-compatible proxy in front of all vLLM pods. Clients
# talk to it exactly like they'd talk to vLLM; it picks a backend per request
# and keeps per-backend stats (QPS, latency, prefix-cache hit rate).
# -----------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "router" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
        # Changing the routing strategy changes this annotation, which forces
        # a fresh pod — so routing state (session/prefix tables) starts clean
        # for each strategy you demo.
        annotations = { "demo/routing-logic" = var.routing_logic }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.router.metadata[0].name
        node_selector        = { workload = "system" }

        container {
          name  = "router"
          image = var.image

          # Image ENTRYPOINT is `vllm-router`.
          args = [
            "--host", "0.0.0.0",
            "--port", tostring(local.port),
            "--service-discovery", "k8s",
            "--k8s-service-discovery-type", "pod-ip",
            "--k8s-namespace", var.namespace,
            "--k8s-label-selector", var.engine_label_selector,
            "--k8s-port", tostring(var.engine_port),
            "--routing-logic", var.routing_logic,
            "--session-key", var.session_key,
            # Refresh backend stats often so the dashboard reacts within seconds.
            "--engine-stats-interval", "5",
            "--request-stats-window", "30",
          ]

          port {
            name           = "http"
            container_port = local.port
          }

          resources {
            requests = { cpu = "500m", memory = "512Mi" }
            limits   = { cpu = "2", memory = "2Gi" }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.port
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = local.port
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# The Service name becomes the Prometheus `job` label (vllm-router-demo), which
# is what the router dashboard's $site variable selects on.
resource "kubernetes_service_v1" "router" {
  metadata {
    name      = var.name
    namespace = var.namespace
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

resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = var.name
      namespace = var.namespace
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
