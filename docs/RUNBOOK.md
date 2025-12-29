# Operations Runbook

Guía operacional para el equipo de DevOps/Platform Engineering de Colombian Supply.

## 📋 Pre-requisitos

### Herramientas Locales

```bash
# Instalar herramientas (MacOS)
make install-tools

# Verificar versiones
terraform version  # >= 1.6.0
kubectl version --client  # >= 1.28.0
helm version  # >= 3.12.0
aws --version  # >= 2.13.0 (si usas AWS)
gcloud version  # >= 450.0 (si usas GCP)
```

### Accesos Necesarios

- [x] Acceso SSH a VPS (si aplica)
- [x] AWS credentials con permisos EKS (si aplica)
- [x] GCP credentials con permisos GKE (si aplica)
- [x] GitHub access token (para CI/CD)
- [x] Cloudflare API token (si usas external-dns en VPS)

## 🚀 Procedimientos de Despliegue

### Desplegar Nuevo Ambiente (VPS)

**Caso de uso**: Levantar ambiente de desarrollo desde cero

```bash
# 1. Navegar al environment
cd environments/dev

# 2. Crear terraform.tfvars desde el ejemplo
cp terraform.tfvars.example terraform.tfvars

# 3. Editar valores
vim terraform.tfvars
# Configurar:
# - target_provider = "vps"
# - vps_host = "TU_IP_AQUI"
# - letsencrypt_email = "tu@email.com"

# 4. Inicializar Terraform
terraform init

# 5. Revisar plan
terraform plan

# 6. Aplicar
terraform apply

# 7. Exportar kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# 8. Verificar cluster
kubectl get nodes
kubectl get pods -n platform
kubectl get pods -n apps

# 9. Obtener IP del ingress
kubectl get svc -n platform ingress-nginx-controller

# 10. Configurar DNS
# Apuntar tus dominios al IP del paso 9
```

**Tiempo estimado**: 5-10 minutos

### Desplegar en AWS EKS

```bash
cd environments/stg

# 1. Configurar AWS credentials
export AWS_PROFILE=colombian-supply
# O
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# 2. Crear terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
# Configurar target_provider = "aws"

# 3. Terraform
terraform init
terraform plan
terraform apply

# 4. Configurar kubectl (método 1: automático)
export KUBECONFIG=$(terraform output -raw kubeconfig_path)

# Método 2: usando AWS CLI
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region us-east-1

# 5. Verificar
kubectl get nodes
kubectl get svc -n platform ingress-nginx-controller

# 6. Obtener hostname del NLB
kubectl get svc -n platform ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# 7. Configurar DNS
# CNAME: *.example.com -> hostname-del-nlb
```

**Tiempo estimado**: 15-20 minutos

### Desplegar en GCP GKE

```bash
cd environments/prod

# 1. Autenticar con GCP
gcloud auth login
gcloud auth application-default login

# 2. Configurar proyecto
gcloud config set project colombian-supply-prod

# 3. Habilitar APIs necesarias
gcloud services enable container.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable dns.googleapis.com

# 4. Crear terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
# Configurar target_provider = "gcp"

# 5. Terraform
terraform init
terraform plan
terraform apply

# 6. Configurar kubectl
gcloud container clusters get-credentials \
  $(terraform output -raw cluster_name) \
  --region us-central1 \
  --project colombian-supply-prod

# 7. Verificar
kubectl get nodes
kubectl get svc -n platform

# 8. Obtener IP del Load Balancer
kubectl get svc -n platform ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 9. Configurar DNS (external-dns lo hace automáticamente si está habilitado)
```

**Tiempo estimado**: 10-15 minutos

## 🔄 Operaciones Comunes

### Actualizar Versión de Kubernetes

#### VPS/k3s

```bash
cd environments/dev

# Editar terraform.tfvars
vim terraform.tfvars
# k3s_version = "v1.29.0+k3s1"  # Nueva versión

# Aplicar
terraform apply

# k3s se actualizará automáticamente
# Verificar
kubectl get nodes
```

#### EKS

```bash
cd environments/stg

# 1. Actualizar versión del cluster
vim terraform.tfvars
# eks_cluster_version = "1.29"

# 2. Aplicar (actualiza control plane primero)
terraform apply

# 3. Los nodos se actualizan automáticamente por el managed node group
# Monitorear el progreso
kubectl get nodes -w

# 4. Verificar addons
kubectl get pods -n kube-system
```

**Nota**: EKS solo permite actualizar una versión minor a la vez (1.28 → 1.29, no 1.28 → 1.30).

#### GKE

Similar a EKS, pero GKE es más rápido:

```bash
cd environments/prod
vim terraform.tfvars
# gke_cluster_version = "1.29"
terraform apply
```

### Escalar Nodos

#### Escalado Manual

```bash
cd environments/<env>

# Editar terraform.tfvars
vim terraform.tfvars
# EKS: eks_desired_size = 5  # Era 3
# GKE: gke_min_node_count = 3, gke_max_node_count = 10

terraform apply

# Verificar nuevos nodos
kubectl get nodes -w
```

#### Escalado Automático (Cluster Autoscaler)

Ya está configurado si `enable_autoscaling = true` en GKE.

Para EKS, instalar Cluster Autoscaler:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

# Configurar para tu cluster
kubectl edit deployment cluster-autoscaler -n kube-system
# Agregar flag: --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster-name>

# Monitorear logs
kubectl logs -f deployment/cluster-autoscaler -n kube-system
```

### Renovar Certificados SSL

**Los certificados se renuevan automáticamente por cert-manager** (60 días antes del vencimiento).

#### Verificar Estado de Certificados

```bash
# Listar certificados
kubectl get certificates -A

# Ver detalles de un certificado
kubectl describe certificate <nombre> -n <namespace>

# Ver fechas de expiración
kubectl get secret <nombre>-tls -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

#### Forzar Renovación Manual

```bash
# Eliminar el secret (cert-manager lo recreará)
kubectl delete secret <nombre>-tls -n <namespace>

# O eliminar y recrear el Certificate
kubectl delete certificate <nombre> -n <namespace>
kubectl apply -f certificate.yaml

# Monitorear
kubectl get certificaterequest -n <namespace> -w
```

#### Troubleshooting: Certificado No Se Emite

```bash
# 1. Verificar ClusterIssuer
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod

# 2. Verificar Certificate
kubectl describe certificate <nombre> -n <namespace>

# 3. Verificar CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <nombre> -n <namespace>

# 4. Verificar Challenge (si usa HTTP01)
kubectl get challenges -A
kubectl describe challenge <nombre> -n <namespace>

# 5. Ver logs de cert-manager
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager --tail=100
```

**Causas comunes**:
- DNS no apunta al ingress IP (HTTP01)
- Route53/Cloud DNS permisos incorrectos (DNS01)
- Rate limit de Let's Encrypt (usa staging para testing)

### Rotar Tokens/Secrets

#### Rotar Cloudflare API Token (VPS)

```bash
# 1. Generar nuevo token en Cloudflare

# 2. Actualizar secret
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="NUEVO_TOKEN" \
  -n platform \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Reiniciar external-dns
kubectl rollout restart deployment external-dns -n platform

# 4. Verificar
kubectl logs -n platform -l app.kubernetes.io/name=external-dns --tail=50
```

#### Rotar Kubeconfig

```bash
cd environments/<env>

# VPS: Regenerar kubeconfig
terraform taint null_resource.fetch_kubeconfig
terraform apply

# EKS: Regenerar token
aws eks update-kubeconfig --name <cluster-name> --region <region>

# GKE: Regenerar token
gcloud container clusters get-credentials <cluster-name> --region <region>

# Verificar
kubectl get nodes
```

### Backup y Restore

#### Backup con Velero

**Instalación inicial**:

```bash
# AWS
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket colombian-supply-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# GCP
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.8.0 \
  --bucket colombian-supply-backups \
  --secret-file ./credentials-velero
```

**Backup manual**:

```bash
# Backup completo del cluster
velero backup create full-backup-$(date +%Y%m%d)

# Backup de un namespace específico
velero backup create apps-backup --include-namespaces apps

# Verificar backup
velero backup describe full-backup-20240101
velero backup logs full-backup-20240101
```

**Backup automático (schedule)**:

```bash
# Backup diario a las 2 AM
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --ttl 720h0m0s  # 30 días

# Verificar schedules
velero schedule get
```

**Restore**:

```bash
# Listar backups disponibles
velero backup get

# Restore completo
velero restore create --from-backup full-backup-20240101

# Restore solo un namespace
velero restore create --from-backup full-backup-20240101 \
  --include-namespaces apps

# Verificar restore
velero restore describe <restore-name>
velero restore logs <restore-name>
```

#### Backup de Terraform State

**S3 (AWS)**:

```bash
# Verificar versionado habilitado
aws s3api get-bucket-versioning --bucket colombian-supply-tfstate

# Listar versiones
aws s3api list-object-versions \
  --bucket colombian-supply-tfstate \
  --prefix prod/terraform.tfstate

# Restaurar versión anterior
aws s3api get-object \
  --bucket colombian-supply-tfstate \
  --key prod/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.backup
```

**GCS (GCP)**:

```bash
# Listar versiones
gsutil ls -a gs://colombian-supply-tfstate/prod/

# Restaurar versión
gsutil cp gs://colombian-supply-tfstate/prod/#<generation> \
  terraform.tfstate.backup
```

### Monitoreo y Alertas

#### Acceder a Grafana

```bash
# Si ingress habilitado
open https://grafana.example.com

# Sin ingress (port-forward)
kubectl port-forward -n platform svc/prometheus-grafana 3000:80
open http://localhost:3000
# Usuario: admin
# Password: admin (cambiar en primera conexión)
```

#### Acceder a Prometheus

```bash
# Port-forward
kubectl port-forward -n platform svc/prometheus-kube-prometheus-prometheus 9090:9090
open http://localhost:9090
```

#### Queries Útiles (PromQL)

```promql
# CPU usage por node
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage por node
100 * (1 - ((node_memory_MemAvailable_bytes) / (node_memory_MemTotal_bytes)))

# Pods en estado CrashLoopBackOff
kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}

# Request rate por ingress
rate(nginx_ingress_controller_requests[5m])

# P95 response time
histogram_quantile(0.95, rate(nginx_ingress_controller_request_duration_seconds_bucket[5m]))
```

#### Configurar Alertmanager

```bash
# Editar configuración
kubectl edit secret alertmanager-prometheus-kube-prometheus-alertmanager -n platform

# Ejemplo de configuración (base64 encoded)
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'slack'

receivers:
- name: 'slack'
  slack_configs:
  - channel: '#alerts'
    send_resolved: true

# Aplicar cambios
kubectl delete pod -n platform -l app.kubernetes.io/name=alertmanager
```

### Ver Logs

#### Logs de Platform Components

```bash
# nginx-ingress
kubectl logs -n platform -l app.kubernetes.io/name=ingress-nginx --tail=100 -f

# cert-manager
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager --tail=100 -f

# external-dns
kubectl logs -n platform -l app.kubernetes.io/name=external-dns --tail=100 -f

# metrics-server
kubectl logs -n platform -l app.kubernetes.io/name=metrics-server --tail=100 -f
```

#### Logs de Aplicaciones

```bash
# Logs de un deployment
kubectl logs -n apps deployment/myapp --tail=100 -f

# Logs de todos los pods con un label
kubectl logs -n apps -l app=myapp --tail=100 -f --max-log-requests=10

# Logs anteriores (si el pod crasheó)
kubectl logs -n apps <pod-name> --previous
```

#### Logs Agregados con Stern

```bash
# Instalar stern
brew install stern

# Ver logs de múltiples pods
stern -n apps myapp

# Con filter
stern -n apps myapp --tail 50 --since 15m
```

## 🚨 Troubleshooting

### Pods en CrashLoopBackOff

```bash
# 1. Ver el pod
kubectl get pods -n <namespace>

# 2. Describir el pod
kubectl describe pod <pod-name> -n <namespace>
# Buscar: Events, Last State

# 3. Ver logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 4. Verificar recursos
kubectl top pod <pod-name> -n <namespace>

# 5. Verificar imagen
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[0].image}'
```

**Causas comunes**:
- OOMKilled: Aumentar memory limits
- ImagePullBackOff: Verificar nombre de imagen y acceso al registry
- Liveness probe failing: Revisar configuración del probe

### Nodes NotReady

```bash
# 1. Ver estado de nodes
kubectl get nodes

# 2. Describir el node
kubectl describe node <node-name>

# 3. Ver logs del kubelet (si tienes acceso al node)
# VPS:
ssh user@vps
sudo journalctl -u k3s -f

# EKS/GKE: Ver logs en CloudWatch/Cloud Logging

# 4. Verificar recursos del node
kubectl top node <node-name>
```

**Soluciones**:
- Disk pressure: Limpiar imágenes viejas `kubectl delete pod <pod>` o `docker system prune`
- Memory pressure: Escalar cluster
- Network issues: Verificar security groups/firewall

### Ingress No Funciona

```bash
# 1. Verificar ingress controller
kubectl get pods -n platform -l app.kubernetes.io/name=ingress-nginx

# 2. Ver logs
kubectl logs -n platform -l app.kubernetes.io/name=ingress-nginx --tail=100

# 3. Verificar service
kubectl get svc -n platform ingress-nginx-controller

# 4. Verificar ingress
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# 5. Verificar backend service
kubectl get svc <service-name> -n <namespace>
kubectl get endpoints <service-name> -n <namespace>

# 6. Test directo al pod
kubectl port-forward -n <namespace> pod/<pod-name> 8080:8080
curl localhost:8080
```

### Performance Issues

```bash
# 1. Ver resource usage
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# 2. Identificar pods sin resource requests/limits
kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.requests == null) | .metadata.name'

# 3. Ver HPA status
kubectl get hpa -A

# 4. Ver PDB (PodDisruptionBudgets)
kubectl get pdb -A

# 5. Ver métricas de Prometheus
# Query: container_cpu_usage_seconds_total
# Query: container_memory_working_set_bytes
```

## 🔥 Disaster Recovery

### Escenario 1: Cluster Completamente Caído

**VPS**:

```bash
# 1. Intentar reiniciar k3s
ssh user@vps
sudo systemctl restart k3s
sudo systemctl status k3s

# 2. Si no funciona, reinstalar desde Terraform
cd environments/dev
terraform destroy -target=module.infra_vps
terraform apply

# 3. Restore desde backup
velero restore create --from-backup latest
```

**EKS/GKE**:

```bash
# 1. Revisar estado en console (AWS/GCP)

# 2. Si control plane está OK pero nodes no:
terraform apply -replace=module.infra_aws.module.eks.aws_eks_node_group.workers

# 3. Si todo está mal, recrear:
cd environments/<env>
terraform destroy
terraform apply

# 4. Restore
velero restore create --from-backup latest
```

### Escenario 2: Bad Deployment Rollout

```bash
# 1. Rollback inmediato
kubectl rollout undo deployment/<name> -n <namespace>

# 2. Ver historial
kubectl rollout history deployment/<name> -n <namespace>

# 3. Rollback a revisión específica
kubectl rollout undo deployment/<name> -n <namespace> --to-revision=2

# 4. Pausar rollout (si está en progreso)
kubectl rollout pause deployment/<name> -n <namespace>

# 5. Resumir (después de fix)
kubectl rollout resume deployment/<name> -n <namespace>
```

### Escenario 3: Terraform State Corrupto

```bash
# 1. Backup del state actual
cp terraform.tfstate terraform.tfstate.backup

# 2. Si tienes remote backend con versioning
# AWS S3:
aws s3api list-object-versions --bucket <bucket> --prefix <key>
aws s3api get-object --bucket <bucket> --key <key> --version-id <version> terraform.tfstate

# GCP GCS:
gsutil ls -a gs://<bucket>/<prefix>
gsutil cp gs://<bucket>/<prefix>#<generation> terraform.tfstate

# 3. Verificar state
terraform state list
terraform plan  # No debe mostrar cambios inesperados

# 4. Si state está muy corrupto, recrear desde outputs
terraform import <resource_type>.<resource_name> <resource_id>
```

### Escenario 4: Pérdida Total de Data

```bash
# 1. Recrear infraestructura
cd environments/<env>
terraform apply

# 2. Instalar Velero
# (ver sección Backup)

# 3. Restore último backup bueno
velero backup get
velero restore create full-restore --from-backup <backup-name>

# 4. Verificar aplicaciones
kubectl get all -n apps
kubectl get pvc -A  # Verificar volúmenes
```

## 📞 Escalamiento y Contactos

### Niveles de Severidad

**SEV1 - Critical** (Producción caída)
- Contacto inmediato: Platform Lead
- SLA: Respuesta en 15 min

**SEV2 - High** (Funcionalidad degradada)
- Contacto: Ingeniero on-call
- SLA: Respuesta en 1 hora

**SEV3 - Medium** (Issue no crítico)
- Crear ticket en Jira
- SLA: Respuesta en 1 día laboral

**SEV4 - Low** (Mejora, pregunta)
- Slack: #platform-engineering
- SLA: Best effort

### Contactos

- Platform Lead: @lead (Slack), +1-555-0100
- Ingeniero On-Call: Ver PagerDuty schedule
- Cloud Support: AWS/GCP support portal (casos production)

## 📚 Referencias

- [Terraform Docs](https://developer.hashicorp.com/terraform/docs)
- [Kubernetes Docs](https://kubernetes.io/docs/)
- [nginx-ingress Docs](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Docs](https://cert-manager.io/docs/)
- [Velero Docs](https://velero.io/docs/)
- [Prometheus Docs](https://prometheus.io/docs/)

