terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

locals {
  environment = "dev"
  
  # Common tags/labels
  common_tags = {
    Environment = local.environment
    Project     = "colombian-supply"
    ManagedBy   = "terraform"
  }
}

################################################################################
# Provider Configuration (conditional based on target_provider)
################################################################################

provider "aws" {
  region = var.aws_region
  
  # Only configure if target is AWS
  skip_region_validation = var.target_provider != "aws"
  
  default_tags {
    tags = local.common_tags
  }
}

provider "google" {
  project = var.gcp_project_id != "" ? var.gcp_project_id : "dummy-project"
  region  = var.gcp_region
  
  # Only configure if target is GCP
}

################################################################################
# Infrastructure Layer (Provider-Specific)
################################################################################

# VPS k3s
module "infra_vps" {
  count  = var.target_provider == "vps" ? 1 : 0
  source = "../../modules/infra_vps_k3s"

  environment          = local.environment
  vps_host             = var.vps_host
  vps_user             = var.vps_user
  ssh_private_key_path = var.ssh_private_key_path
  k3s_version          = var.k3s_version
  configure_firewall   = var.vps_configure_firewall
  
  tags = local.common_tags
}

# AWS EKS
module "infra_aws" {
  count  = var.target_provider == "aws" ? 1 : 0
  source = "../../modules/infra_aws_eks"

  environment     = local.environment
  region          = var.aws_region
  cluster_version = var.eks_cluster_version
  
  # VPC
  vpc_cidr             = var.aws_vpc_cidr
  availability_zones   = var.aws_availability_zones
  single_nat_gateway   = var.aws_single_nat_gateway
  
  # Node Group
  node_instance_types     = var.eks_instance_types
  node_capacity_type      = var.eks_capacity_type
  node_group_desired_size = var.eks_desired_size
  node_group_min_size     = var.eks_min_size
  node_group_max_size     = var.eks_max_size
  
  # IRSA
  enable_cert_manager_irsa      = var.enable_cert_manager
  cert_manager_route53_zone_arns = var.aws_route53_zone_arns
  
  enable_external_dns_irsa      = var.enable_external_dns
  external_dns_route53_zone_arns = var.aws_route53_zone_arns
  
  tags = local.common_tags
}

# GCP GKE
module "infra_gcp" {
  count  = var.target_provider == "gcp" ? 1 : 0
  source = "../../modules/infra_gcp_gke"

  environment      = local.environment
  project_id       = var.gcp_project_id
  region           = var.gcp_region
  cluster_version  = var.gke_cluster_version
  regional_cluster = var.gke_regional_cluster
  
  # Node Pool
  machine_type       = var.gke_machine_type
  preemptible_nodes  = var.gke_preemptible_nodes
  enable_autoscaling = var.gke_enable_autoscaling
  min_node_count     = var.gke_min_node_count
  max_node_count     = var.gke_max_node_count
  
  # Private cluster
  enable_private_nodes    = var.gke_enable_private_nodes
  enable_private_endpoint = var.gke_enable_private_endpoint
  
  # Workload Identity
  enable_cert_manager_workload_identity    = var.enable_cert_manager
  enable_external_dns_workload_identity    = var.enable_external_dns
  
  labels = local.common_tags
}

################################################################################
# Kubernetes Provider Configuration (uses kubeconfig from infra layer)
################################################################################

provider "kubernetes" {
  config_path = try(
    module.infra_vps[0].kubeconfig_path,
    module.infra_aws[0].kubeconfig_path,
    module.infra_gcp[0].kubeconfig_path,
    ""
  )
}

provider "helm" {
  kubernetes {
    config_path = try(
      module.infra_vps[0].kubeconfig_path,
      module.infra_aws[0].kubeconfig_path,
      module.infra_gcp[0].kubeconfig_path,
      ""
    )
  }
}

################################################################################
# Runtime Platform Layer (Provider-Agnostic)
################################################################################

module "runtime_platform" {
  source = "../../modules/runtime_platform"
  
  depends_on = [
    module.infra_vps,
    module.infra_aws,
    module.infra_gcp
  ]

  environment   = local.environment
  provider_type = var.target_provider == "vps" ? "vps-k3s" : var.target_provider == "aws" ? "aws-eks" : "gcp-gke"
  
  # cert-manager
  letsencrypt_email      = var.letsencrypt_email
  cert_manager_use_dns01 = var.cert_manager_use_dns01
  
  # AWS-specific
  cert_manager_iam_role_arn = var.target_provider == "aws" ? try(module.infra_aws[0].cert_manager_role_arn, "") : ""
  aws_region                = var.target_provider == "aws" ? var.aws_region : ""
  
  # GCP-specific
  cert_manager_gcp_sa_email = var.target_provider == "gcp" ? try(module.infra_gcp[0].cert_manager_service_account, "") : ""
  gcp_project_id            = var.target_provider == "gcp" ? var.gcp_project_id : ""
  
  # external-dns (optional)
  enable_external_dns         = var.enable_external_dns
  external_dns_domain_filters = var.external_dns_domain_filters
  external_dns_iam_role_arn   = var.target_provider == "aws" ? try(module.infra_aws[0].external_dns_role_arn, "") : ""
  external_dns_gcp_sa_email   = var.target_provider == "gcp" ? try(module.infra_gcp[0].external_dns_service_account, "") : ""
  
  # kube-prometheus-stack (optional)
  enable_kube_prometheus     = var.enable_monitoring
  prometheus_ingress_enabled = var.prometheus_ingress_enabled
  prometheus_ingress_host    = var.prometheus_ingress_host
  grafana_ingress_host       = var.grafana_ingress_host
}

