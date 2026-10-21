#!/usr/bin/env bash
# Install Chaos Mesh via Helm (Bash)
set -euo pipefail

echo ">>> Deploying Chaos Mesh Platform Engine & Dashboard..."

helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --set dashboard.service.type=NodePort \
  --set dashboard.service.nodePort=32333

echo "Waiting for Chaos Mesh components to become ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=chaos-mesh -n chaos-mesh --timeout=180s

echo "✓ Chaos Mesh Platform deployed successfully!"
echo "Chaos Mesh Dashboard accessible at: http://localhost:2333"
