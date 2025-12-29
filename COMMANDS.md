# Comandos Exactos para Despliegue

Guía paso a paso con comandos copy-paste para cada escenario.

## 📦 Escenario 1: VPS con k3s (Desarrollo)

### Setup Inicial

```bash
# 1. Clonar repositorio
git clone <repo-url>
cd full-colombiano-infra

# 2. Instalar herramientas (MacOS)
make install-tools

# 3. Verificar instalación
terraform version  # Debe ser >= 1.6.0
kubectl version --client
helm version
```

### Configuración

```bash
# 4. Ir a environment dev
cd environments/dev

# 5. Copiar template de configuración
cp terraform.tfvars.example terraform.tfvars

# 6. Editar configuración (reemplazar valores)
cat > terraform.tfvars <<'EOF'
target_provider = "vps"

# VPS Configuration
vps_host             = "203.0.113.10"  # CAMBIAR POR TU IP
vps_user             = "root"
ssh_private_key_path = "~/.ssh/id_rsa"
k3s_version          = "v1.28.5+k3s1"

# Platform Configuration
letsencrypt_email = "devops@colombiansupply.com"  # CAMBIAR

# Optional: External DNS (Cloudflare)
enable_external_dns = false
EOF
```

### Despliegue

```bash
# 7. Inicializar Terraform
terraform init

# 8. Revisar plan
terraform plan

# 9. Aplicar (confirmar con 'yes')
terraform apply

# Tiempo estimado: 5-10 minutos
```

### Verificación

```bash
# 10. Exportar kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
echo "export KUBECONFIG=$(terraform output -raw kubeconfig_path)" >> ~/.bashrc

# 11. Verificar cluster
kubectl get nodes
# Expected: 1 node Ready

kubectl get pods -n platform
# Expected: ingress-nginx, cert-manager, metrics-server pods Running

# 12. Obtener IP del ingress
kubectl get svc -n platform ingress-nginx-controller
# Anotar EXTERNAL-IP (debería ser la IP del VPS)

# 13. Test interno
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://ingress-nginx-controller.platform.svc.cluster.local
```

### Desplegar Aplicación de Ejemplo

```bash
# 14. Aplicar ejemplo
kubectl apply -f ../../examples/hello-world-app.yaml

# 15. Verificar deployment
kubectl get all -n demo
kubectl get certificate -n demo

# 16. Configurar DNS manualmente
# En tu proveedor DNS (Cloudflare, etc.):
# Crear A record: hello.example.com → IP_DEL_VPS

# 17. Esperar 2-3 minutos para certificado
kubectl get certificate -n demo -w
# Esperar hasta que READY = True

# 18. Acceder
curl https://hello.example.com
```

### Troubleshooting Rápido

```bash
# Ver logs de ingress
kubectl logs -n platform -l app.kubernetes.io/name=ingress-nginx --tail=50

# Ver logs de cert-manager
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager --tail=50

# Ver challenges (si certificado no se emite)
kubectl get challenges -A
kubectl describe challenge <name> -n demo

# SSH al VPS si es necesario
ssh root@203.0.113.10
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Limpieza

```bash
# Destruir todo (CUIDADO: irreversible)
terraform destroy
```

---

## ☁️ Escenario 2: AWS EKS (Staging/Producción)

### Prerrequisitos AWS

```bash
# 1. Instalar AWS CLI (si no lo tienes)
brew install awscli

# 2. Configurar credentials
aws configure
# Ingresar Access Key ID, Secret Access Key, region (us-east-1), output format (json)

# 3. Verificar acceso
aws sts get-caller-identity

# 4. Crear Route53 hosted zone (si no existe)
aws route53 create-hosted-zone \
  --name stg.colombiansupply.com \
  --caller-reference $(date +%s)

# 5. Anotar el Hosted Zone ID
aws route53 list-hosted-zones | grep -A 1 "stg.colombiansupply.com"
# Anotar: /hostedzone/ZXXXXXXXXXXXXX
```

### Configuración

```bash
cd environments/stg

cp terraform.tfvars.example terraform.tfvars

# Editar con tus valores
cat > terraform.tfvars <<'EOF'
target_provider = "aws"

# AWS Configuration
aws_region      = "us-east-1"
aws_vpc_cidr    = "10.1.0.0/16"
aws_availability_zones = ["us-east-1a", "us-east-1b"]
aws_single_nat_gateway = false  # HA

# EKS Configuration
eks_cluster_version = "1.28"
eks_instance_types  = ["t3.medium"]
eks_capacity_type   = "ON_DEMAND"
eks_desired_size    = 2
eks_min_size        = 2
eks_max_size        = 4

# Route53 (CAMBIAR por tu zone ID)
aws_route53_zone_arns = ["arn:aws:route53:::hostedzone/ZXXXXXXXXXXXXX"]

# Platform
letsencrypt_email      = "devops@colombiansupply.com"
cert_manager_use_dns01 = true

# External DNS
enable_external_dns         = true
external_dns_domain_filters = ["stg.colombiansupply.com"]

# Monitoring
enable_monitoring          = true
prometheus_ingress_enabled = true
prometheus_ingress_host    = "prometheus.stg.colombiansupply.com"
grafana_ingress_host       = "grafana.stg.colombiansupply.com"
EOF
```

### Despliegue

```bash
# Inicializar
terraform init

# Plan
terraform plan

# Apply (confirmar 'yes')
terraform apply
# Tiempo estimado: 15-20 minutos
```

### Verificación

```bash
# Configurar kubectl (método automático)
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# O método AWS CLI
aws eks update-kubeconfig \
  --name stg-colombian-cluster \
  --region us-east-1

# Verificar
kubectl get nodes
kubectl get pods -n platform

# Obtener hostname del NLB
kubectl get svc -n platform ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Output: aXXXXXXXXXXXXXXXXXXXXXXXXXXXX-123456789.us-east-1.elb.amazonaws.com
```

### Desplegar Aplicación

```bash
# Aplicar ejemplo
kubectl apply -f ../../examples/hello-world-app.yaml

# external-dns creará el record automáticamente
# Verificar en Route53
aws route53 list-resource-record-sets \
  --hosted-zone-id ZXXXXXXXXXXXXX \
  | grep hello

# Esperar certificado (1-2 minutos)
kubectl get certificate -n demo -w

# Acceder
curl https://hello.stg.colombiansupply.com
```

### Acceder a Grafana

```bash
# Via ingress (si configuraste)
open https://grafana.stg.colombiansupply.com
# Usuario: admin
# Password: admin (cambiar en primer login)

# O via port-forward
kubectl port-forward -n platform svc/prometheus-grafana 3000:80
open http://localhost:3000
```

### Limpieza

```bash
terraform destroy
# Confirmar: yes
# Tiempo: ~10 minutos
```

---

## 🌐 Escenario 3: GCP GKE (Producción)

### Prerrequisitos GCP

```bash
# 1. Instalar gcloud CLI
brew install google-cloud-sdk

# 2. Autenticar
gcloud auth login
gcloud auth application-default login

# 3. Crear proyecto (si no existe)
gcloud projects create colombian-supply-prod --name="Colombian Supply Production"

# 4. Configurar proyecto
gcloud config set project colombian-supply-prod

# 5. Habilitar APIs necesarias
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com
gcloud services enable servicenetworking.googleapis.com

# 6. Verificar
gcloud services list --enabled
```

### Configuración

```bash
cd environments/prod

cp terraform.tfvars.example terraform.tfvars

cat > terraform.tfvars <<'EOF'
target_provider = "gcp"

# GCP Configuration
gcp_project_id  = "colombian-supply-prod"
gcp_region      = "us-central1"

# GKE Configuration
gke_cluster_version  = "1.28"
gke_regional_cluster = true  # Multi-zone HA
gke_machine_type     = "n1-standard-2"
gke_preemptible_nodes = false
gke_min_node_count   = 3
gke_max_node_count   = 10

# Network
gke_enable_private_nodes    = true
gke_enable_private_endpoint = false  # Permitir acceso externo

# Platform
letsencrypt_email      = "devops@colombiansupply.com"
cert_manager_use_dns01 = true

# External DNS
enable_external_dns         = true
external_dns_domain_filters = ["colombiansupply.com"]

# Monitoring
enable_monitoring          = true
prometheus_ingress_enabled = true
prometheus_ingress_host    = "prometheus.colombiansupply.com"
grafana_ingress_host       = "grafana.colombiansupply.com"
EOF
```

### Despliegue

```bash
terraform init
terraform plan
terraform apply
# Tiempo: 10-15 minutos
```

### Verificación

```bash
# Configurar kubectl
gcloud container clusters get-credentials \
  prod-colombian-cluster \
  --region us-central1 \
  --project colombian-supply-prod

# Verificar
kubectl get nodes
kubectl get pods -n platform

# Obtener IP del Load Balancer
kubectl get svc -n platform ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Desplegar Aplicación

```bash
kubectl apply -f ../../examples/hello-world-app.yaml

# Verificar external-dns
kubectl logs -n platform -l app.kubernetes.io/name=external-dns --tail=50

# Verificar en Cloud DNS
gcloud dns record-sets list --zone=<zone-name>

# Acceder
curl https://hello.colombiansupply.com
```

---

## 🔄 Migración VPS → AWS

Ver guía completa en `docs/MIGRATION_GUIDE.md`. Resumen de comandos:

```bash
# 1. En VPS: Instalar Velero
velero install \
  --provider aws \
  --bucket colombian-supply-backups \
  --backup-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# 2. Crear backup
velero backup create pre-migration --wait

# 3. Desplegar EKS (ver Escenario 2)

# 4. Instalar Velero en EKS (mismo bucket)
velero install \
  --provider aws \
  --bucket colombian-supply-backups \
  --backup-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# 5. Restore
velero restore create eks-migration --from-backup pre-migration

# 6. Verificar
kubectl get all -n apps

# 7. Cambiar DNS (si no usas external-dns)
# Cambiar A record de VPS IP a NLB hostname

# 8. Después de 7 días, destruir VPS
cd environments/dev
terraform destroy
```

---

## 🧪 Testing Local (Sin Despliegue Real)

Para validar sintaxis sin crear recursos:

```bash
cd environments/dev

# Validar
terraform init -backend=false
terraform validate

# Plan sin ejecutar
terraform plan

# Linting
tflint

# Security scan
tfsec .
```

---

## 📊 Comandos de Monitoreo

```bash
# Ver uso de recursos
kubectl top nodes
kubectl top pods -A

# Ver eventos recientes
kubectl get events --sort-by=.lastTimestamp

# Ver logs de aplicaciones
kubectl logs -n demo deployment/hello-world --tail=100 -f

# Ver métricas en Prometheus
kubectl port-forward -n platform svc/prometheus-kube-prometheus-prometheus 9090:9090
# Abrir http://localhost:9090

# Ver dashboards en Grafana
kubectl port-forward -n platform svc/prometheus-grafana 3000:80
# Abrir http://localhost:3000
```

---

## 🚨 Comandos de Emergencia

```bash
# Rollback deployment
kubectl rollout undo deployment/hello-world -n demo

# Reiniciar deployment
kubectl rollout restart deployment/hello-world -n demo

# Ver estado de rollout
kubectl rollout status deployment/hello-world -n demo

# Escalar rápidamente
kubectl scale deployment/hello-world -n demo --replicas=10

# Drenar nodo (antes de mantenimiento)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Cordon nodo (prevenir nuevos pods)
kubectl cordon <node-name>

# Uncordon nodo
kubectl uncordon <node-name>
```

---

## 📝 Comandos de Administración Terraform

```bash
# Ver state
terraform state list

# Ver output específico
terraform output kubeconfig_path

# Refresh state
terraform refresh

# Import recurso existente
terraform import module.infra_aws.aws_eks_cluster.main <cluster-name>

# Taint resource (forzar recreación)
terraform taint module.infra_vps.null_resource.install_k3s

# Ver workspace actual
terraform workspace show

# Crear nuevo workspace
terraform workspace new staging

# Cambiar workspace
terraform workspace select production
```

---

## 🎓 Comandos para Aprender

```bash
# Ver todos los recursos
kubectl api-resources

# Explicar un recurso
kubectl explain pod.spec.containers

# Ver documentación de field
kubectl explain deployment.spec.replicas

# Modo interactivo (debugging)
kubectl run debug --image=alpine --rm -it --restart=Never -- sh

# Ver configuración actual de kubectl
kubectl config view

# Ver contextos disponibles
kubectl config get-contexts

# Cambiar contexto
kubectl config use-context <context-name>
```

---

**Pro Tip**: Guarda estos comandos en un script o alias para uso frecuente.

Ejemplo de alias útiles:

```bash
# Agregar a ~/.bashrc o ~/.zshrc
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
alias kctx='kubectl config use-context'
alias tf='terraform'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
```

