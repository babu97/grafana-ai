# -----------------------------------------------------------------------------
# 1. NVIDIA device plugin
#
# The AL2023 NVIDIA AMI has the driver, but Kubernetes doesn't know the GPU
# exists until this DaemonSet registers it with the kubelet as the resource
# `nvidia.com/gpu`. Only then can a pod ask for `nvidia.com/gpu: 1`.
#
# Chart defaults already do what we need:
#   - tolerate the nvidia.com/gpu NoSchedule taint
#   - only run on nodes labelled nvidia.com/gpu.present=true (set in layer 2)
# -----------------------------------------------------------------------------
resource "helm_release" "device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.device_plugin_chart_version
  namespace  = "kube-system"
}

# -----------------------------------------------------------------------------
# 2. kube-prometheus-stack
#
# Prometheus Operator + Prometheus + Grafana + node-exporter + kube-state-metrics.
# The operator watches ServiceMonitor objects and turns them into scrape config,
# so other charts (DCGM, vLLM) just ship a ServiceMonitor to get scraped.
# -----------------------------------------------------------------------------
locals {
  remote_write_enabled = var.remote_write != null
  remote_write_secret  = "grafana-cloud-remote-write"
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "mon"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version
  namespace        = var.namespace
  create_namespace = true

  # Installs CRDs and waits for many pods; give it time on a fresh cluster.
  timeout = 900

  # values = YAML documents. yamlencode() lets us write them as HCL maps,
  # so typos are caught by Terraform instead of silently ignored by Helm.
  values = [yamlencode({
    # Not needed for the demo; saves a pod on the small system nodes.
    alertmanager = { enabled = false }

    prometheus = {
      prometheusSpec = {
        retention = var.prometheus_retention

        # THE classic gotcha: by default Prometheus only picks up
        # ServiceMonitors labelled release=mon (i.e. from this chart).
        # false = "select every ServiceMonitor/PodMonitor in the cluster".
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false

        # Lets k6 (layer 4) push its metrics straight into Prometheus, so
        # load-test numbers sit on the same Grafana dashboard as the GPU.
        enableRemoteWriteReceiver = true

        # Label every series with the cluster it came from.
        externalLabels = { cluster = var.cluster_label }

        # Forward a FILTERED copy to Grafana Cloud. Prometheus still keeps
        # everything locally; only talk metrics leave the cluster.
        remoteWrite = local.remote_write_enabled ? [{
          url = var.remote_write.url
          basicAuth = {
            username = { name = local.remote_write_secret, key = "username" }
            password = { name = local.remote_write_secret, key = "password" }
          }
          writeRelabelConfigs = [{
            sourceLabels = ["__name__"]
            regex        = var.remote_write_keep_regex
            action       = "keep"
          }]
        }] : []
      }
    }

    # The Grafana Cloud credentials as a Kubernetes Secret, created by the chart
    # itself. (They are in Terraform state and the Helm release too — fine for a
    # demo; use External Secrets/Secrets Manager for real systems.)
    extraManifests = local.remote_write_enabled ? [{
      apiVersion = "v1"
      kind       = "Secret"
      metadata   = { name = local.remote_write_secret }
      type       = "Opaque"
      stringData = {
        username = var.remote_write.username
        password = var.remote_write.password
      }
    }] : []

    grafana = {
      adminPassword = random_password.grafana_admin.result

      # The dashboard sidecar loads any ConfigMap labelled grafana_dashboard=1
      # from any namespace (chart default) — that's how layer 4 ships dashboards.
      sidecar = {
        dashboards = { enabled = true }
      }
    }
  })]
}

# -----------------------------------------------------------------------------
# 3. DCGM exporter
#
# Talks to the GPU through NVIDIA's DCGM library and exposes DCGM_FI_* metrics
# (utilisation, framebuffer used, temperature, power, SM clocks...). Also maps
# each GPU to the pod using it, via the kubelet pod-resources socket.
# -----------------------------------------------------------------------------
resource "helm_release" "dcgm_exporter" {
  name       = "dcgm-exporter"
  repository = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart      = "dcgm-exporter"
  version    = var.dcgm_exporter_chart_version
  namespace  = var.namespace

  values = [yamlencode({
    # Only run where there's a GPU, and tolerate that node's taint.
    nodeSelector = { "nvidia.com/gpu.present" = "true" }
    tolerations = [{
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }]

    serviceMonitor = {
      enabled       = true
      interval      = var.gpu_scrape_interval
      scrapeTimeout = var.gpu_scrape_interval
    }
  })]

  # The ServiceMonitor CRD comes from kube-prometheus-stack; install it first.
  # The device plugin is a soft prerequisite (DCGM works without it), but
  # ordering it here means "GPU visible" before "GPU monitored".
  depends_on = [
    helm_release.kube_prometheus_stack,
    helm_release.device_plugin,
  ]
}
