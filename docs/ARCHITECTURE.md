# Architecture Documentation

## Overview

This repository implements a **portable, multi-cloud Kubernetes infrastructure** using a **2-layer architecture** that maximizes provider agnosticism while maintaining operational simplicity.

## Design Philosophy

### Core Principles

1. **Separation of Concerns**: Infrastructure (provider-specific) vs Runtime (provider-agnostic)
2. **DRY (Don't Repeat Yourself)**: Single runtime platform module for all providers
3. **Incremental Migration**: Start on VPS, migrate to cloud without app changes
4. **Infrastructure as Code**: Everything version-controlled, reviewable, reproducible
5. **Security by Default**: Private networks, IRSA/Workload Identity, no hardcoded secrets

### Why This Architecture?

**Problem**: Organizations start small (VPS) but need enterprise features (EKS/GKE) later. Traditional approaches require:
- Rewriting Helm charts
- Reconfiguring ingress controllers
- Migrating certificates and DNS
- Retraining teams on new tools

**Solution**: Two-layer architecture where **apps never know** which infrastructure they run on.

```
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Applications (ArgoCD, user workloads)         │
│  ─────────────────────────────────────────────────────  │
│  Same deployments across VPS/AWS/GCP                    │
└─────────────────────────────────────────────────────────┘
                         ▲
                         │ Kubernetes API
                         │
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Runtime Platform (Provider-Agnostic)          │
│  ─────────────────────────────────────────────────────  │
│  ├─ nginx-ingress (same config everywhere)              │
│  ├─ cert-manager (same ClusterIssuers)                  │
│  ├─ metrics-server                                      │
│  ├─ external-dns (provider-specific credentials only)   │
│  └─ kube-prometheus (optional)                          │
└─────────────────────────────────────────────────────────┘
                         ▲
                         │ Kubeconfig
                         │
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Infrastructure (Provider-Specific)            │
│  ─────────────────────────────────────────────────────  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  VPS + k3s   │  │  AWS + EKS   │  │  GCP + GKE   │ │
│  │              │  │              │  │              │ │
│  │ • SSH access │  │ • VPC        │  │ • VPC        │ │
│  │ • Firewall   │  │ • IRSA       │  │ • Workload   │ │
│  │ • k3s binary │  │ • Node groups│  │ • Identity   │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Layer 1: Infrastructure (Provider-Specific)

### Purpose
Provision and configure the Kubernetes cluster itself.

### Modules

#### `infra_vps_k3s`

**When to use**: Development, small projects, cost-sensitive deployments

**What it does**:
- Connects to VPS via SSH
- Installs k3s (lightweight Kubernetes)
- Configures UFW firewall
- Generates kubeconfig

**Outputs**:
- `kubeconfig_path`: Local file to access cluster
- `cluster_endpoint`: API server URL
- `ingress_ip`: VPS public IP

**Cost**: $5-20/month (VPS provider)

**Pros**: 
- Cheapest option
- Full control
- Fast setup (~5 min)

**Cons**:
- No managed services
- Single point of failure
- Manual backups

#### `infra_aws_eks`

**When to use**: Production, AWS ecosystem, need managed Kubernetes

**What it does**:
- Creates VPC with public/private subnets
- Provisions EKS cluster (managed control plane)
- Creates managed node groups
- Sets up IRSA for cert-manager/external-dns
- Configures security groups

**Outputs**:
- `kubeconfig_path`: Local file
- `cluster_endpoint`: EKS API server
- `oidc_provider_arn`: For IRSA
- `cert_manager_role_arn`: IAM role for cert-manager
- `external_dns_role_arn`: IAM role for external-dns

**Cost**: $150-400/month (cluster + nodes + NAT)

**Pros**:
- Managed control plane (AWS handles upgrades, HA)
- IRSA (no IAM keys in pods)
- Integrates with AWS services (ALB, EBS, Route53)
- High availability across AZs

**Cons**:
- More expensive
- AWS lock-in
- Slower provisioning (~15 min)

#### `infra_gcp_gke`

**When to use**: Production, GCP ecosystem, cost-optimized managed Kubernetes

**What it does**:
- Creates VPC network with subnets
- Provisions GKE cluster (managed control plane + nodes)
- Creates node pools with autoscaling
- Sets up Workload Identity for cert-manager/external-dns
- Configures Cloud NAT for private nodes

**Outputs**:
- `kubeconfig_path`: Local file
- `cluster_endpoint`: GKE API server
- `workload_identity_pool`: For Workload Identity
- `cert_manager_service_account`: GSA for cert-manager
- `external_dns_service_account`: GSA for external-dns

**Cost**: $100-300/month (generally 20-30% cheaper than EKS)

**Pros**:
- Cheapest managed option
- Excellent autoscaling
- Workload Identity (native GCP auth)
- Fast upgrades

**Cons**:
- GCP lock-in
- Less AWS service integrations
- Smaller ecosystem than EKS

### Common Interface

All infrastructure modules expose the same outputs:

```hcl
output "kubeconfig_path"     # Where kubectl config lives
output "cluster_endpoint"    # Kubernetes API URL
output "cluster_name"        # Cluster identifier
output "ingress_ip"          # Public IP for ingress (or command to get it)
output "provider_type"       # "vps-k3s", "aws-eks", or "gcp-gke"
```

This standardization allows the runtime layer to work identically across all providers.

## Layer 2: Runtime Platform (Provider-Agnostic)

### Purpose
Install and configure platform services that applications depend on.

### Module: `runtime_platform`

**Single module for all providers**. Receives:
- `provider_type`: "vps-k3s" | "aws-eks" | "gcp-gke"
- `kubeconfig_path`: From infrastructure layer

**What it installs**:

#### 1. nginx-ingress

**Why nginx**: 
- We deliberately **disable Traefik** (k3s default) for consistency
- Same ingress controller across VPS/AWS/GCP
- Easier team training (single tool)
- Consistent annotations and features

**Provider differences**:
- **VPS**: DaemonSet with `hostNetwork: true` (binds to ports 80/443)
- **AWS/GCP**: LoadBalancer service (creates ALB/NLB or GCP LB)

#### 2. cert-manager

**Purpose**: Automatic TLS certificate management via Let's Encrypt

**How it works**:
1. You create Ingress with annotation: `cert-manager.io/cluster-issuer: letsencrypt-prod`
2. cert-manager sees annotation, creates Certificate resource
3. Contacts Let's Encrypt with HTTP01 or DNS01 challenge
4. Stores certificate in Kubernetes Secret
5. Ingress controller uses secret for TLS

**Provider differences**:
- **VPS**: HTTP01 challenge (requires port 80 accessible)
- **AWS**: DNS01 via Route53 (uses IRSA, no API keys)
- **GCP**: DNS01 via Cloud DNS (uses Workload Identity)

**Why DNS01 in cloud**: 
- Supports wildcard certificates (`*.example.com`)
- Works with private clusters (no port 80 needed)
- More secure (no HTTP challenge exposure)

#### 3. metrics-server

**Purpose**: Provides resource metrics for `kubectl top` and HPA

**What it does**:
- Scrapes kubelet metrics every 15s
- Exposes Metrics API
- Enables Horizontal Pod Autoscaling

**Provider differences**:
- **VPS**: Needs `--kubelet-insecure-tls` (k3s uses self-signed certs)
- **AWS/GCP**: Works out of box

#### 4. external-dns (optional)

**Purpose**: Automatically create DNS records for Ingresses/Services

**How it works**:
1. You create Ingress with host `myapp.example.com`
2. external-dns detects it
3. Gets ingress IP/hostname
4. Creates DNS A/CNAME record in provider

**Provider differences**:
- **VPS**: Uses Cloudflare API (requires secret with API token)
- **AWS**: Uses Route53 (IRSA, no secrets)
- **GCP**: Uses Cloud DNS (Workload Identity, no secrets)

**Configuration**:
```hcl
enable_external_dns = true
external_dns_domain_filters = ["example.com"]  # Only manage these domains
```

#### 5. kube-prometheus-stack (optional)

**Purpose**: Full monitoring solution

**What it includes**:
- Prometheus: Metrics collection/storage
- Grafana: Dashboards
- Alertmanager: Alert routing
- Node exporter: Host metrics
- kube-state-metrics: Kubernetes object metrics

**Resource cost**: ~1 CPU, ~2GB RAM

**When to enable**:
- ✅ Staging/Production
- ❌ Development (unless debugging performance)

### Provider-Specific Configurations

The runtime module adapts based on `provider_type`:

```hcl
# VPS
ingress_service_type = "NodePort"
ingress_host_network = true
cert_manager_challenge = "http01"
external_dns_provider = "cloudflare"

# AWS
ingress_service_type = "LoadBalancer"
ingress_annotations = {
  "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
}
cert_manager_challenge = "dns01"
cert_manager_sa_annotation = {
  "eks.amazonaws.com/role-arn" = module.infra_aws.cert_manager_role_arn
}
external_dns_provider = "aws"

# GCP
ingress_service_type = "LoadBalancer"
cert_manager_challenge = "dns01"
cert_manager_sa_annotation = {
  "iam.gke.io/gcp-service-account" = module.infra_gcp.cert_manager_service_account
}
external_dns_provider = "google"
```

## Layer 3: Applications

Not part of this repository, but architectural considerations:

### Deployment Methods

1. **kubectl apply**: Simple, not recommended for production
2. **Helm**: Better, supports templating and versioning
3. **ArgoCD** (recommended): GitOps, automatic sync, rollback

### Application Requirements

To be portable across providers, applications must:

1. **Use standard Kubernetes resources**:
   - Deployment, Service, Ingress (not provider-specific CRDs)
   
2. **Use StorageClasses dynamically**:
   ```yaml
   storageClassName: ""  # Uses default
   # NOT: storageClassName: "gp3" (AWS-specific)
   ```

3. **Use cert-manager annotations**:
   ```yaml
   annotations:
     cert-manager.io/cluster-issuer: letsencrypt-prod
   ```

4. **Avoid hardcoded IPs/hostnames**:
   - Use DNS names
   - Use environment variables for endpoints

### Example Portable Application

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: apps
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:v1.0.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: apps
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
  namespace: apps
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
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

This manifest works identically on VPS/AWS/GCP.

## Security Architecture

### Secrets Management

**Never hardcode secrets in Terraform**.

#### Options:

1. **Environment Variables** (dev):
   ```bash
   export TF_VAR_cloudflare_api_token="..."
   terraform apply
   ```

2. **SOPS + AGE** (recommended):
   ```bash
   sops -e secrets.yaml > secrets.enc.yaml
   git add secrets.enc.yaml
   # Later:
   sops -d secrets.enc.yaml | terraform apply -var-file=-
   ```

3. **Terraform Cloud** (enterprise):
   - Encrypted variable storage
   - Audit logging
   - Team access controls

### IRSA (AWS) Architecture

**Problem**: Pods need AWS permissions (e.g., cert-manager accessing Route53)

**Old way**: IAM user with keys → store in Secret → security risk

**New way (IRSA)**:
1. EKS creates OIDC provider
2. Terraform creates IAM role with trust policy for OIDC
3. Annotate ServiceAccount with role ARN
4. Pod using that SA automatically gets temporary AWS credentials

```
┌─────────────────────────────────────────────────┐
│  Pod (cert-manager)                             │
│  ServiceAccount: cert-manager                   │
│  Annotation: eks.amazonaws.com/role-arn=...     │
└─────────────────┬───────────────────────────────┘
                  │ Requests AWS credentials
                  ▼
┌─────────────────────────────────────────────────┐
│  AWS STS (Secure Token Service)                 │
│  Verifies: OIDC token from EKS                  │
│  Returns: Temporary AWS credentials (1h)        │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│  Route53 (DNS service)                          │
│  Accepts requests with temp credentials         │
└─────────────────────────────────────────────────┘
```

**No secrets stored in cluster**.

### Workload Identity (GCP) Architecture

Similar to IRSA, but GCP-native:

1. GKE enables Workload Identity
2. Terraform creates GSA (Google Service Account)
3. Bind GSA to KSA (Kubernetes ServiceAccount)
4. Annotate KSA with GSA email
5. Pods get GCP credentials automatically

## Network Architecture

### VPS Network

```
┌────────────────────────────────────────┐
│  Internet                              │
└────────┬───────────────────────────────┘
         │
         ▼ (ports 80, 443, 22, 6443)
┌────────────────────────────────────────┐
│  VPS (Public IP: 203.0.113.10)         │
│  ┌──────────────────────────────────┐  │
│  │  UFW Firewall                    │  │
│  │  Allow: 22, 80, 443, 6443        │  │
│  └────────┬─────────────────────────┘  │
│           │                            │
│  ┌────────▼─────────────────────────┐  │
│  │  k3s                              │  │
│  │  ├─ Pods (10.42.0.0/16)           │  │
│  │  ├─ Services (10.43.0.0/16)       │  │
│  │  └─ nginx-ingress (hostNetwork)   │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

**Traffic flow**:
1. User → `https://app.example.com` → DNS resolves to 203.0.113.10
2. Hits VPS port 443 → nginx-ingress (host network)
3. nginx routes to Service → Pod

### AWS EKS Network

```
┌──────────────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)                                   │
│                                                      │
│  ┌────────────────────┐  ┌────────────────────┐    │
│  │ Public Subnet -1a  │  │ Public Subnet -1b  │    │
│  │ 10.0.101.0/24      │  │ 10.0.102.0/24      │    │
│  │                    │  │                    │    │
│  │  ┌──────────────┐  │  │  ┌──────────────┐  │    │
│  │  │ NAT Gateway  │  │  │  │ NAT Gateway  │  │    │
│  │  └──────┬───────┘  │  │  └──────┬───────┘  │    │
│  │         │          │  │         │          │    │
│  │  ┌──────▼───────┐  │  │  ┌──────▼───────┐  │    │
│  │  │ NLB          │  │  │  │ NLB (backup) │  │    │
│  │  │ (ingress)    │  │  │  │              │  │    │
│  │  └──────┬───────┘  │  │  └──────┬───────┘  │    │
│  └─────────┼──────────┘  └─────────┼──────────┘    │
│            │                       │               │
│  ┌─────────▼──────────┐  ┌─────────▼──────────┐    │
│  │ Private Subnet -1a │  │ Private Subnet -1b │    │
│  │ 10.0.1.0/24        │  │ 10.0.2.0/24        │    │
│  │                    │  │                    │    │
│  │  EKS Nodes         │  │  EKS Nodes         │    │
│  │  Pods              │  │  Pods              │    │
│  └────────────────────┘  └────────────────────┘    │
│                                                      │
│  EKS Control Plane (AWS-managed, in AWS VPC)        │
└──────────────────────────────────────────────────────┘
                        ▲
                        │ Managed by AWS
                        │
        ┌───────────────┴────────────────┐
        │  Amazon EKS Service            │
        │  (API server, etcd, scheduler) │
        └────────────────────────────────┘
```

**Traffic flow**:
1. User → `https://app.example.com` → DNS resolves to NLB hostname
2. NLB distributes across AZs → nginx-ingress pods
3. nginx routes to Service → Pod (in private subnet)

**Egress**: Pods → NAT Gateway → Internet (for pulling images, APIs)

### GCP GKE Network

Similar to AWS, but simpler:
- Single VPC with subnet
- Secondary ranges for pods/services (VPC-native)
- Cloud NAT for egress
- GCP Load Balancer for ingress

## Data Flow: Request to Response

### Example: `https://myapp.example.com/api/users`

#### 1. DNS Resolution

**VPS**:
```
myapp.example.com → A record → 203.0.113.10
```

**AWS/GCP**:
```
myapp.example.com → CNAME → xxx-123456.us-east-1.elb.amazonaws.com
                         → A records → [IP1, IP2, IP3]
```

#### 2. TLS Handshake

1. Client connects to ingress IP/hostname
2. nginx-ingress presents certificate (from cert-manager Secret)
3. Client validates certificate (signed by Let's Encrypt)
4. Encrypted connection established

#### 3. Ingress Routing

nginx-ingress reads Ingress rules:
```yaml
rules:
- host: myapp.example.com
  http:
    paths:
    - path: /
      backend:
        service:
          name: myapp
          port: 80
```

Routes to Service `myapp` on port 80.

#### 4. Service Load Balancing

Service selects Pod with matching labels:
```yaml
selector:
  app: myapp
```

Uses round-robin (or session affinity if configured).

#### 5. Pod Processes Request

Container receives HTTP request on port 8080 (targetPort).

#### 6. Response Returns

Same path in reverse: Pod → Service → Ingress → Client

## Disaster Recovery Architecture

### Backup Strategy

#### State Backup

**Terraform State**:
- **Dev**: Local (acceptable loss)
- **Stg/Prod**: Remote backend (S3 with versioning or GCS)

**Kubernetes State**:
- Use Velero for cluster backups
- Backs up to S3/GCS
- Includes PVs, ConfigMaps, Secrets

```bash
velero install --provider aws --bucket backups --backup-location-config region=us-east-1
velero schedule create daily --schedule="0 2 * * *"
```

#### Recovery Time Objectives (RTO)

- **VPS**: 30-60 min (reprovision from scratch)
- **EKS/GKE**: 20-30 min (cluster recreation + restore)
- **Data**: Depends on backup frequency

### High Availability

**VPS**: Not HA (single node)

**EKS/GKE**:
- Multi-AZ control plane (AWS/GCP managed)
- Multi-AZ nodes (in different subnets)
- Multi-AZ load balancers

**Application HA**:
```yaml
replicas: 3
podAntiAffinity:  # Spread across zones
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels:
          app: myapp
      topologyKey: topology.kubernetes.io/zone
```

## Cost Architecture

### Monthly Cost Breakdown

#### VPS (Dev)
```
VPS (2 vCPU, 4GB): $10-20
Total: $10-20/month
```

#### AWS EKS (Stg)
```
EKS control plane: $72
EC2 nodes (2x t3.medium on-demand): $60
NAT Gateways (2x): $64
EBS volumes: $10
Load Balancer: $20
Total: ~$226/month
```

#### AWS EKS (Prod)
```
EKS control plane: $72
EC2 nodes (3x t3.large): $150
NAT Gateways (3x): $96
EBS volumes: $30
Load Balancer: $20
Data transfer: $50
Total: ~$418/month
```

#### GCP GKE (Prod)
```
GKE control plane: $72 (free for autopilot/1 cluster)
Compute (3x n1-standard-4): $150
Cloud NAT: $45
Load Balancer: $18
Persistent Disks: $20
Total: ~$305/month
(20-30% cheaper than EKS)
```

### Cost Optimization Strategies

1. **Use SPOT/Preemptible for non-prod** (70-80% savings)
2. **Single NAT gateway in dev** ($32 vs $96)
3. **Zonal clusters for dev** (1/3 cost of regional)
4. **Right-size instances** (use metrics-server data)
5. **Scheduled autoscaling** (scale down nights/weekends)
6. **Reserved Instances** (production, 1-year commitment)

## Monitoring & Observability

### Metrics Collection

```
┌───────────────────────────────────────────────────┐
│  kube-state-metrics                               │
│  (Kubernetes object metrics)                      │
└────────────┬──────────────────────────────────────┘
             │
             ▼
┌───────────────────────────────────────────────────┐
│  Prometheus                                       │
│  ├─ Scrapes metrics every 15s                     │
│  ├─ Stores in TSDB (15-30 days)                   │
│  └─ Evaluates alerting rules                      │
└────────────┬──────────────────────────────────────┘
             │
             ▼
┌───────────────────────────────────────────────────┐
│  Grafana                                          │
│  ├─ Dashboards for visualization                  │
│  └─ Queries Prometheus via PromQL                 │
└───────────────────────────────────────────────────┘
```

### Key Metrics

**Infrastructure**:
- Node CPU/memory utilization
- Disk usage
- Network I/O

**Kubernetes**:
- Pod restarts
- Deployment availability
- PV usage

**Application**:
- HTTP request rate
- Response time (p50, p95, p99)
- Error rate

## Scalability

### Vertical Scaling (Bigger Nodes)

Change instance type:
```hcl
eks_instance_types = ["t3.xlarge"]  # Was t3.medium
```

Apply → nodes replaced with bigger ones.

### Horizontal Scaling (More Nodes)

**Manual**:
```hcl
eks_desired_size = 5  # Was 3
```

**Automatic** (Cluster Autoscaler):
Monitors pending pods, adds nodes automatically within min/max bounds.

### Application Autoscaling (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

Requires metrics-server (installed by runtime_platform).

## Migration Architecture

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for step-by-step procedures.

### Key Principle

**Applications don't migrate, infrastructure does**.

1. Deploy new infrastructure (e.g., EKS)
2. Install runtime platform (identical to VPS)
3. Backup apps from VPS (Velero)
4. Restore to EKS
5. Update DNS
6. Destroy VPS

Total downtime: < 5 minutes (DNS propagation).

## Conclusion

This architecture achieves:

- ✅ **Portability**: VPS → AWS → GCP with minimal changes
- ✅ **Simplicity**: 2 layers, clear separation
- ✅ **Security**: IRSA/Workload Identity, no hardcoded secrets
- ✅ **Cost Efficiency**: Start cheap (VPS), scale when needed
- ✅ **Maintainability**: DRY modules, standard interfaces
- ✅ **Production Ready**: HA, monitoring, backups

**Trade-offs**:
- Requires discipline (follow architecture patterns)
- Initial learning curve (2-layer concept)
- Some provider-specific features sacrificed for portability

**When to deviate**:
- Need AWS-specific services (e.g., RDS, ElastiCache) → use provider-specific modules
- Extreme scale (100+ nodes) → consider managed services like ECS/Cloud Run
- Multi-region requirements → more complex architecture needed

