# GCP GKE Infrastructure Module

This module provisions a production-ready GKE cluster with VPC, node pools, and Workload Identity for platform components.

## Features

- **VPC Network**: Custom VPC with subnet and secondary ranges for pods/services
- **GKE Cluster**: Managed Kubernetes cluster with configurable version
- **Node Pools**: Autoscaling node pools with preemptible/standard support
- **Workload Identity**: Native GCP authentication for:
  - cert-manager (Cloud DNS integration)
  - external-dns (Cloud DNS management)
- **Private Cluster**: Optional private nodes with Cloud NAT
- **Security**: Shielded nodes, network policies, minimal IAM roles
- **Observability**: Cloud Logging, Cloud Monitoring, optional Managed Prometheus

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                    GCP Project                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  VPC Network                                     │  │
│  │                                                  │  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │ Subnet (10.10.0.0/24)                    │  │  │
│  │  │   ├─ Pods Range (10.20.0.0/16)           │  │  │
│  │  │   └─ Services Range (10.30.0.0/16)       │  │  │
│  │  │                                            │  │  │
│  │  │  Cloud Router + Cloud NAT                 │  │  │
│  │  │                                            │  │  │
│  │  │  GKE Nodes (Private IPs)                  │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  │                                                  │  │
│  │  GKE Control Plane (Managed by Google)          │  │
│  └─────────────────────────────────────────────────┘  │
│                                                        │
│  Workload Identity: cert-manager, external-dns        │
└────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "gke_cluster" {
  source = "../../modules/infra_gcp_gke"

  environment = "prod"
  project_id  = "colombian-supply-prod"
  region      = "us-central1"

  # Cluster Configuration
  cluster_version   = "1.28"
  regional_cluster  = true  # Multi-zone for HA

  # Network
  subnet_cidr   = "10.10.0.0/24"
  pods_cidr     = "10.20.0.0/16"
  services_cidr = "10.30.0.0/16"

  # Private cluster
  enable_private_nodes    = true
  enable_private_endpoint = false  # Keep API public for CI/CD

  # Node Pool
  machine_type      = "n1-standard-2"
  preemptible_nodes = false
  enable_autoscaling = true
  min_node_count    = 3
  max_node_count    = 10

  # Workload Identity
  enable_cert_manager_workload_identity    = true
  enable_external_dns_workload_identity    = true

  labels = {
    project = "colombian-supply"
  }
}
```

## Regional vs Zonal Clusters

### Zonal Cluster (Development)

```hcl
regional_cluster = false
zone             = "us-central1-a"
node_count       = 1
```

**Pros**: Lower cost (single zone), faster deployments
**Cons**: No HA - if zone fails, cluster is down

**Cost**: ~$80-120/month

### Regional Cluster (Production)

```hcl
regional_cluster = true
region           = "us-central1"
# Nodes distributed across 3 zones automatically
```

**Pros**: High availability, automatic zone distribution
**Cons**: 3x cost (nodes replicated across zones)

**Cost**: ~$250-400/month

## Cost Optimization

### Development

```hcl
regional_cluster  = false
zone              = "us-central1-a"
machine_type      = "e2-medium"      # Cheaper than n1
preemptible_nodes = true             # 80% cheaper
node_count        = 1
enable_autoscaling = false
```

### Production

```hcl
regional_cluster   = true
machine_type       = "n1-standard-2"
preemptible_nodes  = false
enable_autoscaling = true
min_node_count     = 3
max_node_count     = 10
```

## Workload Identity

GKE's Workload Identity provides secure, keyless authentication to Google Cloud services.

### How It Works

1. Create GCP Service Account (GSA)
2. Grant GSA permissions (e.g., `roles/dns.admin`)
3. Bind GSA to Kubernetes ServiceAccount (KSA) via IAM
4. Annotate KSA with GSA email
5. Pods using KSA automatically get GSA credentials

### cert-manager Setup

Module automatically creates:

```hcl
# GSA for cert-manager
google_service_account.cert_manager

# Grant DNS admin role
google_project_iam_member.cert_manager_dns

# Bind to KSA
google_service_account_iam_member.cert_manager_workload_identity
  member = "serviceAccount:{project}.svc.id.goog[platform/cert-manager]"
```

In runtime_platform, annotate cert-manager ServiceAccount:

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: {cluster-name}-cert-manager@{project}.iam.gserviceaccount.com
```

### external-dns Setup

Similar to cert-manager:

```hcl
enable_external_dns_workload_identity = true
```

Annotate external-dns ServiceAccount in runtime_platform module.

## Private Clusters

### Private Nodes

```hcl
enable_private_nodes = true
```

- Nodes get private IPs only (no public IPs)
- Internet access via Cloud NAT
- More secure, cheaper (no external IPs)

### Private Endpoint

```hcl
enable_private_endpoint = true
```

- Kubernetes API not publicly accessible
- Requires VPN or Cloud Identity-Aware Proxy
- Maximum security for production

**Note**: Keep `enable_private_endpoint = false` if you need CI/CD access from GitHub Actions.

## Networking

### IP Ranges

- **Subnet CIDR** (`10.10.0.0/24`): 254 IPs for nodes
- **Pods CIDR** (`10.20.0.0/16`): 65,536 IPs for pods (VPC-native)
- **Services CIDR** (`10.30.0.0/16`): 65,536 IPs for services

### Firewall Rules

- **allow-internal**: All traffic within VPC (nodes, pods, services)
- **allow-ssh**: SSH access from authorized networks

### Cloud NAT

Provides outbound internet access for private nodes (pulling images, calling APIs).

**Cost**: ~$45/month + data processing charges

## Node Autoscaling

GKE's Cluster Autoscaler automatically scales nodes based on pod demand:

```hcl
enable_autoscaling = true
min_node_count     = 1
max_node_count     = 10
```

- Scales **up** when pods are pending due to insufficient resources
- Scales **down** when nodes are underutilized (< 50% CPU/memory)
- Respects PodDisruptionBudgets

## Managed Prometheus

Google Cloud Managed Service for Prometheus:

```hcl
enable_managed_prometheus = true
```

- No need to run Prometheus in-cluster
- Scales automatically
- Integrated with Cloud Monitoring
- Query via PromQL

**Cost**: Based on samples ingested (~$0.15/million samples)

## Cluster Upgrades

### Master Upgrades

GKE automatically upgrades master to new patch versions. Control with:

```hcl
cluster_version = "1.28"  # Locks to 1.28.x
```

### Node Upgrades

```hcl
auto_upgrade_nodes = true
```

- Nodes auto-upgrade to match master version
- Upgrades during maintenance window
- Respects PodDisruptionBudgets

To disable auto-upgrade:

```hcl
auto_upgrade_nodes = false
```

Then manually upgrade:

```bash
gcloud container clusters upgrade <cluster-name> \
  --node-pool=<pool-name> \
  --cluster-version=1.28.x
```

## Monitoring & Logging

### Cloud Logging

Automatically collects:
- **System Components**: API server, scheduler, controller-manager logs
- **Workloads**: Container stdout/stderr

Access via:
```bash
gcloud logging read "resource.type=k8s_cluster"
```

### Cloud Monitoring

Metrics for:
- CPU, memory, disk, network per node/pod
- API server requests
- Cluster autoscaler activity

Dashboard: https://console.cloud.google.com/monitoring

## Security Best Practices

- ✅ Enable private nodes
- ✅ Use Workload Identity (never IAM keys)
- ✅ Enable Shielded GKE Nodes
- ✅ Restrict master authorized networks in production
- ✅ Enable Binary Authorization (admission control)
- ✅ Use VPC-native cluster (IP aliasing)
- ✅ Enable Cloud Armor for DDoS protection
- ✅ Regularly update cluster version

## Troubleshooting

### Nodes not ready

```bash
kubectl get nodes
kubectl describe node <node-name>
gcloud compute instances list --filter="name~<cluster-name>"
```

### Workload Identity not working

```bash
# Verify GSA exists
gcloud iam service-accounts list

# Verify binding
gcloud iam service-accounts get-iam-policy <gsa-email>

# Test from pod
kubectl run -it --rm debug --image=google/cloud-sdk:slim --restart=Never -- bash
gcloud auth list
```

### Private cluster access issues

Use Cloud Identity-Aware Proxy:

```bash
gcloud compute start-iap-tunnel <bastion-instance> 22 \
  --local-host-port=localhost:2222 \
  --zone=<zone>

kubectl --kubeconfig <kubeconfig> get nodes
```

## Migration from k3s/EKS

See [MIGRATION_GUIDE.md](../../docs/MIGRATION_GUIDE.md).

Key GKE differences:
- **Storage**: Uses GCE Persistent Disks instead of EBS
- **Ingress**: Uses GCP Load Balancer instead of ELB/ALB
- **Auth**: Workload Identity instead of IRSA
- **Costs**: Generally 20-30% cheaper than EKS for same specs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| google | ~> 5.0 |
| local | ~> 2.4 |
| null | ~> 3.2 |

## Resources

| Name | Type |
|------|------|
| google_container_cluster | resource |
| google_container_node_pool | resource |
| google_compute_network | resource |
| google_compute_subnetwork | resource |
| google_service_account | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name | `string` | n/a | yes |
| project_id | GCP project ID | `string` | n/a | yes |
| region | GCP region | `string` | `"us-central1"` | no |
| cluster_version | Kubernetes version | `string` | `"1.28"` | no |
| machine_type | Node machine type | `string` | `"n1-standard-2"` | no |

## Outputs

| Name | Description |
|------|-------------|
| kubeconfig_path | Path to kubeconfig file |
| cluster_endpoint | Kubernetes API endpoint |
| cluster_name | GKE cluster name |
<!-- END_TF_DOCS -->

