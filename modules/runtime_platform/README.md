# Runtime Platform Module

**Provider-agnostic Kubernetes platform components**

This module installs common platform services on any Kubernetes cluster (k3s, EKS, GKE) using Helm. It provides a consistent runtime layer regardless of infrastructure provider.

## Philosophy

The runtime platform module is **infrastructure-agnostic** by design. It receives a kubeconfig and provider type, then installs identical platform components across VPS/AWS/GCP with only minor provider-specific configuration differences.

```
┌─────────────────────────────────────────────────────┐
│  Applications (ArgoCD, user workloads)              │
├─────────────────────────────────────────────────────┤
│  Runtime Platform Module (THIS MODULE)              │
│  ├─ nginx-ingress                                   │
│  ├─ cert-manager + ClusterIssuers                   │
│  ├─ metrics-server                                  │
│  ├─ external-dns (optional)                         │
│  └─ kube-prometheus-stack (optional)                │
├─────────────────────────────────────────────────────┤
│  Infrastructure Module (provider-specific)          │
│  VPS k3s | AWS EKS | GCP GKE                        │
└─────────────────────────────────────────────────────┘
```

## Components

### Core Components (Always Installed)

1. **nginx-ingress**: Ingress controller for HTTP/HTTPS routing
   - VPS: DaemonSet with hostNetwork
   - Cloud: LoadBalancer service

2. **cert-manager**: Automatic TLS certificate management
   - Let's Encrypt integration (staging + production)
   - HTTP01 or DNS01 challenges
   - IRSA/Workload Identity for cloud providers

3. **metrics-server**: Metrics API for HPA and kubectl top
   - Required for Horizontal Pod Autoscaling
   - Provides node/pod resource metrics

### Optional Components (Feature Flags)

4. **external-dns**: Automatic DNS record management
   - AWS Route53, GCP Cloud DNS, or Cloudflare
   - Syncs Ingress/Service to DNS automatically
   
5. **kube-prometheus-stack**: Full monitoring stack
   - Prometheus + Grafana + Alertmanager
   - Node exporter, kube-state-metrics
   - Pre-configured dashboards and alerts

## Usage

```hcl
module "runtime_platform" {
  source = "../../modules/runtime_platform"

  environment   = "dev"
  provider_type = "vps-k3s"  # or "aws-eks" or "gcp-gke"

  # cert-manager
  letsencrypt_email      = "devops@colombiansupply.com"
  cert_manager_use_dns01 = false  # Use HTTP01 for simplicity

  # Optional: external-dns
  enable_external_dns        = true
  external_dns_domain_filters = ["colombiansupply.com"]

  # Optional: monitoring
  enable_kube_prometheus     = true
  prometheus_ingress_enabled = true
  prometheus_ingress_host    = "prometheus.dev.colombiansupply.com"
  grafana_ingress_host       = "grafana.dev.colombiansupply.com"
}
```

## Provider-Specific Configuration

### VPS k3s

```hcl
provider_type = "vps-k3s"

# No additional cloud credentials needed
# cert-manager uses HTTP01 by default
# external-dns uses Cloudflare (requires secret)
```

**Ingress**: Uses `hostNetwork: true` and `hostPort` to bind directly to VPS ports 80/443.

**Certificates**: HTTP01 challenges work automatically via ingress.

**DNS**: Requires Cloudflare API token if using external-dns:

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token="YOUR_TOKEN" \
  -n platform
```

### AWS EKS

```hcl
provider_type = "aws-eks"
aws_region    = "us-east-1"

# IRSA roles from infra module
cert_manager_iam_role_arn  = module.eks_cluster.cert_manager_role_arn
external_dns_iam_role_arn  = module.eks_cluster.external_dns_role_arn

# DNS01 recommended for wildcard certs
cert_manager_use_dns01 = true

enable_external_dns        = true
external_dns_domain_filters = ["colombiansupply.com"]
```

**Ingress**: Creates AWS Network Load Balancer automatically.

**Certificates**: DNS01 via Route53 (no secrets needed, uses IRSA).

**DNS**: external-dns updates Route53 automatically via IRSA.

### GCP GKE

```hcl
provider_type   = "gcp-gke"
gcp_project_id  = "colombian-supply-prod"

# Workload Identity from infra module
cert_manager_gcp_sa_email  = module.gke_cluster.cert_manager_service_account
external_dns_gcp_sa_email  = module.gke_cluster.external_dns_service_account

cert_manager_use_dns01 = true

enable_external_dns        = true
external_dns_domain_filters = ["colombiansupply.com"]
```

**Ingress**: Creates GCP Load Balancer automatically.

**Certificates**: DNS01 via Cloud DNS (no secrets needed, uses Workload Identity).

**DNS**: external-dns updates Cloud DNS automatically via Workload Identity.

## Namespaces

The module creates two namespaces:

- `platform`: Platform services (ingress, cert-manager, monitoring)
- `apps`: User applications

This separation enables:
- Different RBAC policies
- Resource quotas per namespace
- Clear operational boundaries

## ClusterIssuers

Two Let's Encrypt ClusterIssuers are created:

### letsencrypt-staging

For testing certificate issuance without rate limits:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - test.example.com
```

### letsencrypt-prod

For production certificates (has rate limits):

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-prod
```

## HTTP01 vs DNS01 Challenges

### HTTP01 (Default for VPS)

**Pros**:
- Simple setup, no DNS provider integration
- Works with any DNS provider

**Cons**:
- Cannot issue wildcard certificates (`*.example.com`)
- Requires port 80 accessible
- Requires ingress for each domain

**Use when**: Single domain certificates, simple setup

### DNS01 (Recommended for Cloud)

**Pros**:
- Supports wildcard certificates
- No need for port 80
- More flexible

**Cons**:
- Requires DNS provider integration
- Needs cloud credentials (IRSA/Workload Identity)

**Use when**: Wildcard certs, private clusters, cloud providers

## external-dns

Automatically creates DNS records for Ingresses and LoadBalancer Services.

### Example: Automatic DNS Record

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  namespace: apps
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
spec:
  ingressClassName: nginx
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

external-dns will:
1. Detect the Ingress
2. Extract hostname from annotation
3. Get ingress IP/hostname
4. Create DNS A/CNAME record automatically

### Domain Filters

Restrict which domains external-dns manages:

```hcl
external_dns_domain_filters = [
  "colombiansupply.com",
  "dev.colombiansupply.com"
]
```

## Monitoring Stack

When `enable_kube_prometheus = true`, you get:

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization dashboards
- **Alertmanager**: Alert routing and notification
- **Node Exporter**: Host metrics
- **kube-state-metrics**: Kubernetes object metrics

### Accessing Grafana

With ingress enabled:

```
URL: https://grafana.dev.colombiansupply.com
Default user: admin
Default password: admin  # CHANGE THIS!
```

Without ingress:

```bash
kubectl port-forward -n platform svc/prometheus-grafana 3000:80
# Access at http://localhost:3000
```

### Custom Dashboards

Grafana comes with pre-installed dashboards:
- Kubernetes cluster overview
- Node metrics
- Pod metrics
- Persistent volume usage

Import additional dashboards from https://grafana.com/grafana/dashboards/

## Resource Requirements

### Minimal (Development)

```
nginx-ingress:    100m CPU, 128Mi RAM
cert-manager:     50m CPU, 128Mi RAM
metrics-server:   50m CPU, 64Mi RAM
Total:            ~200m CPU, ~320Mi RAM
```

### With Monitoring (Production)

```
nginx-ingress:          100m CPU, 128Mi RAM
cert-manager:           50m CPU, 128Mi RAM
metrics-server:         50m CPU, 64Mi RAM
external-dns:           50m CPU, 64Mi RAM
kube-prometheus-stack:  1000m CPU, 2Gi RAM
Total:                  ~1.2 CPU, ~2.5Gi RAM
```

## Troubleshooting

### Certificates not issuing

```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n platform -l app.kubernetes.io/name=cert-manager

# Check challenges
kubectl get challenges -A
```

### Ingress not working

```bash
# Check ingress controller
kubectl get pods -n platform -l app.kubernetes.io/name=ingress-nginx

# Check ingress object
kubectl describe ingress <name> -n <namespace>

# Check service
kubectl get svc -n platform ingress-nginx-controller
```

### external-dns not creating records

```bash
# Check logs
kubectl logs -n platform -l app.kubernetes.io/name=external-dns

# Verify permissions (AWS)
kubectl describe sa external-dns -n platform
# Should see eks.amazonaws.com/role-arn annotation

# Verify permissions (GCP)
kubectl describe sa external-dns -n platform
# Should see iam.gke.io/gcp-service-account annotation
```

### Prometheus storage full

```bash
# Check PVC
kubectl get pvc -n platform

# Increase storage size
kubectl edit pvc prometheus-<name> -n platform
# Update storage size, requires StorageClass with allowVolumeExpansion: true
```

## Upgrading Components

### Helm Chart Versions

Update versions in `variables.tf`:

```hcl
nginx_ingress_version  = "4.10.0"  # Update here
cert_manager_version   = "v1.14.0"
```

Then run:

```bash
terraform apply
```

Helm will perform rolling updates automatically.

### Major Version Upgrades

For major version updates (e.g., cert-manager v1.12 → v1.13):

1. Read upgrade notes: https://cert-manager.io/docs/installation/upgrading/
2. Check for breaking changes
3. Backup CRDs: `kubectl get crds -o yaml > crds-backup.yaml`
4. Update version
5. Apply and monitor

## Security Considerations

- ✅ All components run as non-root (where possible)
- ✅ RBAC policies are minimal (least privilege)
- ✅ Secrets are not logged
- ✅ TLS enabled by default for ingress
- ✅ NetworkPolicies recommended (deploy separately)
- ✅ Regular security updates via automated upgrades

## Customization

### Custom Helm Values

To pass additional Helm values, edit the template files in `helm-values/`:

```yaml
# helm-values/nginx-ingress.yaml
controller:
  config:
    custom-config-key: "custom-value"
```

### Custom Annotations

Add annotations to ingress, cert-manager, etc.:

```hcl
# In main.tf
set {
  name  = "controller.service.annotations.custom\\.annotation"
  value = "custom-value"
}
```

## Migration Between Providers

The beauty of this module: **migration is transparent**.

When moving from k3s → EKS:
1. Deploy new EKS cluster (infra module)
2. Install runtime_platform with `provider_type = "aws-eks"`
3. All platform components install identically
4. Applications continue to work (same ingress class, same cert-manager)

Only DNS records need updating (handled by external-dns automatically).

See [MIGRATION_GUIDE.md](../../docs/MIGRATION_GUIDE.md) for detailed steps.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| kubernetes | ~> 2.24 |
| helm | ~> 2.12 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name | `string` | n/a | yes |
| provider_type | Provider type (vps-k3s, aws-eks, gcp-gke) | `string` | n/a | yes |
| letsencrypt_email | Email for Let's Encrypt | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| platform_namespace | Platform namespace name |
| apps_namespace | Apps namespace name |
| platform_components | List of installed components |
<!-- END_TF_DOCS -->

