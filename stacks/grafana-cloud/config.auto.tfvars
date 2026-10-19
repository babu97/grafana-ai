# Non-secret Grafana Cloud settings (committed). Tokens are in SSM — see variables.tf.
grafana_url           = "https://maroonbegonia3114.grafana.net"
prom_remote_write_url = "https://prometheus-prod-55-prod-gb-south-1.grafana.net/api/prom/push"
prom_username         = "3686299" # Prometheus instance ID, not a secret
