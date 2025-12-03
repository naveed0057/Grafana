# Install docker & docker compose 
# newgrp docker
# sudo usermod -aG docker $USER
# docker-compose up -d
# docker-compose down
# Start Prometheus
docker run -d --name prometheus -p 9090:9090 prom/prometheus
# Start Grafana
docker run -d --name grafana -p 3000:3000 grafana/grafana
# Node Exporter 
docker run -d --name node-exporter -p 9100:9100 prom/node-exporter
Access Prometheus: **http://localhost:9090**
Access Grafana: **http://localhost:3000** (login: admin/admin)
CPU Usage node PromQL - **rate(node_cpu_seconds_total[5m])**
Memory Usage PromQl - **node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100**
Install Jaeger - **docker run -d --name jaeger -p 16686:16686 jaegertracing/all-in-one:latest**
