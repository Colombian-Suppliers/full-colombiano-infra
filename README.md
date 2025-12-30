# Colombian Supply - Infrastructure as Code

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-844FBA?logo=terraform)](https://www.terraform.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Infraestructura portable y agnóstica de proveedor para Colombian Supply, diseñada para maximizar la flexibilidad entre VPS (k3s), AWS (EKS) y GCP (GKE) manteniendo una capa de runtime común basada en Helm/Kubernetes.

> 📚 **Documentation**: Detailed documentation has been moved to the [full-colombiano-docs](https://github.com/Colombian-Suppliers/full-colombiano-docs) repository. See the [Documentation Index](https://github.com/Colombian-Suppliers/full-colombiano-docs/blob/main/docs/DOCUMENTATION_INDEX.md) for all available documentation. Deployment guides, SSL setup, and CI/CD documentation are available in the `docs/06-devops-e-infraestructura/` directory.

## 🎯 Filosofía de Diseño

Este repositorio implementa una **arquitectura de 2 capas**:

1. **Capa de Infraestructura** (Provider-specific): Módulos intercambiables por proveedor
   - `modules/infra_vps_k3s` - k3s en VPS existente o aprovisionado
   - `modules/infra_aws_eks` - EKS + VPC + NodeGroups + IRSA
   - `modules/infra_gcp_gke` - GKE + VPC + NodePool + Workload Identity

2. **Capa de Runtime/Platform** (Provider-agnostic): Componentes comunes vía Helm
   - Ingress Controller (Traefik para k3s, Nginx para cloud)
   - cert-manager + LetsEncrypt (staging/prod)
   - metrics-server
   - external-dns (feature flag)
   - kube-prometheus-stack (feature flag)

```
┌──────────────────────────────────────────────────────┐
│          Applications (Deployed via ArgoCD)          │
├──────────────────────────────────────────────────────┤
│  Runtime Platform (Helm - Provider Agnostic)         │
│  ├─ Ingress Controller                               │
│  ├─ cert-manager + ClusterIssuers                    │
│  ├─ external-dns (optional)                          │
│  ├─ metrics-server                                   │
│  └─ kube-prometheus (optional)                       │
├──────────────────────────────────────────────────────┤
│  Infrastructure Layer (Provider-Specific Modules)    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │ VPS + k3s  │  │ AWS + EKS  │  │ GCP + GKE  │    │
│  └────────────┘  └────────────┘  └────────────┘    │
└──────────────────────────────────────────────────────┘
```

## 🚀 Quickstart: Desarrollo Local (Dev)

### Opción 1: Docker Desktop (Recomendado para Mac/Windows)

```bash
# 1. Instalar Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop

# 2. Habilitar Kubernetes en Docker Desktop
# Settings → Kubernetes → Enable Kubernetes

# 3. Verificar
kubectl config use-context docker-desktop
kubectl get nodes
```

### Opción 2: Minikube (Alternativa)

```bash
# Instalar minikube
brew install minikube

# Iniciar
minikube start --cpus=4 --memory=8192

# Verificar
kubectl get nodes
```

### Desplegar Platform en Dev Local

```bash
cd environments/dev

# dev no usa Terraform, es local
# Instalar platform components directamente
kubectl apply -f local-dev-setup.yaml

# O usar Helm directamente
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx -n platform --create-namespace
```

## 🌐 Quickstart: VPS Compartido (Staging + Production)

### Prerrequisitos

- VPS con Ubuntu 22.04+ (mínimo 4 vCPU, 8GB RAM para ambos ambientes)
- SSH access al VPS
- Terraform >= 1.6

### Paso 1: Desplegar Infraestructura Base (Una sola vez)

```bash
cd environments/stg
cp terraform.tfvars.example terraform.tfvars
```

Editar `terraform.tfvars`:

```hcl
target_provider = "vps"
vps_host        = "203.0.113.10"  # TU IP VPS
vps_user        = "root"
ssh_private_key_path = "~/.ssh/id_rsa"

# Staging configuration
environment     = "stg"
domain_name     = "stg.colombiansupply.com"
letsencrypt_email = "devops@colombiansupply.com"
```

### Paso 2: Desplegar Infraestructura

```bash
# Inicializar Terraform
make init ENV=dev

# Revisar plan
make plan ENV=dev

# Aplicar (instala k3s + platform components)
make apply ENV=dev
```

### Paso 3: Verificar Cluster

```bash
# Exportar kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Verificar nodos
kubectl get nodes

# Verificar platform components
kubectl get pods -n platform

# Verificar ingress
kubectl get ingress -A
```

### Paso 4: Desplegar Primera Aplicación

```bash
kubectl create namespace apps
kubectl apply -f examples/hello-world-ingress.yaml
```

Acceder via `https://hello.dev.colombiansupply.com` (después de configurar DNS).

## 🌐 Migración a AWS EKS

### Paso 1: Cambiar Provider

```bash
cd environments/stg
```

Editar `terraform.tfvars`:

```hcl
target_provider = "aws"
aws_region      = "us-east-1"
domain_name     = "stg.colombiansupply.com"
environment     = "stg"

# EKS specific
eks_cluster_version = "1.28"
eks_instance_types  = ["t3.medium"]
eks_desired_size    = 2
eks_min_size        = 1
eks_max_size        = 4
```

### Paso 2: Configurar AWS Credentials

```bash
export AWS_PROFILE=colombian-supply
# o
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### Paso 3: Desplegar

```bash
make init ENV=stg
make plan ENV=stg
make apply ENV=stg

# Configurar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name stg-colombian-cluster
```

**La capa de runtime es idéntica** - cert-manager, ingress, external-dns se instalan automáticamente con la misma configuración.

## ☁️ Migración a GCP GKE

```bash
cd environments/prod
```

Editar `terraform.tfvars`:

```hcl
target_provider = "gcp"
gcp_project_id  = "colombian-supply-prod"
gcp_region      = "us-central1"
domain_name     = "colombiansupply.com"
environment     = "prod"

# GKE specific
gke_cluster_version = "1.28"
gke_machine_type    = "n1-standard-2"
gke_node_count      = 3
```

```bash
gcloud auth application-default login
make init ENV=prod
make apply ENV=prod

gcloud container clusters get-credentials prod-colombian-cluster --region us-central1
```

## 📂 Estructura del Repositorio

```
.
├── modules/
│   ├── infra_vps_k3s/      # VPS + k3s provisioning
│   ├── infra_aws_eks/      # AWS EKS + VPC + IRSA
│   ├── infra_gcp_gke/      # GCP GKE + VPC + Workload Identity
│   └── runtime_platform/   # Helm charts (provider-agnostic)
├── environments/
│   ├── dev/                # Local Development (Docker Desktop/Minikube)
│   ├── stg/                # Staging (VPS compartido)
│   └── prod/               # Production (VPS compartido)
├── docs/
│   ├── ARCHITECTURE.md     # Detailed architecture
│   ├── RUNBOOK.md          # Operations guide
│   └── MIGRATION_GUIDE.md  # Provider migration steps
├── .github/
│   └── workflows/          # CI/CD pipelines
├── examples/               # Sample deployments
├── scripts/                # Helper scripts
├── Makefile                # Common commands
├── .pre-commit-config.yaml
└── README.md
```

## 🏗️ Arquitectura de Ambientes

**Local Development (dev)**:
- Docker Desktop / Minikube / k3d en tu laptop
- Para desarrollo y testing local
- Sin costo de infraestructura

**VPS Compartido (stg + prod)**:
- Mismo VPS físico con k3s
- Separación por namespaces y resource quotas
- Ingress con subdomains diferentes
- Costo único del VPS (~$20/mes)

## 🛠 Comandos Disponibles (Makefile)

```bash
make init ENV=dev           # Inicializar Terraform
make validate ENV=dev       # Validar configuración
make plan ENV=dev          # Ver plan de cambios
make apply ENV=dev         # Aplicar cambios
make destroy ENV=dev       # Destruir infraestructura
make fmt                   # Formatear código Terraform
make lint                  # Ejecutar tflint
make security-scan         # Ejecutar tfsec/checkov
make docs                  # Generar documentación (terraform-docs)
make pre-commit-install    # Instalar pre-commit hooks
```

## 🔒 Seguridad

### State Management

**Producción**: Usar remote backend

Para AWS:
```hcl
# environments/prod/backend.tf
terraform {
  backend "s3" {
    bucket         = "colombian-supply-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

Para GCP:
```hcl
terraform {
  backend "gcs" {
    bucket = "colombian-supply-tfstate"
    prefix = "prod"
  }
}
```

**Desarrollo**: Local state es aceptable (incluido en `.gitignore`)

### Secrets Management

**NO hardcodear secrets**. Opciones:

1. **Variables de entorno**:
   ```bash
   export TF_VAR_cloudflare_api_token="..."
   ```

2. **SOPS + AGE** (recomendado):
   ```bash
   sops -d secrets.enc.yaml | terraform apply -var-file=-
   ```

3. **Terraform Cloud** (enterprise):
   Variables sensibles encriptadas en el workspace.

### Network Security

- **VPS**: Firewall configurado automáticamente (ports 22, 80, 443)
- **AWS**: Security Groups mínimos (ingress controller, API server)
- **GCP**: Firewall rules automáticos para GKE

### DoD (Definition of Done) para Cambios IaC

- [ ] Código formateado (`terraform fmt`)
- [ ] Validación exitosa (`terraform validate`)
- [ ] Linting sin errores (`tflint`)
- [ ] Security scan sin issues críticos (`tfsec`)
- [ ] Plan revisado y aprobado
- [ ] Documentación actualizada (`terraform-docs`)
- [ ] Pre-commit hooks pasan
- [ ] PR aprobado por arquitecto/staff engineer

## 🧪 Testing

```bash
# Validar sintaxis
make validate ENV=dev

# Dry-run completo
make plan ENV=dev

# Test en ambiente efímero (opcional - requiere configuración)
cd test
go test -v -timeout 30m
```

## 📚 Documentación

- [Arquitectura Detallada](docs/ARCHITECTURE.md)
- [Runbook Operacional](docs/RUNBOOK.md)
- [Guía de Migración entre Providers](docs/MIGRATION_GUIDE.md)
- [Decisiones de Arquitectura (ADRs)](docs/adr/)

## 🤝 Contribuir

1. Crear branch desde `main`
2. Hacer cambios
3. Ejecutar `make pre-commit-install && pre-commit run --all-files`
4. Crear PR
5. CI/CD ejecutará validaciones automáticas
6. Esperar revisión y aprobación
7. Merge (apply manual por environment)

## 📋 Requisitos de Sistema

| Componente | Versión Mínima | Recomendada |
|------------|----------------|-------------|
| Terraform  | 1.6.0          | 1.7+        |
| kubectl    | 1.28.0         | 1.29+       |
| Helm       | 3.12.0         | 3.14+       |
| k3s        | 1.28.0         | 1.29+       |
| AWS CLI    | 2.13.0         | 2.15+       |
| gcloud CLI | 450.0.0        | 460+        |

## 🐛 Troubleshooting

### k3s no inicia en VPS

```bash
# SSH al VPS
ssh user@vps-ip
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### cert-manager no emite certificados

```bash
kubectl get certificaterequests -A
kubectl describe clusterissuer letsencrypt-prod
# Verificar external-dns si está habilitado
kubectl logs -n platform -l app.kubernetes.io/name=external-dns
```

### EKS nodes no se unen al cluster

```bash
# Verificar IAM roles
aws eks describe-cluster --name <cluster-name> --query cluster.roleArn
# Verificar security groups
kubectl get nodes
```

Ver [RUNBOOK.md](docs/RUNBOOK.md) para más escenarios.

## 📄 Licencia

MIT License - ver [LICENSE](LICENSE)

## 👥 Equipo

Mantenido por el equipo de Platform Engineering de Colombian Supply.

Para soporte: devops@colombiansupply.com

