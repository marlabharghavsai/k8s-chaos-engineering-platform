# Trigger Chaos Experiment with Automated Pre-flight and SLI Monitoring (PowerShell)
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("workflow", "pod-kill", "pod-failure", "network-latency", "network-loss", "io-latency", "stress-cpu", "stress-memory", "http-delay", "http-replace", "schedule")]
    [string]$Experiment = "workflow"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  EXECUTING CHAOS EXPERIMENT: $Experiment" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Step 1: Pre-flight Verification
Write-Host "`n[Step 1] Running Pre-flight Steady-State Verification..." -ForegroundColor Yellow
& "$PSScriptRoot\preflight-check.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ABORT] System not in steady state. Experiment halted for safety." -ForegroundColor Red
    exit 1
}

# Step 2: Resolve Target Manifest
$manifestMap = @{
    "workflow"        = "chaos/workflows/cascading-failure-workflow.yaml"
    "pod-kill"        = "chaos/experiments/01-pod-kill-frontend.yaml"
    "pod-failure"     = "chaos/experiments/01-pod-failure-cart.yaml"
    "network-latency" = "chaos/experiments/02-network-latency-productcatalog.yaml"
    "network-loss"    = "chaos/experiments/02-network-loss-currencyservice.yaml"
    "io-latency"      = "chaos/experiments/03-io-latency-redis.yaml"
    "stress-cpu"      = "chaos/experiments/04-stress-cpu-frontend.yaml"
    "stress-memory"   = "chaos/experiments/04-stress-memory-recommendation.yaml"
    "http-delay"      = "chaos/experiments/05-http-delay-api.yaml"
    "http-replace"    = "chaos/experiments/05-http-replace-status.yaml"
    "schedule"        = "chaos/schedules/nightly-pod-kill-schedule.yaml"
}

$manifestPath = $manifestMap[$Experiment]
Write-Host "`n[Step 2] Applying Chaos Manifest: $manifestPath..." -ForegroundColor Yellow
kubectl apply -f $manifestPath

# Step 3: Real-Time SLI Telemetry and Fault Observation
Write-Host "`n[Step 3] Monitoring Active Chaos and Application Telemetry for 45s..." -ForegroundColor Yellow
$startTime = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 1; $i -le 9; $i++) {
    Start-Sleep -Seconds 5
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $statusCode = 0
    try {
        $res = Invoke-WebRequest -Uri "http://localhost:30080" -UseBasicParsing -TimeoutSec 3
        $statusCode = $res.StatusCode
    } catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        } else {
            $statusCode = 503
        }
    }
    $sw.Stop()
    $latencyMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 2)
    
    $color = "Green"
    if ($statusCode -ne 200 -or $latencyMs -gt 250) { $color = "Yellow" }
    if ($statusCode -ge 500) { $color = "Red" }
    
    Write-Host ("  [+${i}x5s] HTTP Probe: Status={0} | Latency={1}ms" -f $statusCode, $latencyMs) -ForegroundColor $color
}

# Step 4: Verification and Inspection
Write-Host "`n[Step 4] Checking Active Experiments in Chaos Mesh..." -ForegroundColor Yellow
kubectl get podchaos,networkchaos,iochaos,stresschaos,httpchaos,workflow,schedule -n chaos-mesh --ignore-not-found

Write-Host "`n[OK] Chaos Experiment execution cycle completed!" -ForegroundColor Green
Write-Host "View Grafana Dashboard for visual SLI impact: http://localhost:3000" -ForegroundColor Cyan
Write-Host "View Chaos Mesh Dashboard for injection traces: http://localhost:2333" -ForegroundColor Cyan
