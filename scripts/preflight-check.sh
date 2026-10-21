#!/usr/bin/env bash
# Pre-flight Health Check Script (Bash)
# Verifies steady-state conditions before injecting chaos experiments.

set -euo pipefail

echo "============================================================"
echo "  CHAOS ENGINEERING PLATFORM: PRE-FLIGHT HEALTH CHECK       "
echo "============================================================"

PASSED=true

# 1. Cluster Node Health
echo -e "\n[1/5] Checking Kubernetes Cluster Nodes..."
NOT_READY=$(kubectl get nodes --no-headers | awk '{print $2}' | grep -v 'Ready' || true)
if [ -z "$NOT_READY" ]; then
    echo "  ✓ All Kubernetes nodes are Ready"
else
    echo "  ✗ Some nodes are Not Ready"
    PASSED=false
fi

# 2. Chaos Mesh Platform Health
echo -e "\n[2/5] Checking Chaos Mesh Platform Daemons & Controller..."
if kubectl get pods -n chaos-mesh | grep -q 'chaos-controller-manager.*Running' && \
   kubectl get pods -n chaos-mesh | grep -q 'chaos-daemon.*Running'; then
    echo "  ✓ Chaos Mesh Controller Manager and Daemon are Running"
else
    echo "  ✗ Chaos Mesh components not fully operational yet"
    PASSED=false
fi

# 3. Monitoring Stack Health
echo -e "\n[3/5] Checking Prometheus & Grafana Monitoring Stack..."
if kubectl get pods -n monitoring | grep -q 'prometheus.*Running' && \
   kubectl get pods -n monitoring | grep -q 'grafana.*Running'; then
    echo "  ✓ Prometheus and Grafana are Running"
else
    echo "  ! Monitoring stack pods are still initializing..."
fi

# 4. Target Application Steady-State
echo -e "\n[4/5] Checking Target Application (online-boutique pods)..."
READY_COUNT=$(kubectl get pods -n online-boutique --no-headers 2>/dev/null | grep -E '1/1|2/2' | grep -c 'Running' || true)
TOTAL_COUNT=$(kubectl get pods -n online-boutique --no-headers 2>/dev/null | wc -l || true)

echo "  Application pods ready: ${READY_COUNT} / ${TOTAL_COUNT}"
if [ "$READY_COUNT" -ge 10 ]; then
    echo "  ✓ Target application microservices are in steady-state"
else
    echo "  ✗ Insufficient application pods in Ready state ($READY_COUNT ready)"
    PASSED=false
fi

# 5. Application Ingress & End-to-End Synthetic Probe
echo -e "\n[5/5] Performing Synthetic HTTP Latency & Availability Probe..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:30080" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" -eq 200 ]; then
    LATENCY=$(curl -s -o /dev/null -w "%{time_total}" --max-time 5 "http://localhost:30080" 2>/dev/null || echo "0")
    echo "  ✓ Frontend HTTP 200 OK received! (Baseline Latency: ${LATENCY}s)"
else
    echo "  ✗ Frontend returned HTTP status: ${HTTP_CODE}"
    PASSED=false
fi

echo -e "\n------------------------------------------------------------"
if [ "$PASSED" = true ]; then
    echo ">>> PRE-FLIGHT HEALTH CHECK: PASSED (Steady State Confirmed) <<<"
    exit 0
else
    echo ">>> PRE-FLIGHT HEALTH CHECK: FAILED (System not in steady state) <<<"
    exit 1
fi
