# 🚀 Quickstart: Desarrollo Local a Producción

Esta guía te lleva desde desarrollo local hasta staging y producción en VPS con TLS automático.

## 🎯 Arquitectura de Ambientes

- **Dev**: Docker Desktop o Minikube en tu laptop (local)
- **Staging + Production**: Mismo VPS con namespaces separados (~$20/mes)
- **Futura migración a cloud**: AWS EKS o GCP GKE cuando necesites escalar

## Opción 1: Desarrollo Local (Gratis, Tu Laptop)

### Requisitos

- Docker Desktop (Mac/Windows) o Minikube (Linux)
- kubectl y helm instalados
- 10 minutos de tu tiempo

### Paso a Paso

```bash
# 1. Clonar repo
git clone https://github.com/tu-org/full-colombiano-infra.git
cd full-colombiano-infra

# 2. Habilitar Kubernetes en Docker Desktop
# Docker Desktop → Settings → Kubernetes → Enable Kubernetes
# O iniciar Minikube:
# minikube start --cpus=4 --memory=8192

# 3. Verificar cluster
kubectl config use-context docker-desktop  # o minikube
kubectl get nodes

# 4. Setup environment local
cd environments/dev
./setup-local-dev.sh

# El script instala:
# - ingress-nginx
# - cert-manager (self-signed para dev)
# - metrics-server

# 5. Desplegar aplicación de prueba
kubectl apply -f ../../examples/hello-world-app.yaml

# 6. Configurar /etc/hosts
echo "127.0.0.1 hello.local.dev" | sudo tee -a /etc/hosts

# 7. Acceder
curl -k https://hello.local.dev  # -k porque es self-signed
```

**¡Listo!** Tienes un cluster Kubernetes local con:
- ✅ Ingress controller (nginx)
- ✅ Métricas (metrics-server)
- ✅ Certificados self-signed (dev)
- ✅ Aplicación de ejemplo funcionando

**Costo mensual**: $0 (usa tu laptop)

## Opción 2: VPS Compartido (Staging + Production)

### Requisitos

- VPS con Ubuntu 22.04+ (mínimo 4 vCPU, 8GB RAM)
- IP pública
- SSH access
- 15 minutos

### Paso a Paso

```bash
cd environments/stg

# Crear configuración
cat > terraform.tfvars <<'EOF'
target_provider = "vps"
vps_host        = "203.0.113.10"  # TU IP VPS
vps_user        = "root"
ssh_private_key_path = "~/.ssh/id_rsa"

k3s_version = "v1.28.5+k3s1"
letsencrypt_email = "tu@email.com"
EOF

# Desplegar k3s
terraform init
terraform apply

# Exportar kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Crear namespaces para staging y production
kubectl create namespace stg-apps
kubectl create namespace prod-apps

# Configurar resource quotas (ver VPS_SHARED_SETUP.md)
# ... aplicar quotas ...

# Configurar DNS
# *.stg.colombiansupply.com → 203.0.113.10
# *.colombiansupply.com → 203.0.113.10

# Desplegar app en staging
kubectl apply -f myapp-staging.yaml  # namespace: stg-apps

# Desplegar app en production
kubectl apply -f myapp-production.yaml  # namespace: prod-apps
```

**Ver guía completa**: `VPS_SHARED_SETUP.md`

**Costo mensual**: ~$20-24 (VPS único para ambos ambientes)

## Opción 3: AWS EKS o GCP GKE (Cuando necesites escalar)

### Requisitos

- Cuenta AWS
- AWS CLI configurado
- Terraform instalado
- 15 minutos

### Paso a Paso

```bash
cd environments/stg
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

Configuración:

```hcl
target_provider = "aws"
aws_region      = "us-east-1"

letsencrypt_email = "tu@email.com"

# Route53 hosted zone (obtener con: aws route53 list-hosted-zones)
aws_route53_zone_arns = ["arn:aws:route53:::hostedzone/ZXXXXX"]

enable_external_dns = true
external_dns_domain_filters = ["example.com"]
```

```bash
terraform init
terraform apply

# Configurar kubectl
aws eks update-kubeconfig \
  --name stg-colombian-cluster \
  --region us-east-1

# Verificar
kubectl get nodes

# Desplegar app
kubectl apply -f ../../examples/hello-world-app.yaml

# external-dns creará el DNS record automáticamente
# Esperar 2-3 minutos y acceder
curl https://hello.example.com
```

**Diferencia clave con VPS**: DNS se configura automáticamente via external-dns.

**Costo mensual**: ~$200-300 (EKS + nodos + NAT)

## Opción 3: GCP GKE (Mejor precio/performance)

Similar a EKS:

```bash
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

```hcl
target_provider = "gcp"
gcp_project_id  = "tu-proyecto-gcp"

letsencrypt_email = "tu@email.com"

enable_external_dns = true
external_dns_domain_filters = ["example.com"]
```

```bash
gcloud auth application-default login

terraform init
terraform apply

gcloud container clusters get-credentials \
  prod-colombian-cluster \
  --region us-central1

kubectl apply -f ../../examples/hello-world-app.yaml
```

**Costo mensual**: ~$150-250 (20-30% más barato que EKS)

## Comandos Útiles

### Ver todo lo que está corriendo

```bash
kubectl get all -A
```

### Ver logs de la plataforma

```bash
kubectl logs -n platform -l app.kubernetes.io/name=ingress-nginx --tail=50
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager --tail=50
```

### Ver certificados

```bash
kubectl get certificate -A
```

### Escalar una aplicación

```bash
kubectl scale deployment hello-world -n demo --replicas=5
```

### Ver métricas

```bash
kubectl top nodes
kubectl top pods -A
```

## Troubleshooting Rápido

### Pods no inician

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Certificado no se emite

```bash
# Usar staging primero para testing
# En el Ingress: cert-manager.io/cluster-issuer: letsencrypt-staging

kubectl describe certificate <cert-name> -n <namespace>
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager
```

### DNS no resuelve

```bash
# VPS: Verifica que el A record apunte a la IP correcta
dig hello.example.com

# AWS/GCP: Verifica external-dns logs
kubectl logs -n platform -l app.kubernetes.io/name=external-dns
```

## Próximos Pasos

1. **Habilitar Monitoring**:
   ```hcl
   enable_monitoring = true
   prometheus_ingress_enabled = true
   grafana_ingress_host = "grafana.example.com"
   ```

2. **Desplegar tu aplicación real**:
   - Copiar `examples/hello-world-app.yaml`
   - Cambiar image, nombre, dominio
   - `kubectl apply -f tu-app.yaml`

3. **Setup CI/CD**:
   - Configurar GitHub Actions (ya incluido en `.github/workflows/`)
   - Configurar ArgoCD para GitOps

4. **Backups**:
   - Instalar Velero (ver RUNBOOK.md)
   - Configurar backup schedule

5. **Migrar a producción**:
   - Ver MIGRATION_GUIDE.md
   - Proceso de VPS → AWS/GCP

## Ayuda

- **Documentación completa**: Ver `README.md`
- **Arquitectura**: Ver `docs/ARCHITECTURE.md`
- **Operaciones**: Ver `docs/RUNBOOK.md`
- **Migraciones**: Ver `docs/MIGRATION_GUIDE.md`

## Comandos para Destruir Todo

**⚠️ CUIDADO: Esto elimina todo**

```bash
cd environments/dev
terraform destroy
# Confirmar: yes
```

Esto elimina:
- Cluster Kubernetes
- Todos los pods y aplicaciones
- Load balancers
- Discos persistentes

Backups en Velero (si configuraste) permanecen en S3/GCS.

