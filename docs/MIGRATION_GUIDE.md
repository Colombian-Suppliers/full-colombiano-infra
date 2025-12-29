# Migration Guide: Provider to Provider

Guía completa para migrar tu cluster de Kubernetes de un proveedor a otro sin downtime significativo.

## Filosofía de Migración

**Principio clave**: No migras aplicaciones, migras infraestructura debajo de ellas.

La arquitectura de 2 capas permite:
1. Crear nueva infraestructura (Layer 1)
2. Instalar runtime platform idéntico (Layer 2)
3. Migrar state de aplicaciones
4. Cambiar DNS
5. Destruir infraestructura antigua

**Downtime esperado**: < 5 minutos (solo DNS propagation)

## Pre-requisitos Generales

Para cualquier migración:

```bash
# 1. Instalar Velero (si no está instalado)
# Ver RUNBOOK.md sección Backup

# 2. Crear backup completo
velero backup create pre-migration-$(date +%Y%m%d-%H%M) \
  --wait

# 3. Verificar backup
velero backup describe pre-migration-YYYYMMDD-HHMM
velero backup logs pre-migration-YYYYMMDD-HHMM

# 4. Exportar backup a S3/GCS (accesible desde nuevo cluster)
# Velero backups ya están en object storage

# 5. Documentar configuraciones actuales
kubectl get configmap -A -o yaml > configs-backup.yaml
kubectl get secret -A -o yaml > secrets-backup.yaml
kubectl get ingress -A -o yaml > ingresses-backup.yaml
```

## Migración 1: VPS (k3s) → AWS (EKS)

### Caso de Uso

Empezaste en VPS para validar el producto. Ahora necesitas:
- Alta disponibilidad (multi-AZ)
- Managed control plane
- Integración con servicios AWS (RDS, ElastiCache, etc.)
- Escalabilidad automática

### Paso a Paso

#### Fase 1: Preparación (Día -7)

```bash
# 1. En el cluster VPS actual
export KUBECONFIG=.kube/dev-k3s.yaml

# 2. Instalar Velero apuntando a S3
# Crear bucket S3
aws s3 mb s3://colombian-supply-migration-backups --region us-east-1

# Crear IAM user para Velero
aws iam create-user --user-name velero

# Attach policy (ver AWS docs para policy exacto)
aws iam attach-user-policy \
  --user-name velero \
  --policy-arn arn:aws:iam::aws:policy/VeleroBackupPolicy

# Crear access key
aws iam create-access-key --user-name velero

# Guardar credentials
cat > credentials-velero <<EOF
[default]
aws_access_key_id=<ACCESS_KEY>
aws_secret_access_key=<SECRET_KEY>
EOF

# Instalar Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket colombian-supply-migration-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --secret-file ./credentials-velero

# 3. Crear backup schedule (diario hasta migración)
velero schedule create daily-pre-migration \
  --schedule="0 2 * * *"

# 4. Test backup/restore en namespace no crítico
kubectl create namespace test-migration
kubectl run test-pod --image=nginx -n test-migration
velero backup create test-backup --include-namespaces test-migration --wait
velero restore create test-restore --from-backup test-backup
kubectl get all -n test-migration
```

#### Fase 2: Crear Infraestructura EKS (Día -1)

```bash
cd environments/stg  # O prod

# 1. Crear terraform.tfvars para EKS
cat > terraform.tfvars <<EOF
target_provider = "aws"
aws_region      = "us-east-1"

# Cluster config
eks_cluster_version = "1.28"
eks_instance_types  = ["t3.large"]  # Similar capacity a VPS
eks_desired_size    = 2
eks_min_size        = 2
eks_max_size        = 4

# Network
aws_vpc_cidr       = "10.1.0.0/16"
aws_single_nat_gateway = false  # HA

# Platform
letsencrypt_email      = "devops@colombiansupply.com"
cert_manager_use_dns01 = true
enable_external_dns    = true

# Route53 zone ARN (obtener con: aws route53 list-hosted-zones)
aws_route53_zone_arns = ["arn:aws:route53:::hostedzone/ZXXXXXXXXXXXXX"]
external_dns_domain_filters = ["colombiansupply.com"]

# Monitoring
enable_monitoring = true
EOF

# 2. Terraform init & plan
terraform init
terraform plan -out=eks-migration.plan

# 3. Revisar plan cuidadosamente
less eks-migration.plan

# 4. Apply (esto toma ~15 minutos)
terraform apply eks-migration.plan

# 5. Configurar kubectl para EKS
aws eks update-kubeconfig \
  --name stg-colombian-cluster \
  --region us-east-1 \
  --alias eks-migration

# 6. Verificar cluster
kubectl --context eks-migration get nodes
kubectl --context eks-migration get pods -n platform

# 7. Instalar Velero en EKS (apuntando al mismo bucket)
kubectl --context eks-migration apply -f \
  https://raw.githubusercontent.com/vmware-tanzu/velero/main/config/crds/v1/bases/velero.io_backupstoragelocations.yaml

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket colombian-supply-migration-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --secret-file ./credentials-velero \
  --use-node-agent \
  --kubeconfig ~/.kube/config \
  --kube-context eks-migration

# 8. Verificar que Velero ve los backups anteriores
kubectl --context eks-migration exec -n velero \
  deploy/velero -- velero backup get
```

#### Fase 3: Migración de Datos (Día 0)

```bash
# 1. NOTIFICAR A USUARIOS: Mantenimiento en 1 hora

# 2. Crear backup final en VPS
kubectl --context kubernetes-admin@dev-k3s-cluster \
  scale deployment --all --replicas=0 -n apps  # Opcional: stop writes

velero backup create final-migration-$(date +%Y%m%d-%H%M) \
  --include-namespaces apps \
  --wait

# 3. Esperar a que backup complete
velero backup describe final-migration-YYYYMMDD-HHMM

# 4. Restore en EKS
kubectl --context eks-migration exec -n velero \
  deploy/velero -- velero restore create eks-restore \
  --from-backup final-migration-YYYYMMDD-HHMM \
  --wait

# 5. Verificar restore
kubectl --context eks-migration get all -n apps
kubectl --context eks-migration get pvc -n apps
kubectl --context eks-migration get ingress -n apps

# 6. Verificar que pods están corriendo
kubectl --context eks-migration get pods -n apps -w

# 7. Test interno (desde dentro del cluster)
kubectl --context eks-migration run test-curl \
  --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://myapp.apps.svc.cluster.local
```

#### Fase 4: Cambio de DNS (Cutover)

```bash
# 1. Obtener nuevo ingress endpoint (EKS)
kubectl --context eks-migration get svc -n platform ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# Output: a1234567890.us-east-1.elb.amazonaws.com

# 2. Test con curl (antes de cambiar DNS público)
curl -H "Host: myapp.colombiansupply.com" \
  http://a1234567890.us-east-1.elb.amazonaws.com/health

# 3. Si external-dns está habilitado, los records se crean automáticamente
# Verificar en Route53:
aws route53 list-resource-record-sets \
  --hosted-zone-id ZXXXXXXXXXXXXX \
  | grep myapp

# 4. Si external-dns NO está habilitado, cambiar DNS manualmente
# En tu DNS provider (Cloudflare, Route53, etc.):
#   Cambiar: myapp.colombiansupply.com CNAME vps-ip
#   A:       myapp.colombiansupply.com CNAME a1234567890.us-east-1.elb.amazonaws.com

# 5. Reducir TTL antes del cambio (si es posible)
# TTL = 60 segundos para cambio rápido

# 6. Ejecutar cambio de DNS

# 7. Monitorear propagación
watch -n 5 'dig myapp.colombiansupply.com +short'

# 8. Test desde múltiples locations
curl -v https://myapp.colombiansupply.com
# Desde otro país/ISP
```

#### Fase 5: Validación Post-Migración

```bash
# 1. Verificar tráfico llegando a EKS
kubectl --context eks-migration logs -n platform \
  -l app.kubernetes.io/name=ingress-nginx --tail=100 -f

# 2. Verificar certificados SSL
echo | openssl s_client -connect myapp.colombiansupply.com:443 2>/dev/null | \
  openssl x509 -noout -dates

# 3. Monitorear errores
kubectl --context eks-migration get events -n apps --sort-by=.lastTimestamp

# 4. Verificar métricas (si monitoring habilitado)
kubectl --context eks-migration port-forward -n platform \
  svc/prometheus-kube-prometheus-prometheus 9090:9090
# Abrir http://localhost:9090 y revisar métricas

# 5. Smoke tests de aplicaciones críticas
# (Tus tests específicos aquí)

# 6. Monitorear por 24-48 horas
```

#### Fase 6: Limpieza (Día +7)

```bash
# Solo después de confirmar que todo funciona bien

# 1. Backup final de VPS (por si acaso)
kubectl --context kubernetes-admin@dev-k3s-cluster \
  --all-namespaces=true \
  get all -o yaml > vps-final-backup.yaml

# 2. Destruir infraestructura VPS
cd environments/dev
terraform destroy
# Confirmar: yes

# 3. Limpiar archivos locales
rm -rf .terraform
rm .kube/dev-k3s.yaml

# 4. Actualizar documentación
# - Actualizar README con nuevos endpoints
# - Actualizar runbook con procedimientos EKS
# - Archivar configuraciones VPS

# 5. Cancelar VPS con provider (DigitalOcean, etc.)
```

### Troubleshooting Migración VPS → EKS

#### Pods No Inician en EKS

```bash
# Storage class diferente
kubectl --context eks-migration get storageclass

# Si tus PVCs usan storageClassName específico de VPS, cambiar a "gp3" o ""
kubectl --context eks-migration edit pvc <pvc-name> -n apps
```

#### Certificados No Se Emiten

```bash
# IRSA para cert-manager
kubectl --context eks-migration describe sa cert-manager -n platform
# Debe tener annotation: eks.amazonaws.com/role-arn

# Verificar IAM role
aws iam get-role --role-name stg-colombian-cluster-cert-manager

# Ver logs
kubectl --context eks-migration logs -n platform \
  -l app.kubernetes.io/name=cert-manager --tail=200
```

#### Ingress No Recibe Tráfico

```bash
# Verificar security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:kubernetes.io/cluster/stg-colombian-cluster,Values=owned"

# Debe permitir ingress en puertos 80/443 desde 0.0.0.0/0
```

## Migración 2: VPS (k3s) → GCP (GKE)

Proceso similar a EKS, con diferencias clave:

### Diferencias Principales

1. **Workload Identity en vez de IRSA**:
```bash
# En terraform.tfvars
gcp_project_id = "colombian-supply-prod"
enable_cert_manager_workload_identity = true
enable_external_dns_workload_identity = true
```

2. **Velero usa GCS**:
```bash
# Crear bucket
gsutil mb gs://colombian-supply-migration-backups

# Service account para Velero
gcloud iam service-accounts create velero \
  --display-name "Velero backup service account"

# Grant permissions
gcloud projects add-iam-policy-binding colombian-supply-prod \
  --member serviceAccount:velero@colombian-supply-prod.iam.gserviceaccount.com \
  --role roles/compute.storageAdmin

# Create key
gcloud iam service-accounts keys create credentials-velero \
  --iam-account velero@colombian-supply-prod.iam.gserviceaccount.com

# Install Velero
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.8.0 \
  --bucket colombian-supply-migration-backups \
  --secret-file ./credentials-velero
```

3. **Obtener kubeconfig GKE**:
```bash
gcloud container clusters get-credentials prod-colombian-cluster \
  --region us-central1 \
  --project colombian-supply-prod
```

El resto del proceso es idéntico a la migración EKS.

## Migración 3: AWS (EKS) → GCP (GKE)

### Caso de Uso

Moverte de AWS a GCP por:
- Costos (GKE es 20-30% más barato)
- Mejores herramientas de data (BigQuery, Dataflow)
- Preferencia por GCP ecosystem

### Consideraciones Especiales

#### 1. Servicios AWS que debes migrar

- **RDS** → Cloud SQL
- **ElastiCache** → Memorystore
- **S3** → GCS
- **SQS/SNS** → Pub/Sub
- **Lambda** → Cloud Functions/Cloud Run

#### 2. Networking

EKS y GKE usan diferentes CNIs:
- EKS: AWS VPC CNI (pods get VPC IPs)
- GKE: Kubenet o VPC-native

**No afecta aplicaciones**, pero revisar:
- Network policies (si las usas)
- Pod IP ranges

#### 3. Storage

- EKS usa EBS (block storage)
- GKE usa Persistent Disks

Velero maneja esto automáticamente con snapshots.

### Proceso Simplificado

```bash
# 1. Backup desde EKS (a GCS en vez de S3)
# Configurar Velero en EKS para usar GCS como destination alternativo

# 2. Crear GKE cluster
cd environments/prod
# Cambiar target_provider = "gcp" en terraform.tfvars
terraform apply

# 3. Restore en GKE
velero restore create gke-migration --from-backup latest

# 4. Cambiar DNS

# 5. Verificar y destruir EKS
```

## Migración 4: GCP (GKE) → AWS (EKS)

Proceso inverso a GKE → EKS. Mismas consideraciones pero en dirección opuesta.

## Migración 5: Blue/Green (Cero Downtime)

Para aplicaciones críticas que no toleran ni 1 segundo de downtime.

### Arquitectura

```
                    ┌─────────────┐
                    │  Route53 /  │
                    │  Cloud DNS  │
                    │  (Weighted) │
                    └──────┬──────┘
                           │
              100% │       │ 0%
        ┌──────────┴───────┴──────────┐
        │                              │
   ┌────▼────┐                    ┌────▼────┐
   │  Blue   │                    │  Green  │
   │ (VPS)   │                    │ (EKS)   │
   │ Active  │                    │ Standby │
   └─────────┘                    └─────────┘
```

### Proceso

```bash
# 1. Deploy Green (EKS) con runtime completo
terraform apply

# 2. Restore datos en Green
velero restore create --from-backup latest

# 3. Sync continuo Blue → Green
# Usar herramienta como replicator o custom script

# 4. Weighted routing (Route53)
aws route53 change-resource-record-sets --hosted-zone-id Z123 --change-batch '
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "app.example.com",
      "Type": "A",
      "SetIdentifier": "Blue",
      "Weight": 90,
      "AliasTarget": {
        "HostedZoneId": "Z123",
        "DNSName": "vps-ip",
        "EvaluateTargetHealth": false
      }
    }
  },
  {
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "app.example.com",
      "Type": "A",
      "SetIdentifier": "Green",
      "Weight": 10,
      "AliasTarget": {
        "HostedZoneId": "Z123",
        "DNSName": "elb-hostname",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
'

# 5. Monitorear Green con 10% de tráfico

# 6. Incrementar gradualmente
# Weight Blue: 50, Green: 50
# Weight Blue: 10, Green: 90
# Weight Blue: 0, Green: 100

# 7. Después de 24h estable, destruir Blue
```

## Checklist de Migración

### Pre-Migración

- [ ] Backup completo creado y verificado
- [ ] Infraestructura destino creada y testeada
- [ ] Velero instalado en ambos clusters
- [ ] DNS TTL reducido a 60s (si es posible)
- [ ] Stakeholders notificados de ventana de mantenimiento
- [ ] Runbook de rollback preparado
- [ ] Contactos de soporte listos (AWS/GCP)

### Durante Migración

- [ ] Backup final creado
- [ ] Restore completado exitosamente
- [ ] Pods corriendo en nuevo cluster
- [ ] DNS cambiado
- [ ] Certificados SSL funcionando
- [ ] Smoke tests pasando

### Post-Migración

- [ ] Monitoreo activo por 24-48h
- [ ] Métricas normales (error rate, latency)
- [ ] Backups automáticos configurados
- [ ] Documentación actualizada
- [ ] Infraestructura antigua destruida (después de 7 días)
- [ ] Postmortem escrito (si hubo issues)

## Rollback Plan

Si algo sale mal durante la migración:

```bash
# 1. INMEDIATO: Revertir DNS al cluster original
# Cambiar CNAME/A record de vuelta

# 2. Verificar cluster original sigue funcionando
kubectl --context original-cluster get pods -A

# 3. Si cluster original está degradado, restore desde backup
velero restore create emergency-restore --from-backup pre-migration-YYYYMMDD

# 4. Notificar stakeholders

# 5. Investigar causa raíz

# 6. Schedule nueva ventana de migración después de fix
```

## Costos de Migración

### Estimado por Tipo

**VPS → EKS**:
- Overlap (ambos clusters corriendo): $226/mes prorrateado (1-2 días) = ~$15
- Data transfer (Velero backups): ~$5
- Engineering time: 8-16 horas
- **Total**: ~$20 + tiempo

**EKS → GKE**:
- Overlap: ~$450/mes prorrateado = ~$30
- Data transfer inter-cloud: ~$50-100 (depende de tamaño)
- Engineering time: 12-24 horas
- **Total**: ~$80-130 + tiempo

**Blue/Green**:
- Doble infraestructura por 1-7 días: $200-1500
- Más complejo pero cero downtime

## Lecciones Aprendidas

### Do's ✅

- **Test restore antes** de día de migración
- **Reduce TTL** de DNS días antes
- **Documentar** cada paso mientras lo haces
- **Tener rollback** plan claro
- **Comunicar** proactivamente a stakeholders
- **Migrar** en horario de bajo tráfico

### Don'ts ❌

- **No asumir** que backup/restore funcionará sin testearlo
- **No cambiar** múltiples cosas a la vez (migración + upgrade de versión)
- **No destruir** infraestructura antigua inmediatamente
- **No olvidar** migrar secrets/configmaps no respaldados por Velero
- **No subestimar** tiempo de DNS propagation
- **No hacer** migraciones los viernes

## Preguntas Frecuentes

**Q: ¿Cuánto downtime esperar?**
A: Con DNS switch: 1-5 minutos. Con Blue/Green: 0 minutos.

**Q: ¿Puedo migrar durante horario laboral?**
A: Sí, si usas Blue/Green. No recomendado para DNS switch directo.

**Q: ¿Qué pasa con las conexiones activas?**
A: Se pierden durante DNS switch. Clientes deben reconectar. Para WebSockets/long-polling, considera Blue/Green.

**Q: ¿Cómo migrar bases de datos externas?**
A: No están en Velero backup. Migrar por separado (pg_dump/restore, replicación, etc.)

**Q: ¿Velero respalda todo?**
A: No respalda:
  - Nodes (obviamente)
  - PVs en algunos casos (verifica snapshot support)
  - Secrets de Service Accounts (se recrean automáticamente)

**Q: ¿Cuánto tiempo mantener cluster antiguo?**
A: Mínimo 7 días, idealmente 14 días.

---

**¿Dudas?** Consultar con Platform Engineering team antes de ejecutar migración.

