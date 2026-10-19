# -----------------------------------------------------------------------------
# The Black Friday shopping assistant (llm-load-testing-demo) on EKS:
#
#   shopper/k6 ──► rag-app ──┬─► postgres (pgvector: vector + keyword search)
#                            └─► vllm-router ──► vLLM on T4 #1 / #2
#
# Order matters and Terraform enforces it with depends_on:
#   postgres ready -> ingest Job loads 283 products -> app starts.
# Postgres data is an emptyDir: gone with the pod, reloaded by the ingest Job
# on every rebuild (seconds). Fine for a demo; use RDS/a PVC for real data.
# -----------------------------------------------------------------------------

locals {
  pg_labels  = { "app.kubernetes.io/name" = "postgres" }
  app_labels = { "app.kubernetes.io/name" = "rag-app" }

  database_url = "postgresql://shop:${random_password.postgres.result}@postgres.${var.namespace}.svc:5432/shop"
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

# --- Credentials -------------------------------------------------------------
# Generated, stored in Terraform state and a Kubernetes Secret — never in git.
resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "rag-db"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    POSTGRES_PASSWORD = random_password.postgres.result
    DATABASE_URL      = local.database_url
  }
}

# --- Postgres + pgvector -----------------------------------------------------
resource "kubernetes_deployment_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.pg_labels
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = local.pg_labels
    }

    template {
      metadata {
        labels = local.pg_labels
      }
      spec {
        node_selector = { workload = "system" }

        container {
          name  = "postgres"
          image = var.postgres_image

          env {
            name  = "POSTGRES_USER"
            value = "shop"
          }
          env {
            name  = "POSTGRES_DB"
            value = "shop"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.db.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          # Postgres refuses to init into a non-empty dir; mount points can
          # contain lost+found, so use a subdirectory.
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          port {
            container_port = 5432
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "shop", "-d", "shop"]
            }
            period_seconds = 5
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  spec {
    selector = local.pg_labels
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# --- Ingest: embed the catalogue and load it into Postgres -------------------
# Runs the app image's own ingest script. Terraform waits for it to finish
# before starting the app, so the app never serves an empty catalogue.
resource "kubernetes_job_v1" "ingest" {
  metadata {
    name      = "ingest-products"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    backoff_limit = 3
    template {
      metadata {}
      spec {
        restart_policy = "Never"
        node_selector  = { workload = "system" }

        container {
          name    = "ingest"
          image   = var.image
          command = ["python", "app/ingest.py"]

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.db.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
          env {
            name  = "PRODUCTS_FILE"
            value = "data/products.jsonl"
          }
        }
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "10m"
  }

  depends_on = [kubernetes_deployment_v1.postgres, kubernetes_service_v1.postgres]
}

# --- The app -----------------------------------------------------------------
resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = "rag-app"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.app_labels
  }

  spec {
    replicas = var.replicas
    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }
      spec {
        node_selector = { workload = "system" }

        container {
          name  = "app"
          image = var.image
          # The tag is often "latest": always check the registry for a newer one.
          image_pull_policy = "Always"

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.db.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
          env {
            name  = "LLM_BASE_URL"
            value = var.llm_base_url
          }
          env {
            name  = "LLM_MODEL"
            value = var.llm_model
          }
          env {
            name  = "TOP_K"
            value = tostring(var.top_k)
          }
          env {
            name  = "MAX_TOKENS"
            value = tostring(var.max_tokens)
          }
          env {
            name  = "MAX_TOP_K"
            value = tostring(var.max_top_k)
          }
          env {
            name  = "MAX_LLM_IN_FLIGHT"
            value = tostring(var.max_llm_in_flight)
          }
          env {
            name  = "ADMISSION_WAIT_S"
            value = tostring(var.admission_wait_s)
          }

          port {
            name           = "http"
            container_port = 8080
          }

          # Question embedding (fastembed) runs on CPU inside this pod.
          resources {
            requests = { cpu = "1", memory = "1Gi" }
            limits   = { cpu = "2", memory = "2Gi" }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            period_seconds = 5
          }
        }
      }
    }
  }

  lifecycle {
    # Checks a rule across two variables (a variable validation can only
    # see its own value). Fails the plan before anything is deployed.
    precondition {
      condition     = var.top_k <= var.max_top_k
      error_message = "top_k (${var.top_k}) can't be bigger than max_top_k (${var.max_top_k})."
    }
  }

  depends_on = [kubernetes_job_v1.ingest]
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = "rag-app"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.app_labels
  }
  spec {
    selector = local.app_labels
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

# The app mounts its metrics at "/metrics/" (a sub-app), so scrape that path
# directly instead of relying on the /metrics -> /metrics/ redirect.
resource "kubernetes_manifest" "service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "rag-app"
      namespace = kubernetes_namespace_v1.this.metadata[0].name
      labels    = local.app_labels
    }
    spec = {
      selector = { matchLabels = local.app_labels }
      endpoints = [{
        port     = "http"
        path     = "/metrics/"
        interval = "5s"
      }]
    }
  }
}

# --- Public access -------------------------------------------------------------
# An Ingress with class "alb" makes the AWS Load Balancer Controller create an
# internet-facing Application Load Balancer. ONLY this app is exposed: vLLM,
# the router, Prometheus and Grafana have no Ingress and stay private.
locals {
  behind_cloudfront = var.cloudfront_origin != null
}

resource "kubernetes_ingress_v1" "public" {
  count = var.expose_publicly ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.behind_cloudfront || length(var.public_allowed_cidrs) > 0
      error_message = "Set public_allowed_cidrs (or put the ALB behind CloudFront) when expose_publicly = true."
    }
  }

  metadata {
    name      = "rag-app-public"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    annotations = merge({
      "alb.ingress.kubernetes.io/load-balancer-name" = "gpu-demo-rag"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      # Send traffic straight to pod IPs (VPC CNI gives pods real VPC IPs).
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/healthcheck-path" = "/health"
      # Default ALB idle timeout is 60 s; overloaded answers can take longer.
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=180"
      # A fixed 404 for /metrics, so the internet can't read Prometheus data.
      "alb.ingress.kubernetes.io/actions.block-metrics" = jsonencode({
        type = "fixed-response"
        fixedResponseConfig = {
          contentType = "text/plain"
          statusCode  = "404"
          messageBody = "Not found"
        }
      })
      },
      # Who may reach the ALB — the controller writes this into its security group.
      local.behind_cloudfront ? tomap({
        # Only CloudFront's edge servers (AWS-managed prefix list)...
        "alb.ingress.kubernetes.io/security-group-prefix-lists" = var.cloudfront_origin.prefix_list_id
        # ...and only when they carry our secret header. Requests without it
        # match no rule and get the ALB's default 404.
        "alb.ingress.kubernetes.io/conditions.rag-app" = jsonencode([{
          field            = "http-header"
          httpHeaderConfig = { httpHeaderName = "X-Origin-Verify", values = [var.cloudfront_origin.verify_header] }
        }])
        }) : tomap({
        "alb.ingress.kubernetes.io/inbound-cidrs" = join(",", var.public_allowed_cidrs)
    }))
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        # Rules are matched in order: /metrics first, then everything else.
        path {
          path      = "/metrics"
          path_type = "Prefix"
          backend {
            service {
              name = "block-metrics" # refers to the action annotation above
              port {
                name = "use-annotation"
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.app.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }

  # Wait until AWS has provisioned the ALB, so its hostname is in the output.
  wait_for_load_balancer = true
}
