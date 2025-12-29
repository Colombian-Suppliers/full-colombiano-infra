# Same variables as dev - see ../dev/variables.tf
# The variables interface is identical across environments
# Only defaults differ via terraform.tfvars

variable "target_provider" {
  description = "Target infrastructure provider: vps, aws, or gcp"
  type        = string
  validation {
    condition     = contains(["vps", "aws", "gcp"], var.target_provider)
    error_message = "target_provider must be one of: vps, aws, gcp"
  }
}

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

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "aws_availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "aws_single_nat_gateway" {
  description = "Use single NAT gateway"
  type        = bool
  default     = false  # Multi-NAT for staging HA
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
  description = "EKS node capacity type"
  type        = string
  default     = "ON_DEMAND"  # Reliability for staging
}

variable "eks_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 6
}

variable "aws_route53_zone_arns" {
  description = "Route53 hosted zone ARNs"
  type        = list(string)
  default     = []
}

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
  description = "Create regional cluster"
  type        = bool
  default     = false  # Zonal acceptable for staging
}

variable "gke_machine_type" {
  description = "GKE node machine type"
  type        = string
  default     = "n1-standard-2"
}

variable "gke_preemptible_nodes" {
  description = "Use preemptible nodes"
  type        = bool
  default     = false  # Standard for staging
}

variable "gke_enable_autoscaling" {
  description = "Enable node autoscaling"
  type        = bool
  default     = true
}

variable "gke_min_node_count" {
  description = "Minimum nodes"
  type        = number
  default     = 2
}

variable "gke_max_node_count" {
  description = "Maximum nodes"
  type        = number
  default     = 6
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

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt"
  type        = string
}

variable "cert_manager_use_dns01" {
  description = "Use DNS01 challenge"
  type        = bool
  default     = true  # DNS01 recommended for staging
}

variable "enable_cert_manager" {
  description = "Enable cert-manager"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable external-dns"
  type        = bool
  default     = true  # Usually enabled for staging
}

variable "external_dns_domain_filters" {
  description = "Domain filters for external-dns"
  type        = list(string)
  default     = []
}

variable "enable_monitoring" {
  description = "Enable kube-prometheus-stack"
  type        = bool
  default     = true  # Usually enabled for staging
}

variable "prometheus_ingress_enabled" {
  description = "Enable ingress for Prometheus/Grafana"
  type        = bool
  default     = true
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

