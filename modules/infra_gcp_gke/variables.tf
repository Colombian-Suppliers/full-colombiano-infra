variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone (used for zonal clusters)"
  type        = string
  default     = "us-central1-a"
}

variable "regional_cluster" {
  description = "Create a regional (multi-zone) cluster instead of zonal"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Base name for GKE cluster (will be prefixed with environment)"
  type        = string
  default     = "colombian-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for GKE cluster"
  type        = string
  default     = "1.28"
}

################################################################################
# Network Configuration
################################################################################

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR block for pods secondary range"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for services secondary range"
  type        = string
  default     = "10.30.0.0/16"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master (used for private clusters)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "List of CIDR blocks that can access the cluster API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

################################################################################
# Cluster Configuration
################################################################################

variable "enable_private_nodes" {
  description = "Enable private IP addresses for nodes"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint (disable public access to master)"
  type        = bool
  default     = false
}

variable "enable_network_policy" {
  description = "Enable network policy (Calico)"
  type        = bool
  default     = false
}

variable "enable_filestore_csi" {
  description = "Enable Google Filestore CSI driver"
  type        = bool
  default     = false
}

variable "enable_managed_prometheus" {
  description = "Enable GCP Managed Prometheus"
  type        = bool
  default     = false
}

variable "maintenance_window_start_time" {
  description = "Start time for maintenance window (HH:MM format in UTC)"
  type        = string
  default     = "03:00"
}

################################################################################
# Node Pool Configuration
################################################################################

variable "machine_type" {
  description = "Machine type for nodes"
  type        = string
  default     = "n1-standard-2"
}

variable "disk_size_gb" {
  description = "Disk size for nodes in GB"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "Disk type for nodes (pd-standard or pd-ssd)"
  type        = string
  default     = "pd-standard"
}

variable "preemptible_nodes" {
  description = "Use preemptible (spot) nodes"
  type        = bool
  default     = false
}

variable "node_count" {
  description = "Number of nodes per zone (for non-autoscaling)"
  type        = number
  default     = 1
}

variable "enable_autoscaling" {
  description = "Enable node autoscaling"
  type        = bool
  default     = true
}

variable "min_node_count" {
  description = "Minimum number of nodes (zonal cluster)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes (zonal cluster)"
  type        = number
  default     = 10
}

variable "min_node_count_per_zone" {
  description = "Minimum number of nodes per zone (regional cluster)"
  type        = number
  default     = 1
}

variable "max_node_count_per_zone" {
  description = "Maximum number of nodes per zone (regional cluster)"
  type        = number
  default     = 3
}

variable "auto_upgrade_nodes" {
  description = "Enable automatic node upgrades"
  type        = bool
  default     = true
}

################################################################################
# Workload Identity
################################################################################

variable "enable_cert_manager_workload_identity" {
  description = "Enable Workload Identity for cert-manager"
  type        = bool
  default     = true
}

variable "enable_external_dns_workload_identity" {
  description = "Enable Workload Identity for external-dns"
  type        = bool
  default     = false
}

################################################################################
# Labels
################################################################################

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default     = {}
}

