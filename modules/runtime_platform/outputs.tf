output "platform_namespace" {
  description = "Name of the platform namespace"
  value       = kubernetes_namespace.platform.metadata[0].name
}

output "apps_namespace" {
  description = "Name of the apps namespace"
  value       = kubernetes_namespace.apps.metadata[0].name
}

output "ingress_controller_name" {
  description = "Name of the ingress controller"
  value       = helm_release.nginx_ingress.name
}

output "cert_manager_name" {
  description = "Name of cert-manager release"
  value       = helm_release.cert_manager.name
}

output "metrics_server_name" {
  description = "Name of metrics-server release"
  value       = helm_release.metrics_server.name
}

output "external_dns_name" {
  description = "Name of external-dns release (if enabled)"
  value       = var.enable_external_dns ? helm_release.external_dns[0].name : null
}

output "kube_prometheus_name" {
  description = "Name of kube-prometheus-stack release (if enabled)"
  value       = var.enable_kube_prometheus ? helm_release.kube_prometheus[0].name : null
}

output "letsencrypt_staging_issuer" {
  description = "Name of Let's Encrypt staging ClusterIssuer"
  value       = "letsencrypt-staging"
}

output "letsencrypt_prod_issuer" {
  description = "Name of Let's Encrypt production ClusterIssuer"
  value       = "letsencrypt-prod"
}

output "platform_components" {
  description = "List of installed platform components"
  value = compact([
    "nginx-ingress",
    "cert-manager",
    "metrics-server",
    var.enable_external_dns ? "external-dns" : "",
    var.enable_kube_prometheus ? "kube-prometheus-stack" : ""
  ])
}

