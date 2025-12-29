# VPS k3s Infrastructure Module

This module provisions a k3s Kubernetes cluster on an existing VPS via SSH.

## Features

- Installs k3s with customizable version and flags
- Configures UFW firewall automatically
- Fetches kubeconfig and makes it available locally
- Supports both new installation and existing k3s clusters
- Idempotent operations

## Architecture Decision: Why No Traefik?

k3s ships with Traefik by default, but we **disable it** (`--disable traefik`) for the following reasons:

1. **Consistency**: To maintain a uniform platform layer across VPS/AWS/GCP, we use the same ingress controller everywhere (nginx-ingress)
2. **Feature Parity**: Enterprise features like external-dns and cert-manager work identically across providers
3. **Migration Path**: Moving from VPS to cloud requires no ingress reconfiguration
4. **Team Familiarity**: Single ingress controller to learn and troubleshoot

If you prefer Traefik, set `--disable traefik` to `false` in `additional_k3s_flags` and adjust the runtime_platform module accordingly.

## Usage

```hcl
module "k3s_cluster" {
  source = "../../modules/infra_vps_k3s"

  environment          = "dev"
  vps_host             = "203.0.113.10"
  vps_user             = "root"
  ssh_private_key_path = "~/.ssh/id_rsa"
  
  k3s_version          = "v1.28.5+k3s1"
  configure_firewall   = true
  
  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```

## Requirements

- Ubuntu 22.04+ or Debian 11+ on VPS
- SSH access with sudo privileges
- Minimum 2 vCPU, 4GB RAM
- 20GB+ disk space

## Provisioning Methods

### Method 1: SSH Provisioner (Default)

Uses Terraform's `null_resource` with `remote-exec` provisioner to install k3s via SSH.

**Pros**: Works with any VPS provider, no special requirements
**Cons**: Requires SSH access, slower than cloud-init

### Method 2: Cloud-Init (Alternative)

For providers supporting cloud-init (DigitalOcean, Hetzner, etc.), use the provided template:

```hcl
# Create VPS with cloud-init
resource "digitalocean_droplet" "k3s" {
  user_data = file("${path.module}/templates/cloud-init.yaml")
  # ...
}
```

**Pros**: Faster, integrated with VPS provisioning
**Cons**: Provider-specific, harder to debug

## Firewall Configuration

The module configures UFW with the following rules:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22   | TCP      | SSH |
| 80   | TCP      | HTTP (ingress) |
| 443  | TCP      | HTTPS (ingress) |
| 6443 | TCP      | Kubernetes API |

To disable firewall configuration:

```hcl
configure_firewall = false
```

## Outputs

- `kubeconfig_path`: Path to local kubeconfig file
- `cluster_endpoint`: Kubernetes API endpoint
- `ingress_ip`: Public IP for ingress traffic (same as VPS)

## Troubleshooting

### SSH Connection Fails

```bash
# Test SSH manually
ssh -i ~/.ssh/id_rsa root@<vps-ip>

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

### k3s Installation Fails

```bash
# SSH to VPS and check logs
ssh root@<vps-ip>
sudo journalctl -u k3s -f
```

### Kubeconfig Not Working

```bash
# Re-fetch kubeconfig
ssh root@<vps-ip> 'sudo cat /etc/rancher/k3s/k3s.yaml' | \
  sed 's/127.0.0.1/<vps-ip>/g' > ~/.kube/dev-k3s.yaml

# Test connection
kubectl --kubeconfig ~/.kube/dev-k3s.yaml get nodes
```

## Security Considerations

- **SSH Keys**: Never commit private keys to version control
- **Firewall**: Always enable firewall in production
- **k3s Token**: Store securely if adding worker nodes
- **API Access**: Consider restricting API server access by IP

## Migration Path

When ready to migrate to EKS/GKE:

1. The runtime_platform module remains unchanged
2. Only the infrastructure module is swapped
3. Applications deployed via ArgoCD/Helm continue to work
4. DNS changes point to new ingress IP

See [MIGRATION_GUIDE.md](../../docs/MIGRATION_GUIDE.md) for detailed steps.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| local | ~> 2.4 |
| null | ~> 3.2 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment name (dev, stg, prod) | `string` | n/a | yes |
| vps_host | VPS public IP address or hostname | `string` | n/a | yes |
| ssh_private_key_path | Path to SSH private key for VPS connection | `string` | n/a | yes |
| vps_user | SSH user for VPS connection | `string` | `"root"` | no |
| provision_k3s | Whether to provision k3s | `bool` | `true` | no |
| k3s_version | k3s version to install | `string` | `"v1.28.5+k3s1"` | no |
| configure_firewall | Configure UFW firewall | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| kubeconfig_path | Path to kubeconfig file |
| cluster_endpoint | Kubernetes API endpoint |
| ingress_ip | Public IP for ingress |
<!-- END_TF_DOCS -->

