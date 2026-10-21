# Deploy Sample Microservices Application (Online Boutique) (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host ">>> Deploying Online Boutique Microservices Application..." -ForegroundColor Cyan

kubectl apply -f application/online-boutique.yaml -n online-boutique

Write-Host "Waiting for deployments to roll out in 'online-boutique' namespace..." -ForegroundColor Yellow
$deployments = kubectl get deployments -n online-boutique -o jsonpath='{.items[*].metadata.name}'
foreach ($dep in ($deployments -split '\s+')) {
    if ($dep) {
        Write-Host "  Waiting for deployment/$dep..."
        kubectl rollout status deployment/$dep -n online-boutique --timeout=180s
    }
}

Write-Host "`n✓ Target microservices application deployed and ready!" -ForegroundColor Green
Write-Host "Application Frontend accessible at: http://localhost:30080" -ForegroundColor Yellow
