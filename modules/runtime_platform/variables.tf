variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "provider_type" {
  description = "Infrastructure provider type (vps-k3s, aws-eks, gcp-gke)"
  type        = string
  validation {
    condition     = contains(["vps-k3s", "aws-eks", "gcp-gke"], var.provider_type)
    error_message = "provider_type must be one of: vps-k3s, aws-eks, gcp-gke"
  }
}

################################################################################
# Ingress Controller
################################################################################

variable "nginx_ingress_version" {
  description = "Version of nginx-ingress Helm chart"
  type        = string
  default     = "4.9.0"
}

variable "ingress_replica_count" {
  description = "Number of ingress controller replicas"
  type        = number
  default     = 2
}

################################################################################
# cert-manager
################################################################################

variable "cert_manager_version" {
  description = "Version of cert-manager Helm chart"
  type        = string
  default     = "v1.13.3"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
}

variable "cert_manager_use_dns01" {
  description = "Use DNS01 challenge instead of HTTP01 (required for wildcard certs)"
  type        = bool
  default     = false
}

# AWS-specific
variable "cert_manager_iam_role_arn" {
  description = "IAM role ARN for cert-manager (AWS IRSA)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region (required if provider_type is aws-eks)"
  type        = string
  default     = ""
}

# GCP-specific
variable "cert_manager_gcp_sa_email" {
  description = "GCP service account email for cert-manager (Workload Identity)"
  type        = string
  default     = ""
}

variable "gcp_project_id" {
  description = "GCP project ID (required if provider_type is gcp-gke)"
  type        = string
  default     = ""
}

################################################################################
# metrics-server
################################################################################

variable "metrics_server_version" {
  description = "Version of metrics-server Helm chart"
  type        = string
  default     = "3.11.0"
}

################################################################################
# external-dns
################################################################################

variable "enable_external_dns" {
  description = "Enable external-dns for automatic DNS record management"
  type        = bool
  default     = false
}

variable "external_dns_version" {
  description = "Version of external-dns Helm chart"
  type        = string
  default     = "1.14.0"
}

variable "external_dns_domain_filters" {
  description = "List of domains to manage with external-dns"
  type        = list(string)
  default     = []
}

variable "external_dns_iam_role_arn" {
  description = "IAM role ARN for external-dns (AWS IRSA)"
  type        = string
  default     = ""
}

variable "external_dns_gcp_sa_email" {
  description = "GCP service account email for external-dns (Workload Identity)"
  type        = string
  default     = ""
}

################################################################################
# kube-prometheus-stack
################################################################################

variable "enable_kube_prometheus" {
  description = "Enable kube-prometheus-stack for monitoring"
  type        = bool
  default     = false
}

variable "kube_prometheus_version" {
  description = "Version of kube-prometheus-stack Helm chart"
  type        = string
  default     = "55.5.0"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size"
  type        = string
  default     = "50Gi"
}

variable "prometheus_ingress_enabled" {
  description = "Enable ingress for Prometheus"
  type        = bool
  default     = false
}

variable "prometheus_ingress_host" {
  description = "Ingress hostname for Prometheus"
  type        = string
  default     = ""
}

variable "grafana_ingress_host" {
  description = "Ingress hostname for Grafana"
  type        = string
  default     = ""
}

