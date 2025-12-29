# AWS EKS Infrastructure Module

This module provisions a production-ready EKS cluster with VPC, node groups, and IRSA roles for platform components.

## Features

- **VPC**: Multi-AZ VPC with public/private subnets and NAT gateways
- **EKS Cluster**: Managed Kubernetes cluster with configurable version
- **Managed Node Groups**: Auto-scaling node groups with spot/on-demand support
- **IRSA (IAM Roles for Service Accounts)**:
  - EBS CSI Driver (required for persistent volumes)
  - cert-manager (for Route53 DNS01 challenges)
  - external-dns (for automatic DNS record management)
- **Security**: Security groups, OIDC provider, encrypted communication
- **Observability**: CloudWatch logging integration

## Architecture

```
┌────────────────────────────────────────────────────────┐
│                    AWS Account                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │  VPC (10.0.0.0/16)                              │  │
│  │                                                  │  │
│  │  ┌──────────────┐  ┌──────────────┐            │  │
│  │  │ Public Subnet│  │ Public Subnet│            │  │
│  │  │  (AZ-a)      │  │  (AZ-b)      │            │  │
│  │  │  NAT Gateway │  │  NAT Gateway │            │  │
│  │  └──────┬───────┘  └──────┬───────┘            │  │
│  │         │                  │                     │  │
│  │  ┌──────▼───────┐  ┌──────▼───────┐            │  │
│  │  │Private Subnet│  │Private Subnet│            │  │
│  │  │  (AZ-a)      │  │  (AZ-b)      │            │  │
│  │  │              │  │              │            │  │
│  │  │  EKS Nodes   │  │  EKS Nodes   │            │  │
│  │  └──────────────┘  └──────────────┘            │  │
│  │                                                  │  │
│  │  EKS Control Plane (Managed by AWS)             │  │
│  └─────────────────────────────────────────────────┘  │
│                                                        │
│  IRSA: cert-manager, external-dns, ebs-csi-driver    │
└────────────────────────────────────────────────────────┘
```

## Usage

```hcl
module "eks_cluster" {
  source = "../../modules/infra_aws_eks"

  environment     = "stg"
  region          = "us-east-1"
  cluster_version = "1.28"

  # VPC Configuration
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b"]
  single_nat_gateway   = false  # Use true for dev to save costs

  # Node Group
  node_instance_types    = ["t3.medium", "t3a.medium"]
  node_capacity_type     = "ON_DEMAND"
  node_group_desired_size = 2
  node_group_min_size     = 1
  node_group_max_size     = 4

  # IRSA
  enable_cert_manager_irsa = true
  cert_manager_route53_zone_arns = [
    "arn:aws:route53:::hostedzone/Z1234567890ABC"
  ]

  enable_external_dns_irsa = true
  external_dns_route53_zone_arns = [
    "arn:aws:route53:::hostedzone/Z1234567890ABC"
  ]

  tags = {
    Project = "colombian-supply"
  }
}
```

## Cost Optimization

### Development Environment

```hcl
# Minimal cost configuration for dev
single_nat_gateway      = true              # ~$32/month instead of ~$96/month
node_instance_types     = ["t3.small"]      # Smaller instances
node_capacity_type      = "SPOT"            # 70% cheaper
node_group_desired_size = 1                 # Single node
```

**Estimated monthly cost**: ~$60-80 USD

### Production Environment

```hcl
# High availability configuration
single_nat_gateway      = false             # Multi-AZ NAT
node_instance_types     = ["t3.medium"]
node_capacity_type      = "ON_DEMAND"       # Reliability
node_group_desired_size = 3                 # Multi-node
```

**Estimated monthly cost**: ~$200-300 USD

## IRSA Setup

### cert-manager with Route53

cert-manager uses IRSA to perform DNS01 challenges without storing AWS credentials:

1. Create Route53 hosted zone
2. Get zone ARN: `aws route53 list-hosted-zones`
3. Pass ARN to `cert_manager_route53_zone_arns`
4. Module creates IAM role with proper permissions
5. runtime_platform module annotates cert-manager ServiceAccount

### external-dns with Route53

Similar to cert-manager:

```hcl
enable_external_dns_irsa = true
external_dns_route53_zone_arns = ["arn:aws:route53:::hostedzone/YOUR_ZONE_ID"]
```

## Networking

### VPC Design

- **CIDR**: `/16` provides 65,536 IPs (plenty for large deployments)
- **Public Subnets**: `/24` each (254 IPs) - for load balancers
- **Private Subnets**: `/24` each (254 IPs) - for EKS nodes
- **Multi-AZ**: Spans 2-3 availability zones for HA

### Security Groups

The module creates:

1. **Cluster Security Group**: Controls access to EKS API server
2. **Node Security Group**: Controls node-to-node and pod-to-pod communication
3. **Additional Rules**: Allows ephemeral ports, inter-node traffic

### NAT Gateways

- **Single NAT Gateway** (dev): All private subnets route through one NAT in AZ-a
  - Pro: 67% cost savings
  - Con: No HA - if AZ-a fails, cluster loses internet
  
- **Multi-NAT Gateway** (prod): Each AZ has its own NAT
  - Pro: High availability
  - Con: Linear cost with number of AZs

## Authentication

### AWS Auth ConfigMap

The module automatically manages `aws-auth` ConfigMap. To add IAM users/roles:

```hcl
additional_aws_auth_users = [
  {
    userarn  = "arn:aws:iam::123456789012:user/devops-user"
    username = "devops-user"
    groups   = ["system:masters"]
  }
]

additional_aws_auth_roles = [
  {
    rolearn  = "arn:aws:iam::123456789012:role/EKSAdminRole"
    username = "eks-admin"
    groups   = ["system:masters"]
  }
]
```

### Kubeconfig

The module automatically generates kubeconfig at `.kube/<env>-eks.yaml`:

```bash
export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes
```

Or update existing kubeconfig:

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

## Cluster Addons

The module installs essential EKS addons:

- **coredns**: Cluster DNS
- **kube-proxy**: Network proxy
- **vpc-cni**: AWS VPC networking for pods
- **aws-ebs-csi-driver**: EBS volume provisioner

These run on EKS-managed versions and auto-update.

## Scaling

### Cluster Autoscaler

To enable automatic node scaling based on pod demand:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

The node group's min/max size controls autoscaling bounds.

### Vertical Pod Autoscaler

For pod resource optimization:

```bash
kubectl apply -f https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/deploy
```

## Monitoring

### CloudWatch Container Insights

Enable with:

```bash
aws eks update-cluster-config \
  --name <cluster-name> \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

## Troubleshooting

### Nodes not joining cluster

Check IAM role and security groups:

```bash
aws eks describe-cluster --name <cluster-name> --query cluster.roleArn
kubectl get nodes
kubectl describe node <node-name>
```

### IRSA not working

Verify OIDC provider:

```bash
aws eks describe-cluster --name <cluster-name> --query cluster.identity.oidc.issuer
aws iam list-open-id-connect-providers
```

### VPC errors

Check VPC and subnet tags:

```bash
aws ec2 describe-subnets --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=shared"
```

## Migration from k3s

See [MIGRATION_GUIDE.md](../../docs/MIGRATION_GUIDE.md) for step-by-step instructions.

Key differences:
- **Ingress IP**: VPS has static IP; EKS uses ELB DNS name
- **Storage**: k3s uses local-path; EKS uses EBS via CSI
- **DNS**: Update records to point to ELB endpoint

## Security Best Practices

- ✅ Enable private endpoint access
- ✅ Restrict public endpoint to specific CIDRs in production
- ✅ Use IRSA instead of IAM user credentials
- ✅ Enable cluster logging to CloudWatch
- ✅ Regularly update cluster version
- ✅ Use Secrets Manager for sensitive data
- ✅ Enable GuardDuty for threat detection

## Disaster Recovery

### Backup

```bash
# Backup cluster state
velero install --provider aws --bucket <backup-bucket> --backup-location-config region=<region>
velero backup create cluster-backup
```

### Restore

See [RUNBOOK.md](../../docs/RUNBOOK.md) for DR procedures.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | ~> 5.0 |
| kubernetes | ~> 2.24 |
| local | ~> 2.4 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| vpc | terraform-aws-modules/vpc/aws | ~> 5.0 |
| eks | terraform-aws-modules/eks/aws | ~> 19.0 |
| ebs_csi_driver_irsa | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.0 |
| cert_manager_irsa | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.0 |
| external_dns_irsa | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name | `string` | n/a | yes |
| region | AWS region | `string` | `"us-east-1"` | no |
| cluster_version | Kubernetes version | `string` | `"1.28"` | no |
| node_instance_types | Instance types | `list(string)` | `["t3.medium"]` | no |

## Outputs

| Name | Description |
|------|-------------|
| kubeconfig_path | Path to kubeconfig file |
| cluster_endpoint | Kubernetes API endpoint |
| cluster_name | EKS cluster name |
<!-- END_TF_DOCS -->

