# Production variables - same interface as dev/stg
# Production defaults favor reliability over cost

variable "target_provider" {
  description = "Target infrastructure provider"
  type        = string
  validation {
    condition     = contains(["vps", "aws", "gcp"], var.target_provider)
    error_message = "target_provider must be one of: vps, aws, gcp"
  }
}

variable "vps_host" {
  type    = string
  default = ""
}

variable "vps_user" {
  type    = string
  default = "root"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_rsa"
}

variable "k3s_version" {
  type    = string
  default = "v1.28.5+k3s1"
}

variable "vps_configure_firewall" {
  type    = bool
  default = true
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

variable "aws_availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "aws_single_nat_gateway" {
  type    = bool
  default = false  # Never single NAT in production
}

variable "eks_cluster_version" {
  type    = string
  default = "1.28"
}

variable "eks_instance_types" {
  type    = list(string)
  default = ["t3.large"]  # Larger for production
}

variable "eks_capacity_type" {
  type    = string
  default = "ON_DEMAND"  # Never SPOT in production
}

variable "eks_desired_size" {
  type    = number
  default = 3
}

variable "eks_min_size" {
  type    = number
  default = 3
}

variable "eks_max_size" {
  type    = number
  default = 10
}

variable "aws_route53_zone_arns" {
  type    = list(string)
  default = []
}

variable "gcp_project_id" {
  type    = string
  default = ""
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gke_cluster_version" {
  type    = string
  default = "1.28"
}

variable "gke_regional_cluster" {
  type    = bool
  default = true  # Regional for production HA
}

variable "gke_machine_type" {
  type    = string
  default = "n1-standard-4"
}

variable "gke_preemptible_nodes" {
  type    = bool
  default = false  # Never preemptible in production
}

variable "gke_enable_autoscaling" {
  type    = bool
  default = true
}

variable "gke_min_node_count" {
  type    = number
  default = 3
}

variable "gke_max_node_count" {
  type    = number
  default = 10
}

variable "gke_enable_private_nodes" {
  type    = bool
  default = true
}

variable "gke_enable_private_endpoint" {
  type    = bool
  default = false
}

variable "letsencrypt_email" {
  type = string
}

variable "cert_manager_use_dns01" {
  type    = bool
  default = true
}

variable "enable_cert_manager" {
  type    = bool
  default = true
}

variable "enable_external_dns" {
  type    = bool
  default = true
}

variable "external_dns_domain_filters" {
  type    = list(string)
  default = []
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "prometheus_ingress_enabled" {
  type    = bool
  default = true
}

variable "prometheus_ingress_host" {
  type    = string
  default = ""
}

variable "grafana_ingress_host" {
  type    = string
  default = ""
}

