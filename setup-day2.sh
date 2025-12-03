
#!/usr/bin/env bash
set -euo pipefail

# === Configurable variables ===
WORKDIR="${PWD}/observability-day2"
NETWORK="obs-net"

echo ">> Creating workdir at: $WORKDIR"
mkdir -p "${WORKDIR}/prometheus/rules"
mkdir -p "${WORKDIR}/alloy"

# === Create Prometheus recording rules ===
cat > "${WORKDIR}/prometheus/rules/recording-rules.yml" <<'YAML'
groups:
  - name: node-recording-rules
    rules:
      # CPU utilization (per instance) over 5m window.
      # Formula: 1 - idle
      - record: instance:node_cpu_utilization:avg5m
        expr: 1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

      # Memory utilization (per instance)
      - record: instance:node_memory_utilization:ratio
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes

      # Prometheus HTTP request rate (by handler)
      - record: job:prometheus_http_request_rate:5m
        expr: sum by (job, instance, handler) (rate(prometheus_http_requests_total[5m]))
YAML

# === Create Prometheus main config ===
cat > "${WORKDIR}/prometheus/prometheus.yml" <<'YAML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  # Scrape Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['prometheus:9090']

  # Scrape Node Exporter (host/system metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
YAML

# === Optional: Alloy config template (Grafana Cloud). Replace placeholders if you plan to use it. ===
cat > "${WORKDIR}/alloy/config.river" <<'RIVER'
# Grafana Alloy (River) example: scrape node-exporter & remote_write to Grafana Cloud.
# Replace <GRAFANA_CLOUD_PROM_URL>, <INSTANCE_ID>, <API_KEY> with your account details.

prometheus.scrape "node" {
  targets = [
    {
      __address__ = "node-exporter:9100",
    },
  ]

  # Send scraped metrics to remote_write
  forward_to = [prometheus.remote_write.grafana.receiver]
}

prometheus.remote_write "grafana" {
  endpoint {
    url = "https://<GRAFANA_CLOUD_PROM_URL>/api/prom/push"

    basic_auth {
      username = "<INSTANCE_ID>" # Typically your Grafana Cloud Prometheus instance ID
      password = "<API_KEY>"     # Grafana Cloud API key with metrics:write
    }
  }
}
RIVER

# === Create Docker network so containers can reach each other by name ===
if ! docker network ls | awk '{print $2}' | grep -qx "${NETWORK}"; then
  echo ">> Creating docker network: ${NETWORK}"
  docker network create "${NETWORK}"
else
  echo ">> Docker network ${NETWORK} already exists"
fi

# === Start Node Exporter ===
if docker ps -a --format '{{.Names}}' | grep -qx 'node-exporter'; then
  echo ">> node-exporter already exists, restarting..."
  docker rm -f node-exporter >/dev/null 2>&1 || true
fi
echo ">> Starting node-exporter"
docker run -d --name node-exporter \
  --restart unless-stopped \
  --network "${NETWORK}" \
  -p 9100:9100 \
  prom/node-exporter:latest

# === Start Prometheus ===
if docker ps -a --format '{{.Names}}' | grep -qx 'prometheus'; then
  echo ">> prometheus already exists, restarting..."
  docker rm -f prometheus >/dev/null 2>&1 || true
fi
echo ">> Starting Prometheus"
docker run -d --name prometheus \
  --restart unless-stopped \
  --network "${NETWORK}" \
  -p 9090:9090 \
  -v "${WORKDIR}/prometheus:/etc/prometheus" \
  prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --web.enable-lifecycle

# === Start Grafana ===
if docker ps -a --format '{{.Names}}' | grep -qx 'grafana'; then
  echo ">> grafana already exists, restarting..."
  docker rm -f grafana >/dev/null 2>&1 || true
fi
echo ">> Starting Grafana"
docker run -d --name grafana \
  --restart unless-stopped \
  --network "${NETWORK}" \
  -p 3000:3000 \
  grafana/grafana:latest

# === Optional: Start Alloy (no config, just to have the agent running) ===
# If you plan to push to Grafana Cloud, mount the config.river and replace placeholders first.
if docker ps -a --format '{{.Names}}' | grep -qx 'alloy'; then
  echo ">> alloy already exists, restarting..."
  docker rm -f alloy >/dev/null 2>&1 || true
fi
echo ">> Starting Alloy (agent)"
docker run -d --name alloy \
  --restart unless-stopped \
  --network "${NETWORK}" \
  -p 12345:12345 \
  grafana/alloy:latest

echo ">> Done!"
echo ">> Prometheus UI: http://localhost:9090"
echo ">> Grafana UI:     http://localhost:3000  (default login: admin / admin)"
echo ">> Node Exporter:  http://localhost:9100/metrics"
echo ">> If using Alloy with Grafana Cloud, edit ${WORKDIR}/alloy/config.river and run:"
echo "   docker rm -f alloy && docker run -d --name alloy --restart unless-stopped --network ${NETWORK} -p 12345:12345 -v ${WORKDIR}/alloy/config.river:/etc/alloy/config.river grafana/alloy:latest"

