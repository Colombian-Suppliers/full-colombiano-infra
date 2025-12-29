################################################################################
# Target Provider Selection
################################################################################

variable "target_provider" {
  description = "Target infrastructure provider: vps, aws, or gcp"
  type        = string
  validation {
    condition     = contains(["vps", "aws", "gcp"], var.target_provider)
    error_message = "target_provider must be one of: vps, aws, gcp"
  }
}

################################################################################
# VPS Configuration
################################################################################

variable "vps_host" {
  description = "VPS public IP address or hostname"
  type        = string
  default     = ""
}

variable "vps_user" {
  description = "SSH user for VPS"
  type        = string
  default     = "root"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "k3s_version" {
  description = "k3s version"
  type        = string
  default     = "v1.28.5+k3s1"
}

variable "vps_configure_firewall" {
  description = "Configure UFW firewall on VPS"
  type        = bool
  default     = true
}

################################################################################
# AWS Configuration
################################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "aws_single_nat_gateway" {
  description = "Use single NAT gateway (cost savings for dev)"
  type        = bool
  default     = true
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.28"
}

variable "eks_instance_types" {
  description = "EKS node instance types"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_capacity_type" {
  description = "EKS node capacity type (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"
}

variable "eks_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 1
}

variable "eks_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 4
}

variable "aws_route53_zone_arns" {
  description = "Route53 hosted zone ARNs for cert-manager and external-dns"
  type        = list(string)
  default     = []
}

################################################################################
# GCP Configuration
################################################################################

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gke_cluster_version" {
  description = "GKE cluster version"
  type        = string
  default     = "1.28"
}

variable "gke_regional_cluster" {
  description = "Create regional cluster (multi-zone)"
  type        = bool
  default     = false
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "e2-medium"
}

variable "gke_preemptible_nodes" {
  description = "Use preemptible (spot) nodes"
  type        = bool
  default     = true
}

variable "gke_enable_autoscaling" {
  description = "Enable node autoscaling"
  type        = bool
  default     = true
}

variable "gke_min_node_count" {
  description = "Minimum nodes"
  type        = number
  default     = 1
}

variable "gke_max_node_count" {
  description = "Maximum nodes"
  type        = number
  default     = 3
}

variable "gke_enable_private_nodes" {
  description = "Enable private nodes"
  type        = bool
  default     = true
}

variable "gke_enable_private_endpoint" {
  description = "Enable private endpoint"
  type        = bool
  default     = false
}

################################################################################
# Platform Configuration (Common)
################################################################################

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt notifications"
  type        = string
}

variable "cert_manager_use_dns01" {
  description = "Use DNS01 challenge (required for wildcard certs)"
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Enable cert-manager"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable external-dns"
  type        = bool
  default     = false
}

variable "external_dns_domain_filters" {
  description = "Domain filters for external-dns"
  type        = list(string)
  default     = []
}

variable "enable_monitoring" {
  description = "Enable kube-prometheus-stack"
  type        = bool
  default     = false
}

variable "prometheus_ingress_enabled" {
  description = "Enable ingress for Prometheus/Grafana"
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

