output "kubeconfig_path" {
  description = "Path to kubeconfig file for cluster access"
  value       = local.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = local.cluster_name
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.primary.id
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64 encoded)"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Cluster location (region or zone)"
  value       = google_container_cluster.primary.location
}

output "cluster_type" {
  description = "Cluster type (regional or zonal)"
  value       = var.regional_cluster ? "regional" : "zonal"
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "Subnet CIDR block"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "pods_cidr" {
  description = "Pods secondary CIDR range"
  value       = var.pods_cidr
}

output "services_cidr" {
  description = "Services secondary CIDR range"
  value       = var.services_cidr
}

output "node_pool_name" {
  description = "Node pool name"
  value       = google_container_node_pool.primary_nodes.name
}

output "node_service_account" {
  description = "Service account email for GKE nodes"
  value       = google_service_account.gke_nodes.email
}

output "cert_manager_service_account" {
  description = "Service account email for cert-manager (if enabled)"
  value       = var.enable_cert_manager_workload_identity ? google_service_account.cert_manager[0].email : null
}

output "external_dns_service_account" {
  description = "Service account email for external-dns (if enabled)"
  value       = var.enable_external_dns_workload_identity ? google_service_account.external_dns[0].email : null
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "provider_type" {
  description = "Infrastructure provider type"
  value       = "gcp-gke"
}

# Output for kubectl configuration
output "kubectl_config_command" {
  description = "Command to update local kubeconfig"
  value       = var.regional_cluster ? "gcloud container clusters get-credentials ${local.cluster_name} --region ${var.region} --project ${var.project_id}" : "gcloud container clusters get-credentials ${local.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

output "workload_identity_pool" {
  description = "Workload Identity pool"
  value       = "${var.project_id}.svc.id.goog"
}

