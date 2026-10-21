#!/usr/bin/env bash
# Deploy Monitoring Stack: Prometheus and Grafana (Bash)
set -euo pipefail

echo ">>> Deploying Monitoring Stack (Prometheus & Grafana with pre-provisioned Dashboards)..."

kubectl apply -f monitoring/

echo "Waiting for Prometheus and Grafana pods to be ready..."
kubectl wait --for=condition=Ready pods -l app=prometheus -n monitoring --timeout=180s
kubectl wait --for=condition=Ready pods -l app=grafana -n monitoring --timeout=180s

echo "✓ Monitoring Stack deployed successfully!"
echo "Prometheus accessible at: http://localhost:9090"
echo "Grafana accessible at:    http://localhost:3000 (User: admin, Pass: admin)"
