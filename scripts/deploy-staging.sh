#!/bin/bash
set -e

echo "🚀 Deploying Full Colombiano Staging to k3s"
echo "============================================"

# Set kubeconfig
export KUBECONFIG="$(pwd)/.kube/dev-k3s.yaml"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first."
    exit 1
fi

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG" ]; then
    echo "❌ Kubeconfig not found at $KUBECONFIG"
    exit 1
fi

echo ""
echo "📦 Step 1: Creating namespace..."
kubectl create namespace stg-apps --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace created"

echo ""
echo "📝 Step 2: Updating secrets..."
echo "⚠️  Please update the secrets in deploy-backend-staging.yaml before deploying!"
read -p "Press Enter to continue or Ctrl+C to cancel..."

echo ""
echo "🔧 Step 3: Deploying backend..."
kubectl apply -f deploy-backend-staging.yaml

echo ""
echo "🎨 Step 4: Deploying frontend..."
kubectl apply -f deploy-frontend-staging.yaml

echo ""
echo "⏳ Step 5: Waiting for deployments..."
kubectl rollout status deployment/backend-api -n stg-apps --timeout=5m || true
kubectl rollout status deployment/frontend -n stg-apps --timeout=5m || true

echo ""
echo "📊 Step 6: Checking deployment status..."
kubectl get pods -n stg-apps
kubectl get svc -n stg-apps
kubectl get ingress -n stg-apps

echo ""
echo "✅ Deployment completed!"
echo ""
echo "📋 Useful commands:"
echo "  kubectl get pods -n stg-apps"
echo "  kubectl logs -n stg-apps -l app=backend-api --tail=50"
echo "  kubectl logs -n stg-apps -l app=frontend --tail=50"
echo "  kubectl get ingress -n stg-apps"
echo "  kubectl get certificate -n stg-apps"

