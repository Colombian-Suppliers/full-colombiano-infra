# Same outputs as dev
# See ../dev/outputs.tf for documentation

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

output "quick_start_commands" {
  description = "Quick start commands"
  value = {
    export_kubeconfig = "export KUBECONFIG=${try(module.infra_vps[0].kubeconfig_path, module.infra_aws[0].kubeconfig_path, module.infra_gcp[0].kubeconfig_path, "")}"
    get_nodes = "kubectl get nodes"
    get_platform_pods = "kubectl get pods -n platform"
    get_ingress = "kubectl get svc -n platform ingress-nginx-controller"
    access_grafana = var.enable_monitoring && var.prometheus_ingress_enabled ? "https://${var.grafana_ingress_host}" : "kubectl port-forward -n platform svc/prometheus-grafana 3000:80"
  }
}

