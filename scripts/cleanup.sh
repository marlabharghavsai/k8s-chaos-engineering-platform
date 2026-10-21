#!/usr/bin/env bash
# Cleanup Script for Chaos Engineering Platform (Bash)
set +e

DELETE_CLUSTER="${1:-}"

echo ">>> Cleaning up Chaos Engineering Platform Resources..."

# 1. Stop all Chaos Experiments
echo "Stopping all active Chaos Mesh experiments and workflows..."
kubectl delete podchaos,networkchaos,iochaos,stresschaos,httpchaos,workflow,schedule --all -n chaos-mesh --ignore-not-found 2>/dev/null || true

# 2. Delete Application Namespace
echo "Deleting target application namespace 'online-boutique'..."
kubectl delete namespace online-boutique --ignore-not-found 2>/dev/null || true

# 3. Delete Monitoring Namespace
echo "Deleting monitoring namespace 'monitoring'..."
kubectl delete namespace monitoring --ignore-not-found 2>/dev/null || true

# 4. Uninstall Chaos Mesh
echo "Uninstalling Chaos Mesh helm release..."
helm uninstall chaos-mesh -n chaos-mesh 2>/dev/null || true
kubectl delete namespace chaos-mesh --ignore-not-found 2>/dev/null || true

if [ "$DELETE_CLUSTER" == "--delete-cluster" ]; then
    echo "Deleting Kind cluster 'chaos-cluster'..."
    kind delete cluster --name chaos-cluster || true
fi

echo "✓ Cleanup completed successfully!"
