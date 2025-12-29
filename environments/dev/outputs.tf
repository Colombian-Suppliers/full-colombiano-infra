################################################################################
# Infrastructure Outputs (Provider-Specific)
################################################################################

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value = try(
    module.infra_vps[0].kubeconfig_path,
    module.infra_aws[0].kubeconfig_path,
    module.infra_gcp[0].kubeconfig_path,
    null
  )
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value = try(
    module.infra_vps[0].cluster_endpoint,
    module.infra_aws[0].cluster_endpoint,
    module.infra_gcp[0].cluster_endpoint,
    null
  )
}

output "cluster_name" {
  description = "Kubernetes cluster name"
  value = try(
    module.infra_vps[0].cluster_name,
    module.infra_aws[0].cluster_name,
    module.infra_gcp[0].cluster_name,
    null
  )
}

output "ingress_ip" {
  description = "Public IP/hostname for ingress traffic"
  value = try(
    module.infra_vps[0].ingress_ip,
    "Run: kubectl get svc -n platform ingress-nginx-controller",
    "Run: kubectl get svc -n platform ingress-nginx-controller",
    null
  )
}

output "provider_type" {
  description = "Infrastructure provider type"
  value = try(
    module.infra_vps[0].provider_type,
    module.infra_aws[0].provider_type,
    module.infra_gcp[0].provider_type,
    null
  )
}

################################################################################
# Provider-Specific Outputs
################################################################################

# AWS EKS
output "eks_cluster_id" {
  description = "EKS cluster ID (AWS only)"
  value       = var.target_provider == "aws" ? try(module.infra_aws[0].cluster_id, null) : null
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN (AWS only)"
  value       = var.target_provider == "aws" ? try(module.infra_aws[0].oidc_provider_arn, null) : null
}

# GCP GKE
output "gke_cluster_location" {
  description = "GKE cluster location (GCP only)"
  value       = var.target_provider == "gcp" ? try(module.infra_gcp[0].cluster_location, null) : null
}

output "gke_workload_identity_pool" {
  description = "GKE Workload Identity pool (GCP only)"
  value       = var.target_provider == "gcp" ? try(module.infra_gcp[0].workload_identity_pool, null) : null
}

################################################################################
# Platform Outputs
################################################################################

output "platform_namespace" {
  description = "Platform namespace"
  value       = module.runtime_platform.platform_namespace
}

output "apps_namespace" {
  description = "Apps namespace"
  value       = module.runtime_platform.apps_namespace
}

output "platform_components" {
  description = "Installed platform components"
  value       = module.runtime_platform.platform_components
}

output "letsencrypt_issuers" {
  description = "Let's Encrypt ClusterIssuers"
  value = {
    staging    = module.runtime_platform.letsencrypt_staging_issuer
    production = module.runtime_platform.letsencrypt_prod_issuer
  }
}

################################################################################
# Quick Start Commands
################################################################################

output "quick_start_commands" {
  description = "Quick start commands for accessing the cluster"
  value = {
    export_kubeconfig = "export KUBECONFIG=${try(module.infra_vps[0].kubeconfig_path, module.infra_aws[0].kubeconfig_path, module.infra_gcp[0].kubeconfig_path, "")}"
    
    get_nodes = "kubectl get nodes"
    
    get_platform_pods = "kubectl get pods -n platform"
    
    get_ingress = "kubectl get svc -n platform ingress-nginx-controller"
    
    access_grafana = var.enable_monitoring && var.prometheus_ingress_enabled ? "https://${var.grafana_ingress_host}" : "kubectl port-forward -n platform svc/prometheus-grafana 3000:80"
  }
}

