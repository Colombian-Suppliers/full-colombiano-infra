terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  cluster_name = "${var.environment}-${var.cluster_name}"
  
  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "terraform"
      provider    = "gcp-gke"
    }
  )

  kubeconfig_path = "${path.root}/../../.kube/${var.environment}-gke.yaml"
}

################################################################################
# VPC Network
################################################################################

resource "google_compute_network" "vpc" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${local.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  secondary_ip_range {
    range_name    = "${local.cluster_name}-pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "${local.cluster_name}-services"
    ip_cidr_range = var.services_cidr
  }

  private_ip_google_access = true
}

################################################################################
# Cloud Router & NAT (for private nodes)
################################################################################

resource "google_compute_router" "router" {
  name    = "${local.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = var.project_id

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

################################################################################
# Firewall Rules
################################################################################

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.cluster_name}-allow-ssh"
  network = google_compute_network.vpc.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.authorized_networks
}

################################################################################
# GKE Cluster
################################################################################

resource "google_service_account" "gke_nodes" {
  account_id   = "${local.cluster_name}-nodes"
  display_name = "Service Account for GKE nodes"
  project      = var.project_id
}

resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "primary" {
  name     = local.cluster_name
  location = var.regional_cluster ? var.region : var.zone
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Kubernetes version
  min_master_version = var.cluster_version

  # Network configuration
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # IP allocation policy for VPC-native cluster
  ip_allocation_policy {
    cluster_secondary_range_name  = "${local.cluster_name}-pods"
    services_secondary_range_name = "${local.cluster_name}-services"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }

    network_policy_config {
      disabled = var.enable_network_policy ? false : true
    }

    gcp_filestore_csi_driver_config {
      enabled = var.enable_filestore_csi
    }
  }

  # Network policy
  network_policy {
    enabled  = var.enable_network_policy
    provider = var.enable_network_policy ? "PROVIDER_UNSPECIFIED" : null
  }

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Master authorized networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value
          display_name = "Authorized network ${cidr_blocks.key}"
        }
      }
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_window_start_time
    }
  }

  # Logging and monitoring
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    
    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  # Resource labels
  resource_labels = local.common_labels

  # Lifecycle
  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config
    ]
  }

  depends_on = [
    google_project_iam_member.gke_nodes_roles
  ]
}

################################################################################
# Node Pool
################################################################################

resource "google_container_node_pool" "primary_nodes" {
  name       = "${local.cluster_name}-node-pool"
  location   = var.regional_cluster ? var.region : var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id

  node_count = var.regional_cluster ? null : var.node_count
  
  dynamic "autoscaling" {
    for_each = var.enable_autoscaling ? [1] : []
    content {
      min_node_count = var.regional_cluster ? var.min_node_count_per_zone : var.min_node_count
      max_node_count = var.regional_cluster ? var.max_node_count_per_zone : var.max_node_count
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = var.auto_upgrade_nodes
  }

  node_config {
    preemptible  = var.preemptible_nodes
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type

    # Service account
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Labels
    labels = merge(
      local.common_labels,
      {
        node_pool = "primary"
      }
    )

    # Tags for firewall rules
    tags = ["gke-node", "${local.cluster_name}-node"]

    # Metadata
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

################################################################################
# Workload Identity for cert-manager
################################################################################

resource "google_service_account" "cert_manager" {
  count        = var.enable_cert_manager_workload_identity ? 1 : 0
  account_id   = "${local.cluster_name}-cert-manager"
  display_name = "Service Account for cert-manager"
  project      = var.project_id
}

resource "google_project_iam_member" "cert_manager_dns" {
  count   = var.enable_cert_manager_workload_identity ? 1 : 0
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager[0].email}"
}

resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  count              = var.enable_cert_manager_workload_identity ? 1 : 0
  service_account_id = google_service_account.cert_manager[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[platform/cert-manager]"
}

################################################################################
# Workload Identity for external-dns
################################################################################

resource "google_service_account" "external_dns" {
  count        = var.enable_external_dns_workload_identity ? 1 : 0
  account_id   = "${local.cluster_name}-external-dns"
  display_name = "Service Account for external-dns"
  project      = var.project_id
}

resource "google_project_iam_member" "external_dns_dns" {
  count   = var.enable_external_dns_workload_identity ? 1 : 0
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns[0].email}"
}

resource "google_service_account_iam_member" "external_dns_workload_identity" {
  count              = var.enable_external_dns_workload_identity ? 1 : 0
  service_account_id = google_service_account.external_dns[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[platform/external-dns]"
}

################################################################################
# Kubeconfig Generation
################################################################################

resource "null_resource" "get_credentials" {
  depends_on = [google_container_cluster.primary]

  triggers = {
    cluster_name = local.cluster_name
    project      = var.project_id
    location     = var.regional_cluster ? var.region : var.zone
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p $(dirname ${local.kubeconfig_path})
      gcloud container clusters get-credentials ${local.cluster_name} \
        --region ${var.regional_cluster ? var.region : ""} \
        --zone ${var.regional_cluster ? "" : var.zone} \
        --project ${var.project_id} \
        --internal-ip=${var.enable_private_endpoint}
      
      # Export to specific kubeconfig file
      KUBECONFIG=~/.kube/config:${local.kubeconfig_path} kubectl config view --flatten > /tmp/merged_config
      mv /tmp/merged_config ${local.kubeconfig_path}
      chmod 600 ${local.kubeconfig_path}
    EOT
  }
}

# Wait for cluster to be ready
resource "null_resource" "wait_for_cluster" {
  depends_on = [null_resource.get_credentials]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG=${local.kubeconfig_path}
      
      for i in {1..30}; do
        if kubectl get nodes >/dev/null 2>&1; then
          echo "Cluster is ready"
          exit 0
        fi
        echo "Waiting for cluster... ($i/30)"
        sleep 10
      done
      
      echo "Cluster failed to become ready"
      exit 1
    EOT
  }
}

