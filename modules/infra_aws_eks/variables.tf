variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Base name for EKS cluster (will be prefixed with environment)"
  type        = string
  default     = "colombian-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to cluster endpoint"
  type        = bool
  default     = true
}

################################################################################
# VPC Configuration
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway (cheaper but less HA)"
  type        = bool
  default     = false
}

################################################################################
# Node Group Configuration
################################################################################

variable "node_instance_types" {
  description = "List of instance types for node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 10
}

variable "node_group_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

################################################################################
# IRSA Configuration
################################################################################

variable "enable_cert_manager_irsa" {
  description = "Enable IRSA for cert-manager"
  type        = bool
  default     = true
}

variable "cert_manager_route53_zone_arns" {
  description = "ARNs of Route53 hosted zones for cert-manager DNS01 challenges"
  type        = list(string)
  default     = []
}

variable "enable_external_dns_irsa" {
  description = "Enable IRSA for external-dns"
  type        = bool
  default     = false
}

variable "external_dns_route53_zone_arns" {
  description = "ARNs of Route53 hosted zones for external-dns"
  type        = list(string)
  default     = []
}

################################################################################
# AWS Auth
################################################################################

variable "additional_aws_auth_roles" {
  description = "Additional IAM roles to add to aws-auth ConfigMap"
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "additional_aws_auth_users" {
  description = "Additional IAM users to add to aws-auth ConfigMap"
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

################################################################################
# Tags
################################################################################

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

