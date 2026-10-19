output "run_command" {
  description = "Start a load test run."
  value       = "kubectl -n ${var.namespace} create job --from=cronjob/${kubernetes_cron_job_v1.k6.metadata[0].name} k6-run-$(date +%s)"
}

output "logs_command" {
  value = "kubectl -n ${var.namespace} logs -f -l app.kubernetes.io/name=${var.name}"
}
