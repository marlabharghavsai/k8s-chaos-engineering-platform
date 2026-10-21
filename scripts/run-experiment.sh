#!/usr/bin/env bash
# Trigger Chaos Experiment with Automated Pre-flight and SLI Monitoring (Bash)
set -euo pipefail

EXPERIMENT="${1:-workflow}"

echo "============================================================"
echo "  EXECUTING CHAOS EXPERIMENT: ${EXPERIMENT}"
echo "============================================================"

# Step 1: Pre-flight Verification
echo -e "\n[Step 1] Running Pre-flight Steady-State Verification..."
./scripts/preflight-check.sh

# Step 2: Resolve Target Manifest
declare -A MANIFEST_MAP=(
    ["workflow"]="chaos/workflows/cascading-failure-workflow.yaml"
    ["pod-kill"]="chaos/experiments/01-pod-kill-frontend.yaml"
    ["pod-failure"]="chaos/experiments/01-pod-failure-cart.yaml"
    ["network-latency"]="chaos/experiments/02-network-latency-productcatalog.yaml"
    ["network-loss"]="chaos/experiments/02-network-loss-currencyservice.yaml"
    ["io-latency"]="chaos/experiments/03-io-latency-redis.yaml"
    ["stress-cpu"]="chaos/experiments/04-stress-cpu-frontend.yaml"
    ["stress-memory"]="chaos/experiments/04-stress-memory-recommendation.yaml"
    ["http-delay"]="chaos/experiments/05-http-delay-api.yaml"
    ["http-replace"]="chaos/experiments/05-http-replace-status.yaml"
    ["schedule"]="chaos/schedules/nightly-pod-kill-schedule.yaml"
)

MANIFEST="${MANIFEST_MAP[$EXPERIMENT]:-}"
if [ -z "$MANIFEST" ]; then
    echo "Unknown experiment: $EXPERIMENT"
    echo "Valid options: workflow, pod-kill, pod-failure, network-latency, network-loss, io-latency, stress-cpu, stress-memory, http-delay, http-replace, schedule"
    exit 1
fi

echo -e "\n[Step 2] Applying Chaos Manifest: $MANIFEST..."
kubectl apply -f "$MANIFEST"

# Step 3: Real-Time SLI Telemetry and Fault Observation
echo -e "\n[Step 3] Monitoring Active Chaos & Application Telemetry for 45s..."
for i in {1..9}; do
    sleep 5
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:30080" 2>/dev/null || echo "000")
    LATENCY=$(curl -s -o /dev/null -w "%{time_total}" --max-time 3 "http://localhost:30080" 2>/dev/null || echo "0")
    echo "  [+${i}x5s] HTTP Probe: Status=${STATUS_CODE} | Latency=${LATENCY}s"
done

# Step 4: Verification & Inspection
echo -e "\n[Step 4] Checking Active Experiments in Chaos Mesh..."
kubectl get podchaos,networkchaos,iochaos,stresschaos,httpchaos,workflow,schedule -n chaos-mesh --ignore-not-found

echo -e "\n✓ Chaos Experiment execution cycle completed!"
echo "View Grafana Dashboard for visual SLI impact: http://localhost:3000"
echo "View Chaos Mesh Dashboard for injection traces: http://localhost:2333"
