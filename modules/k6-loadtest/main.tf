# The k6 script lives in a ConfigMap, mounted into the k6 pod as a file.
# file() reads it at plan time, so editing the .js shows up as a diff.
resource "kubernetes_config_map_v1" "script" {
  metadata {
    name      = "${var.name}-script"
    namespace = var.namespace
  }

  data = {
    # script_path (any file) wins over script (a file in ./scripts).
    "script.js" = file(coalesce(var.script_path, "${path.module}/scripts/${var.script}"))
  }
}

# -----------------------------------------------------------------------------
# A SUSPENDED CronJob, used as a job template.
#
# If Terraform created a plain Job, the load test would fire the moment you run
# `terraform apply` — not when you're on stage. Instead Terraform owns the
# definition, and you trigger runs by hand:
#
#   kubectl -n llm create job --from=cronjob/k6-llm-ramp k6-run-$(date +%s)
#
# Each run is a fresh Job; the schedule never fires because suspend = true.
# -----------------------------------------------------------------------------
resource "kubernetes_cron_job_v1" "k6" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    schedule           = "0 0 1 1 *"
    suspend            = true
    concurrency_policy = "Forbid"

    job_template {
      metadata {}

      spec {
        backoff_limit              = 0    # a failed load test shouldn't silently re-run
        ttl_seconds_after_finished = 3600 # clean up finished runs after an hour

        template {
          metadata {
            labels = { "app.kubernetes.io/name" = var.name }
          }

          spec {
            restart_policy = "Never"

            # Run on CPU nodes — never steal resources from the GPU node.
            node_selector = { workload = "system" }

            container {
              name  = "k6"
              image = var.image
              args  = ["run", "-o", "experimental-prometheus-rw", "/scripts/script.js"]

              # Where k6 sends its metrics (Prometheus remote-write receiver,
              # enabled in layer 3). Metrics arrive as k6_http_reqs_total,
              # k6_http_req_duration_p99 (seconds), k6_dropped_iterations_total...
              env {
                name  = "K6_PROMETHEUS_RW_SERVER_URL"
                value = "${var.prometheus_url}/api/v1/write"
              }
              env {
                name  = "K6_PROMETHEUS_RW_TREND_STATS"
                value = "p(50),p(95),p(99),max"
              }
              env {
                name  = "K6_PROMETHEUS_RW_PUSH_INTERVAL"
                value = "5s"
              }

              # Script inputs.
              env {
                name  = "BASE_URL"
                value = var.target_base_url
              }
              env {
                name  = "MODEL"
                value = var.model
              }
              env {
                name  = "STAGES"
                value = jsonencode(var.stages)
              }
              env {
                name  = "MAX_TOKENS"
                value = tostring(var.max_tokens)
              }
              env {
                name  = "PROMPT_REPEAT"
                value = tostring(var.prompt_repeat)
              }
              env {
                name  = "MAX_VUS"
                value = tostring(var.max_vus)
              }

              # Script-specific settings (e.g. USERS for the sessions script).
              # A dynamic block repeats `env` once per map entry.
              dynamic "env" {
                for_each = var.extra_env
                content {
                  name  = env.key
                  value = env.value
                }
              }

              resources {
                requests = { cpu = "500m", memory = "512Mi" }
                limits   = { cpu = "1", memory = "1Gi" }
              }

              volume_mount {
                name       = "script"
                mount_path = "/scripts"
              }
            }

            volume {
              name = "script"
              config_map {
                name = kubernetes_config_map_v1.script.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}
