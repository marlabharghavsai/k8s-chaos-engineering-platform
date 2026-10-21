#!/usr/bin/env bash
# Setup Kind Kubernetes Cluster for Chaos Engineering Platform
set -euo pipefail

echo ">>> Initializing Kubernetes Cluster for Chaos Engineering Platform..."

if ! command -v kind &> /dev/null; then
    echo "kind CLI not found. Please install kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
fi

if kind get clusters 2>/dev/null | grep -q "^chaos-cluster$"; then
    echo "Kind cluster 'chaos-cluster' already exists. Switching context..."
    kubectl config use-context kind-chaos-cluster
else
    echo "Creating Kind cluster 'chaos-cluster'..."
    kind create cluster --config kind-cluster-config.yaml
fi

echo "Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "✓ Kubernetes Cluster is Ready!"
kubectl cluster-info
