# Pre-flight Health Check Script (PowerShell)
# Verifies steady-state conditions before injecting chaos experiments.

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CHAOS ENGINEERING PLATFORM: PRE-FLIGHT HEALTH CHECK       " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$passed = $true

# 1. Cluster Node Health
Write-Host "`n[1/5] Checking Kubernetes Cluster Nodes..." -ForegroundColor Yellow
$nodeLines = kubectl get nodes --no-headers
foreach ($line in $nodeLines) {
    $parts = $line -split '\s+'
    $name = $parts[0]
    $status = $parts[1]
    if ($status -eq "Ready") {
        Write-Host "  [OK] Node $name is Ready" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Node $name is in state: $status" -ForegroundColor Red
        $passed = $false
    }
}

# 2. Chaos Mesh Platform Health
Write-Host "`n[2/5] Checking Chaos Mesh Platform Daemons and Controller..." -ForegroundColor Yellow
$chaosPods = (kubectl get pods -n chaos-mesh --no-headers) -join "`n"
if ($chaosPods -match "chaos-controller-manager.*Running" -and $chaosPods -match "chaos-daemon.*Running") {
    Write-Host "  [OK] Chaos Mesh Controller Manager and Daemon are Running" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Chaos Mesh components not fully operational yet" -ForegroundColor Red
    $passed = $false
}

# 3. Monitoring Stack Health
Write-Host "`n[3/5] Checking Prometheus and Grafana Monitoring Stack..." -ForegroundColor Yellow
$monitoringPods = (kubectl get pods -n monitoring --no-headers) -join "`n"
if ($monitoringPods -match "prometheus.*Running" -and $monitoringPods -match "grafana.*Running") {
    Write-Host "  [OK] Prometheus and Grafana are Running" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Monitoring stack pods are still initializing..." -ForegroundColor Yellow
}

# 4. Target Application Steady-State (online-boutique)
Write-Host "`n[4/5] Checking Target Application (online-boutique pods)..." -ForegroundColor Yellow
$appPods = kubectl get pods -n online-boutique --no-headers
$totalPods = ($appPods | Measure-Object).Count
$readyPods = 0
foreach ($line in $appPods) {
    if ($line -match "1/1\s+Running|2/2\s+Running") {
        $readyPods++
    }
}

Write-Host "  Application pods ready: $readyPods / $totalPods"
if ($readyPods -ge 10) {
    Write-Host "  [OK] Target application microservices are in steady-state" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Insufficient application pods in Ready state ($readyPods ready)" -ForegroundColor Red
    $passed = $false
}

# 5. Application Ingress & End-to-End Synthetic Probe
Write-Host "`n[5/5] Performing Synthetic HTTP Latency and Availability Probe..." -ForegroundColor Yellow
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri "http://localhost:30080" -UseBasicParsing -TimeoutSec 5
    $sw.Stop()
    $latencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
    
    if ($response.StatusCode -eq 200) {
        Write-Host "  [OK] Frontend HTTP 200 OK received! (Baseline Latency: ${latencyMs}ms)" -ForegroundColor Green
        if ($latencyMs -gt 1000) {
            Write-Host "  [WARN] Baseline latency exceeds 1000ms threshold" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] Frontend returned unexpected HTTP status: $($response.StatusCode)" -ForegroundColor Red
        $passed = $false
    }
} catch {
    Write-Host "  [FAIL] Failed to reach application frontend at http://localhost:30080: $($_.Exception.Message)" -ForegroundColor Red
    $passed = $false
}

Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
if ($passed) {
    Write-Host "*** PRE-FLIGHT HEALTH CHECK: PASSED (Steady State Confirmed) ***" -ForegroundColor Green
    exit 0
} else {
    Write-Host "*** PRE-FLIGHT HEALTH CHECK: FAILED (System not in steady state) ***" -ForegroundColor Red
    exit 1
}
