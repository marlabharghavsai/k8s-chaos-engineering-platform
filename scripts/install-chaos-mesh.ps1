# Install Chaos Mesh via Helm (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host ">>> Deploying Chaos Mesh Platform Engine & Dashboard..." -ForegroundColor Cyan

# Add Helm Repo
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

# Install or Upgrade Chaos Mesh with Kind containerd runtime parameters and NodePort dashboard
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh `
  --namespace chaos-mesh `
  --create-namespace `
  --set chaosDaemon.runtime=containerd `
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock `
  --set dashboard.securityMode=false `
  --set dashboard.service.type=NodePort `
  --set dashboard.service.nodePort=32333

Write-Host "Waiting for Chaos Mesh controller-manager and daemon pods to become ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=chaos-mesh -n chaos-mesh --timeout=180s

Write-Host "`n✓ Chaos Mesh Platform deployed successfully!" -ForegroundColor Green
Write-Host "Chaos Mesh Dashboard accessible at: http://localhost:2333" -ForegroundColor Yellow
