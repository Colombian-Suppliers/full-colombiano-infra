output "kubeconfig_path" {
  description = "Path to kubeconfig file for cluster access"
  value       = local.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = "https://${var.vps_host}:6443"
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = "${var.environment}-k3s-cluster"
}

output "vps_host" {
  description = "VPS host IP address"
  value       = var.vps_host
}

output "k3s_version" {
  description = "Installed k3s version"
  value       = var.k3s_version
}

output "cluster_info" {
  description = "Cluster information (version, nodes count)"
  value = var.provision_k3s && length(data.external.cluster_info) > 0 ? {
    version  = try(data.external.cluster_info[0].result.version, "unknown")
    nodes    = try(data.external.cluster_info[0].result.nodes, "0")
    endpoint = try(data.external.cluster_info[0].result.endpoint, "unknown")
  } : null
}

output "ingress_ip" {
  description = "Public IP for ingress traffic (same as VPS host)"
  value       = var.vps_host
}

output "provider_type" {
  description = "Infrastructure provider type"
  value       = "vps-k3s"
}

