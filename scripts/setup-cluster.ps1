# Setup Kind Kubernetes Cluster for Chaos Engineering Platform
$ErrorActionPreference = "Stop"

Write-Host ">>> Initializing Kubernetes Cluster for Chaos Engineering Platform..." -ForegroundColor Cyan

# Ensure Kind is in path
if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    if (Test-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Links\kind.exe") {
        $env:Path = "$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"
    }
}

$clusters = kind get clusters 2>$null
if ($clusters -contains "chaos-cluster") {
    Write-Host "Kind cluster 'chaos-cluster' already exists. Switching context..." -ForegroundColor Green
    kubectl config use-context kind-chaos-cluster
} else {
    Write-Host "Creating Kind cluster 'chaos-cluster' with multi-port forward configuration..." -ForegroundColor Yellow
    kind create cluster --config kind-cluster-config.yaml
}

Write-Host "Waiting for node to become ready..." -ForegroundColor Yellow
kubectl wait --for=condition=Ready nodes --all --timeout=120s

Write-Host "`n✓ Kubernetes Cluster is Ready!" -ForegroundColor Green
kubectl cluster-info
