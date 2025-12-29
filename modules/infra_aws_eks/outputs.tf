output "kubeconfig_path" {
  description = "Path to kubeconfig file for cluster access"
  value       = local.kubeconfig_path
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.cluster_name
}

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = module.ebs_csi_driver_irsa.iam_role_arn
}

output "cert_manager_role_arn" {
  description = "IAM role ARN for cert-manager (if enabled)"
  value       = var.enable_cert_manager_irsa ? module.cert_manager_irsa[0].iam_role_arn : null
}

output "external_dns_role_arn" {
  description = "IAM role ARN for external-dns (if enabled)"
  value       = var.enable_external_dns_irsa ? module.external_dns_irsa[0].iam_role_arn : null
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "provider_type" {
  description = "Infrastructure provider type"
  value       = "aws-eks"
}

# Output for kubectl configuration
output "kubectl_config_command" {
  description = "Command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.region}"
}

