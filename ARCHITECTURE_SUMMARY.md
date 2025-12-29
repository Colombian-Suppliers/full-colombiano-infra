# Resumen de Arquitectura: 3 Ambientes

## 🏗️ Estrategia de Ambientes

```
┌─────────────────────────────────────────────────────────┐
│  DESARROLLO (Dev)                                       │
│  ─────────────────────────────────────────────────────  │
│  • Docker Desktop o Minikube (local en laptop)          │
│  • Ingenieros desarrollan y testean localmente          │
│  • Sin Terraform, setup con Helm directo                │
│  • Certificados self-signed                             │
│  • Dominios: *.local.dev (/etc/hosts)                   │
│  • Costo: $0                                            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  STAGING + PRODUCTION                                   │
│  ─────────────────────────────────────────────────────  │
│  • Mismo VPS (4 vCPU, 8GB RAM, k3s)                     │
│  • Separación por namespaces (stg-apps, prod-apps)      │
│  • Resource Quotas (40% stg, 60% prod)                  │
│  • Network Policies para aislamiento                    │
│  • Terraform para IaC                                   │
│  • Let's Encrypt para TLS                               │
│  • Dominios:                                            │
│    - stg: *.stg.colombiansupply.com                     │
│    - prod: *.colombiansupply.com                        │
│  • Costo: $20-24/mes (VPS único)                        │
└─────────────────────────────────────────────────────────┘
```

## 🔄 Flujo de Trabajo

```
1. Desarrollador:
   - Clonar repo
   - Trabajar en branch feature/xxx
   - Testear localmente en Docker Desktop
   - Commit y push

2. CI/CD (GitHub Actions):
   - PR triggers terraform-ci.yml
   - Validaciones: fmt, lint, security
   - Comentarios automáticos en PR

3. Merge a main:
   - Deploy automático a staging (namespace stg-apps)
   - Tests de integración
   - Validación manual

4. Tag release (v1.2.3):
   - Deploy manual a production (namespace prod-apps)
   - Rollout gradual
   - Monitoreo

5. Migración futura:
   - Si tráfico crece mucho
   - Cambiar target_provider = "aws" o "gcp"
   - Runtime platform permanece idéntico
   - Apps no requieren cambios
```

## 📊 Recursos por Ambiente

### Dev Local (Docker Desktop)

```yaml
Recursos totales:
  CPU: Lo que tenga tu laptop (típicamente 4-8 cores)
  RAM: Lo que asignes a Docker (típicamente 4-8GB)
  
Configuración:
  - Namespaces: platform, apps
  - Sin resource quotas
  - Certificados: Self-signed
```

### Staging (VPS namespace: stg-apps)

```yaml
Resource Quota:
  requests.cpu: 1600m (40% de 4 vCPU)
  requests.memory: 3Gi
  limits.cpu: 2000m
  limits.memory: 4Gi
  
Configuración típica:
  - Replicas: 2 por deployment
  - CPU por pod: 100-500m
  - RAM por pod: 128-512Mi
```

### Production (VPS namespace: prod-apps)

```yaml
Resource Quota:
  requests.cpu: 2400m (60% de 4 vCPU)
  requests.memory: 5Gi
  limits.cpu: 3000m
  limits.memory: 6Gi
  
Configuración típica:
  - Replicas: 3 por deployment
  - CPU por pod: 200-1000m
  - RAM por pod: 256Mi-1Gi
```

## 🔒 Seguridad por Ambiente

### Dev Local
- ✅ Network isolation (Docker network)
- ✅ Self-signed certs (suficiente para dev)
- ❌ Sin exposición pública
- ❌ Sin secrets reales (usar mocks)

### Staging (VPS)
- ✅ Resource Quotas
- ✅ Network Policies (cross-namespace isolation)
- ✅ Let's Encrypt TLS
- ✅ RBAC por namespace
- ✅ Secrets en Kubernetes (no Git)
- ⚠️  Datos reales pero no sensibles

### Production (VPS)
- ✅ Todo lo de staging +
- ✅ Resource limits estrictos
- ✅ Pod Security Standards
- ✅ Network Policies más restrictivas
- ✅ Audit logging
- ✅ Backups automáticos (Velero)
- ✅ Monitoreo 24/7

## 🚀 Comandos por Ambiente

### Dev Local

```bash
# Setup inicial (una vez)
cd environments/dev
./setup-local-dev.sh

# Desarrollo diario
kubectl apply -f myapp.yaml
kubectl logs -f deployment/myapp
kubectl port-forward svc/myapp 8080:80

# Limpiar
kubectl delete namespace apps --force
kubectl create namespace apps
```

### Staging (VPS)

```bash
# Setup inicial (una vez por VPS)
cd environments/stg
terraform init
terraform apply

# Deploy app
kubectl apply -f myapp-staging.yaml --namespace stg-apps

# Ver estado
kubectl get all -n stg-apps
kubectl top pods -n stg-apps

# Logs
kubectl logs -f -n stg-apps deployment/myapp
```

### Production (VPS)

```bash
# No requiere setup adicional (mismo cluster que staging)

# Deploy app (con aprobación manual)
kubectl apply -f myapp-production.yaml --namespace prod-apps

# Rollout gradual
kubectl set image deployment/myapp -n prod-apps app=myapp:v1.2.3
kubectl rollout status deployment/myapp -n prod-apps

# Rollback si es necesario
kubectl rollout undo deployment/myapp -n prod-apps

# Monitoreo
kubectl top pods -n prod-apps
kubectl get events -n prod-apps --sort-by=.lastTimestamp
```

## 📈 Path de Escalamiento

### Fase 1: Actual (0-1000 usuarios)
- ✅ Dev local
- ✅ VPS compartido (stg + prod)
- **Costo**: $20/mes

### Fase 2: Crecimiento (1000-10,000 usuarios)
- ✅ Dev local
- ✅ VPS para staging
- ➡️ **AWS EKS o GCP GKE para producción**
- **Costo**: ~$220/mes ($20 VPS + $200 EKS/GKE)

### Fase 3: Escala (10,000+ usuarios)
- ✅ Dev local
- ➡️ **AWS EKS para staging** (costo optimizado)
- ➡️ **AWS EKS para producción** (HA completo)
- Opcional: Multi-región
- **Costo**: ~$600-800/mes

### Fase 4: Enterprise (100,000+ usuarios)
- ✅ Dev local
- ➡️ **Multi-cloud**: AWS + GCP (DR)
- ➡️ **Multi-región** en cada cloud
- ➡️ Service mesh (Istio/Linkerd)
- **Costo**: $2,000-5,000/mes

**Clave**: La arquitectura soporta toda esta evolución sin reescribir aplicaciones.

## 🎯 Ventajas de Esta Arquitectura

### 1. Costo-Efectiva
- Empiezas con $20/mes (3 ambientes)
- 97% más barato que cloud directo
- Escala cuando realmente lo necesitas

### 2. Developer Experience
- Desarrollo 100% local (rápido, sin esperar deploys)
- Feedback instantáneo
- No consumes recursos de staging/prod

### 3. Separación Clara
- Dev: Experimentos y breaking changes
- Staging: Testing de integración
- Production: Estable y monitoreado

### 4. Portable
- Cambias de VPS a cloud editando una variable
- Apps no saben dónde corren
- Misma experiencia operacional

### 5. Segura
- Dev aislado (no puede afectar prod)
- Staging/Prod con Network Policies
- Resource quotas previenen resource exhaustion

## 📝 Próximos Pasos Recomendados

### Inmediato (Sprint 1)
- [ ] Setup dev local en laptops del equipo
- [ ] Provisionar VPS para staging+prod
- [ ] Configurar DNS (*.stg y *.prod)
- [ ] Desplegar primera aplicación

### Corto Plazo (Sprint 2-3)
- [ ] Configurar CI/CD completo
- [ ] Implementar Network Policies
- [ ] Setup Velero para backups
- [ ] Documentar runbooks específicos

### Mediano Plazo (Mes 2-3)
- [ ] Monitoreo con Prometheus/Grafana
- [ ] Alerting (PagerDuty/OpsGenie)
- [ ] Load testing en staging
- [ ] Optimizar resource requests/limits

### Largo Plazo (Cuando sea necesario)
- [ ] Migrar prod a AWS EKS o GCP GKE
- [ ] Mantener staging en VPS (ahorrar costos)
- [ ] Implementar blue/green deploys
- [ ] Multi-región si es requerido

---

**Esta arquitectura permite a Colombian Supply empezar barato, escalar cuando sea necesario, y mantener la portabilidad para el futuro.**

