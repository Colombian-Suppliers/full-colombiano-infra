# Development Environment (Local)

Ambiente de desarrollo **local** en tu máquina usando Docker Desktop o Minikube.

## ⚙️ Setup Recomendado

### Docker Desktop (Preferido para Mac/Windows)

**Ventajas**:
- Integración nativa con el sistema operativo
- Fácil de usar
- Buen rendimiento

**Instalación**:

```bash
# 1. Descargar Docker Desktop
# https://www.docker.com/products/docker-desktop

# 2. Instalar y abrir Docker Desktop

# 3. Habilitar Kubernetes
# Docker Desktop → Settings → Kubernetes → Enable Kubernetes

# 4. Esperar que arranque (ícono de Docker en verde)

# 5. Verificar
kubectl config use-context docker-desktop
kubectl get nodes
# Debería mostrar 1 node "docker-desktop"
```

### Minikube (Alternativa para Linux o preferencia personal)

```bash
# Instalar
# MacOS:
brew install minikube

# Linux:
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Iniciar cluster
minikube start --cpus=4 --memory=8192 --driver=docker

# Verificar
kubectl get nodes
```

## 📦 Instalar Platform Components

### Método 1: Script Rápido

```bash
cd environments/dev

# Ejecutar script de setup
./setup-local-dev.sh

# Este script instala:
# - ingress-nginx
# - cert-manager (con self-signed issuer para dev)
# - metrics-server
```

### Método 2: Manual (Helm)

```bash
# 1. Crear namespaces
kubectl apply -f local-dev-setup.yaml

# 2. Instalar ingress-nginx
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n platform \
  --set controller.service.type=LoadBalancer \
  --set controller.hostPort.enabled=true \
  --set controller.hostPort.ports.http=80 \
  --set controller.hostPort.ports.https=443

# 3. Instalar cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# 4. Crear self-signed issuer (para dev local)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

# 5. Instalar metrics-server (si no viene con tu cluster)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Para minikube, agregar flag --kubelet-insecure-tls
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
```

## 🚀 Desplegar Aplicación de Ejemplo

```bash
# Aplicar ejemplo
kubectl apply -f ../../examples/hello-world-app.yaml

# Modificar para usar self-signed issuer
kubectl patch ingress hello-world -n demo -p \
  '{"metadata":{"annotations":{"cert-manager.io/cluster-issuer":"selfsigned-issuer"}}}'

# Ver pods
kubectl get pods -n demo

# Acceder (Docker Desktop)
# Agregar a /etc/hosts:
echo "127.0.0.1 hello.local.dev" | sudo tee -a /etc/hosts

# Acceder
curl -k https://hello.local.dev  # -k porque es self-signed
```

## 🔍 Verificar que Todo Funciona

```bash
# Ver todos los componentes
kubectl get pods -n platform
kubectl get pods -n kube-system

# Ver servicios
kubectl get svc -A

# Ver recursos
kubectl top nodes
kubectl top pods -A

# Test de conectividad
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://ingress-nginx-controller.platform.svc.cluster.local
```

## 💡 Tips para Desarrollo Local

### Hot Reload con Skaffold

```bash
# Instalar Skaffold
brew install skaffold

# En tu proyecto
skaffold dev
# Detecta cambios y redeploy automáticamente
```

### Debugging con Port-Forward

```bash
# Forward port de un pod
kubectl port-forward -n apps pod/myapp-123456-abcde 8080:8080

# Forward servicio
kubectl port-forward -n apps svc/myapp 8080:80

# Ahora accede en http://localhost:8080
```

### Ver Logs en Tiempo Real

```bash
# Logs de un pod
kubectl logs -n apps deployment/myapp -f

# Logs de todos los pods con un label
kubectl logs -n apps -l app=myapp -f --max-log-requests=10

# Con stern (recomendado)
brew install stern
stern -n apps myapp
```

## 🧹 Limpiar Recursos

```bash
# Eliminar aplicación de ejemplo
kubectl delete -f ../../examples/hello-world-app.yaml

# Limpiar todo el namespace apps
kubectl delete namespace apps --force --grace-period=0

# Recrear namespace limpio
kubectl create namespace apps
```

## 🔄 Reiniciar Cluster

### Docker Desktop

```bash
# Reiniciar Kubernetes
# Docker Desktop → Settings → Kubernetes → Reset Kubernetes Cluster
```

### Minikube

```bash
# Detener
minikube stop

# Eliminar y recrear
minikube delete
minikube start --cpus=4 --memory=8192
```

## 🆚 Diferencias con Staging/Prod (VPS)

| Aspecto | Dev Local | Staging/Prod (VPS) |
|---------|-----------|-------------------|
| **Cluster** | Docker Desktop/Minikube | k3s en VPS |
| **Dominio** | `*.local.dev` + `/etc/hosts` | DNS real |
| **Certificados** | Self-signed | Let's Encrypt |
| **Ingress IP** | `127.0.0.1` o `localhost` | IP pública del VPS |
| **Costo** | $0 (usa tu laptop) | $20/mes (VPS compartido) |
| **Acceso** | Solo tu | Accesible públicamente |

## 📚 Recursos para Aprender

- [Docker Desktop Kubernetes](https://docs.docker.com/desktop/kubernetes/)
- [Minikube Docs](https://minikube.sigs.k8s.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Lens](https://k8slens.dev/) - GUI para Kubernetes (recomendado)

## 🐛 Troubleshooting

### "No resources found"

```bash
# Verificar contexto correcto
kubectl config current-context

# Cambiar a docker-desktop o minikube
kubectl config use-context docker-desktop
# o
kubectl config use-context minikube
```

### Ingress no funciona

```bash
# Verificar ingress controller
kubectl get pods -n platform

# Docker Desktop: Verificar que LoadBalancer tiene EXTERNAL-IP
kubectl get svc -n platform ingress-nginx-controller

# Si está en <pending>, en Docker Desktop es normal
# Usa port-forward:
kubectl port-forward -n platform svc/ingress-nginx-controller 8080:80
```

### Certificados no se emiten

```bash
# En dev local, usar self-signed
# Ver issuer
kubectl get clusterissuer

# Describir certificado
kubectl describe certificate -n demo hello-world
```

## 🔐 No Usar Terraform en Dev Local

**Importante**: Este environment NO usa Terraform porque:
- Es local, no hay infraestructura que provisionar
- Más rápido iterar con `kubectl` directo
- Permite experimentar libremente

Para staging y producción (VPS), sí usamos Terraform para IaC.
