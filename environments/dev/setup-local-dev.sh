#!/bin/bash
set -e

echo "🚀 Setting up Local Development Kubernetes Environment"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ helm not found. Please install helm first.${NC}"
    exit 1
fi

# Check which cluster we're using
CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "${BLUE}📍 Current context: $CURRENT_CONTEXT${NC}"

if [[ "$CURRENT_CONTEXT" != "docker-desktop" ]] && [[ "$CURRENT_CONTEXT" != "minikube" ]]; then
    echo -e "${RED}⚠️  Warning: You're not using docker-desktop or minikube${NC}"
    echo -e "${RED}   Current context: $CURRENT_CONTEXT${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}📦 Step 1: Creating namespaces${NC}"
kubectl apply -f local-dev-setup.yaml

echo ""
echo -e "${BLUE}📦 Step 2: Installing ingress-nginx${NC}"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update

if helm list -n platform | grep -q ingress-nginx; then
    echo "  ingress-nginx already installed, upgrading..."
    helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
        -n platform \
        --set controller.service.type=LoadBalancer \
        --set controller.hostPort.enabled=true \
        --set controller.hostPort.ports.http=80 \
        --set controller.hostPort.ports.https=443
else
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        -n platform \
        --set controller.service.type=LoadBalancer \
        --set controller.hostPort.enabled=true \
        --set controller.hostPort.ports.http=80 \
        --set controller.hostPort.ports.https=443
fi

echo ""
echo -e "${BLUE}📦 Step 3: Installing cert-manager${NC}"
if kubectl get namespace cert-manager &> /dev/null; then
    echo "  cert-manager namespace exists, skipping..."
else
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    echo "  Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n cert-manager
fi

echo ""
echo -e "${BLUE}📦 Step 4: Creating self-signed ClusterIssuer${NC}"
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

echo ""
echo -e "${BLUE}📦 Step 5: Installing/Patching metrics-server${NC}"
if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    echo "  metrics-server already exists"
    if [[ "$CURRENT_CONTEXT" == "minikube" ]]; then
        echo "  Patching for minikube..."
        kubectl patch deployment metrics-server -n kube-system --type='json' \
            -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]' 2>/dev/null || true
    fi
else
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    if [[ "$CURRENT_CONTEXT" == "minikube" ]]; then
        echo "  Patching for minikube..."
        sleep 5
        kubectl patch deployment metrics-server -n kube-system --type='json' \
            -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    fi
fi

echo ""
echo -e "${GREEN}✅ Local development environment setup complete!${NC}"
echo ""
echo -e "${BLUE}📋 Verification:${NC}"
echo ""

# Wait a bit for things to start
sleep 5

echo "Checking pods in platform namespace:"
kubectl get pods -n platform

echo ""
echo "Checking ingress controller service:"
kubectl get svc -n platform ingress-nginx-controller

echo ""
echo -e "${GREEN}🎉 Setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Deploy example app:"
echo "   kubectl apply -f ../../examples/hello-world-app.yaml"
echo ""
echo "2. Add to /etc/hosts:"
echo "   echo '127.0.0.1 hello.local.dev' | sudo tee -a /etc/hosts"
echo ""
echo "3. Access app:"
echo "   curl -k https://hello.local.dev"
echo ""
echo "4. View resources:"
echo "   kubectl top nodes"
echo "   kubectl top pods -A"

