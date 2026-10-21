# Cleanup Script for Chaos Engineering Platform (PowerShell)
param (
    [switch]$DeleteCluster
)

$ErrorActionPreference = "Continue"

Write-Host ">>> Cleaning up Chaos Engineering Platform Resources..." -ForegroundColor Cyan

# 1. Stop all Chaos Experiments
Write-Host "Stopping all active Chaos Mesh experiments and workflows..." -ForegroundColor Yellow
kubectl delete podchaos,networkchaos,iochaos,stresschaos,httpchaos,workflow,schedule --all -n chaos-mesh --ignore-not-found

# 2. Delete Application Namespace
Write-Host "Deleting target application namespace 'online-boutique'..." -ForegroundColor Yellow
kubectl delete namespace online-boutique --ignore-not-found

# 3. Delete Monitoring Namespace
Write-Host "Deleting monitoring namespace 'monitoring'..." -ForegroundColor Yellow
kubectl delete namespace monitoring --ignore-not-found

# 4. Uninstall Chaos Mesh
Write-Host "Uninstalling Chaos Mesh helm release..." -ForegroundColor Yellow
helm uninstall chaos-mesh -n chaos-mesh 2>$null
kubectl delete namespace chaos-mesh --ignore-not-found

if ($DeleteCluster) {
    Write-Host "Deleting Kind cluster 'chaos-cluster'..." -ForegroundColor Red
    kind delete cluster --name chaos-cluster
}

Write-Host "`n✓ Cleanup completed successfully!" -ForegroundColor Green
