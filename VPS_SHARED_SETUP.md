# VPS Compartido: Staging + Production

Guía para configurar **staging y production en el mismo VPS** con separación lógica mediante namespaces y resource quotas.

## 🎯 Arquitectura del VPS Compartido

```
┌──────────────────────────────────────────────────────┐
│  VPS (4 vCPU, 8GB RAM, IP: 203.0.113.10)            │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  k3s Cluster                                   │ │
│  │                                                 │ │
│  │  ┌─────────────────┐  ┌─────────────────┐    │ │
│  │  │ Namespace: stg  │  │ Namespace: prod │    │ │
│  │  │                 │  │                 │    │ │
│  │  │ Apps staging    │  │ Apps production │    │ │
│  │  │ CPU: 40%        │  │ CPU: 60%        │    │ │
│  │  │ RAM: 3GB        │  │ RAM: 5GB        │    │ │
│  │  └─────────────────┘  └─────────────────┘    │ │
│  │                                                 │ │
│  │  ┌─────────────────────────────────────────┐  │ │
│  │  │ Namespace: platform                     │  │ │
│  │  │ - ingress-nginx (ruta por subdomain)    │  │ │
│  │  │ - cert-manager                          │  │ │
│  │  │ - metrics-server                        │  │ │
│  │  └─────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  Firewall (UFW): 22, 80, 443, 6443                  │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
                    Internet
                         │
        ┌────────────────┴────────────────┐
        │                                 │
   stg.colombian...com            colombian...com
   (staging apps)                 (production apps)
```

## 🔧 Setup Inicial (Una sola vez)

### Paso 1: Provisionar VPS con k3s

```bash
cd environments/stg

# Crear terraform.tfvars
cat > terraform.tfvars <<'EOF'
target_provider = "vps"
vps_host        = "203.0.113.10"  # TU IP VPS
vps_user        = "root"
ssh_private_key_path = "~/.ssh/id_rsa"

# k3s configuration
k3s_version = "v1.28.5+k3s1"
vps_configure_firewall = true

# Platform configuration (compartido)
letsencrypt_email = "devops@colombiansupply.com"
enable_external_dns = false  # Configurar DNS manualmente
EOF

# Desplegar
terraform init
terraform apply

# Exportar kubeconfig
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
```

### Paso 2: Configurar Namespaces y Resource Quotas

```bash
# Crear namespace para staging
kubectl create namespace stg-apps
kubectl label namespace stg-apps environment=staging

# Crear namespace para production
kubectl create namespace prod-apps
kubectl label namespace prod-apps environment=production

# Resource Quota para staging (40% de recursos)
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: stg-quota
  namespace: stg-apps
spec:
  hard:
    requests.cpu: "1600m"      # 40% de 4 vCPUs
    requests.memory: "3Gi"     # ~40% de 8GB
    limits.cpu: "2000m"
    limits.memory: "4Gi"
    persistentvolumeclaims: "10"
    services.loadbalancers: "0"  # No LoadBalancers, usar Ingress
---
apiVersion: v1
kind: LimitRange
metadata:
  name: stg-limits
  namespace: stg-apps
spec:
  limits:
  - max:
      cpu: "1000m"
      memory: "1Gi"
    min:
      cpu: "10m"
      memory: "16Mi"
    type: Container
EOF

# Resource Quota para production (60% de recursos)
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-quota
  namespace: prod-apps
spec:
  hard:
    requests.cpu: "2400m"      # 60% de 4 vCPUs
    requests.memory: "5Gi"     # ~60% de 8GB
    limits.cpu: "3000m"
    limits.memory: "6Gi"
    persistentvolumeclaims: "20"
    services.loadbalancers: "0"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: prod-limits
  namespace: prod-apps
spec:
  limits:
  - max:
      cpu: "2000m"
      memory: "2Gi"
    min:
      cpu: "10m"
      memory: "16Mi"
    type: Container
EOF

# Verificar quotas
kubectl describe quota -n stg-apps
kubectl describe quota -n prod-apps
```

### Paso 3: Configurar Ingress para Subdomains

El ingress-nginx ya instalado en namespace `platform` puede rutear por subdomain:

```yaml
# Staging app ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-stg
  namespace: stg-apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.stg.colombiansupply.com
    secretName: myapp-stg-tls
  rules:
  - host: myapp.stg.colombiansupply.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80

---
# Production app ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-prod
  namespace: prod-apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.colombiansupply.com
    secretName: myapp-prod-tls
  rules:
  - host: myapp.colombiansupply.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

### Paso 4: Configurar DNS

En tu proveedor de DNS (Cloudflare, Route53, etc.):

```
# Wildcard para staging
*.stg.colombiansupply.com  →  A record  →  203.0.113.10

# Wildcard para production
*.colombiansupply.com       →  A record  →  203.0.113.10

# O records individuales:
myapp.stg.colombiansupply.com  →  A  →  203.0.113.10
myapp.colombiansupply.com      →  A  →  203.0.113.10
```

## 📦 Desplegar Aplicaciones

### Staging Deployment

```bash
# Ejemplo: Desplegar app en staging
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: stg-apps
  labels:
    app: myapp
    environment: staging
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:v1.2.3-stg
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        env:
        - name: ENVIRONMENT
          value: "staging"
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: stg-apps
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: stg-apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.stg.colombiansupply.com
    secretName: myapp-tls
  rules:
  - host: myapp.stg.colombiansupply.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
EOF
```

### Production Deployment

```bash
# Mismo app, namespace prod-apps, más replicas
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: prod-apps
  labels:
    app: myapp
    environment: production
spec:
  replicas: 3  # Más replicas en prod
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:v1.2.3  # Tag estable
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        env:
        - name: ENVIRONMENT
          value: "production"
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: prod-apps
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: prod-apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.colombiansupply.com
    secretName: myapp-prod-tls
  rules:
  - host: myapp.colombiansupply.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
EOF
```

## 🔒 Aislamiento y Seguridad

### Network Policies (Opcional pero Recomendado)

```bash
# Staging: solo puede comunicarse dentro de stg-apps
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: stg-apps
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          environment: staging
    - namespaceSelector:
        matchLabels:
          name: platform  # Permitir desde platform (ingress)
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          environment: staging
  - to:  # Permitir DNS
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

# Similar para prod-apps
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
  namespace: prod-apps
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          environment: production
    - namespaceSelector:
        matchLabels:
          name: platform
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          environment: production
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF
```

### RBAC por Ambiente

```bash
# Service Account para staging deployments
kubectl create serviceaccount stg-deployer -n stg-apps

# Role con permisos limitados
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: stg-deployer
  namespace: stg-apps
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["services", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: stg-deployer
  namespace: stg-apps
subjects:
- kind: ServiceAccount
  name: stg-deployer
  namespace: stg-apps
roleRef:
  kind: Role
  name: stg-deployer
  apiGroup: rbac.authorization.k8s.io
EOF
```

## 📊 Monitoreo por Ambiente

```bash
# Ver uso de recursos por namespace
kubectl top pods -n stg-apps
kubectl top pods -n prod-apps

# Ver quotas
kubectl describe resourcequota -n stg-apps
kubectl describe resourcequota -n prod-apps

# Ver eventos
kubectl get events -n stg-apps --sort-by='.lastTimestamp'
kubectl get events -n prod-apps --sort-by='.lastTimestamp'
```

## 🔄 Flujo de Promoción Staging → Production

```bash
# 1. Testear en staging
kubectl apply -f myapp-staging.yaml
curl https://myapp.stg.colombiansupply.com

# 2. Si OK, cambiar imagen tag en prod deployment
kubectl set image deployment/myapp -n prod-apps \
  app=myapp:v1.2.3

# O aplicar manifiesto completo
kubectl apply -f myapp-production.yaml

# 3. Monitorear rollout
kubectl rollout status deployment/myapp -n prod-apps

# 4. Si hay problemas, rollback
kubectl rollout undo deployment/myapp -n prod-apps
```

## 💰 Costo Total

**VPS Único (4 vCPU, 8GB RAM)**:
- DigitalOcean: $24/mes
- Hetzner: ~$15/mes  
- Linode: $24/mes

**Total: ~$15-24/mes para staging + production**

Comparado con cloud separado:
- AWS EKS staging + prod: ~$600/mes
- **Ahorro: 95%+**

## ⚠️ Limitaciones

1. **Recursos compartidos**: Un ambiente puede afectar al otro si hay spike de uso
2. **Sin HA**: Si el VPS falla, ambos ambientes caen
3. **Escalabilidad limitada**: Máximo ~8GB RAM, 4-8 vCPUs
4. **Backups manuales**: Configurar Velero o snapshots del VPS

## 🎓 Cuándo Migrar a Cloud Separado

Considera migrar cuando:
- Traffic de producción > 10,000 req/min
- Necesitas más de 8GB RAM
- Requieres SLA de 99.9%+
- Compliance requiere ambientes físicamente separados
- Presupuesto permite ~$200-400/mes por ambiente

Entonces usa:
- **Staging**: AWS EKS o GCP GKE (configuración mínima)
- **Production**: AWS EKS o GCP GKE (HA completo)

La arquitectura ya está preparada: solo cambias `target_provider` en terraform.tfvars.

## 📚 Recursos

- [Kubernetes Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Multi-tenancy Best Practices](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

