# Deploy Monitoring Stack: Prometheus and Grafana (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host ">>> Deploying Monitoring Stack (Prometheus & Grafana with pre-provisioned Dashboards)..." -ForegroundColor Cyan

kubectl apply -f monitoring/

Write-Host "Waiting for Prometheus and Grafana pods to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready pods -l app=prometheus -n monitoring --timeout=180s
kubectl wait --for=condition=Ready pods -l app=grafana -n monitoring --timeout=180s

Write-Host "`n✓ Monitoring Stack deployed successfully!" -ForegroundColor Green
Write-Host "Prometheus accessible at: http://localhost:9090" -ForegroundColor Yellow
Write-Host "Grafana accessible at:    http://localhost:3000 (User: admin, Pass: admin)" -ForegroundColor Yellow
