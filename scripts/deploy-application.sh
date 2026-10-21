#!/usr/bin/env bash
# Deploy Sample Microservices Application (Online Boutique) (Bash)
set -euo pipefail

echo ">>> Deploying Online Boutique Microservices Application..."

kubectl apply -f application/online-boutique.yaml -n online-boutique

echo "Waiting for deployments to roll out in 'online-boutique' namespace..."
for dep in $(kubectl get deployments -n online-boutique -o jsonpath='{.items[*].metadata.name}'); do
    echo "  Waiting for deployment/$dep..."
    kubectl rollout status "deployment/$dep" -n online-boutique --timeout=180s
done

echo "✓ Target microservices application deployed and ready!"
echo "Application Frontend accessible at: http://localhost:30080"
