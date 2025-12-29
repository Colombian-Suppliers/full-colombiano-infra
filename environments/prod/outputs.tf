# Same outputs as dev/stg

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
    "Run: kubectl get svc -n platform ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'",
    "Run: kubectl get svc -n platform ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'",
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

output "monitoring_urls" {
  description = "Monitoring URLs (production)"
  value = var.enable_monitoring ? {
    grafana    = var.prometheus_ingress_enabled ? "https://${var.grafana_ingress_host}" : "kubectl port-forward -n platform svc/prometheus-grafana 3000:80"
    prometheus = var.prometheus_ingress_enabled ? "https://${var.prometheus_ingress_host}" : "kubectl port-forward -n platform svc/prometheus-kube-prometheus-prometheus 9090:9090"
  } : null
}

