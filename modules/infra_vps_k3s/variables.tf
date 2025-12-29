variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "vps_host" {
  description = "VPS public IP address or hostname"
  type        = string
}

variable "vps_user" {
  description = "SSH user for VPS connection"
  type        = string
  default     = "root"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for VPS connection"
  type        = string
}

variable "provision_k3s" {
  description = "Whether to provision k3s (set to false if k3s is already installed)"
  type        = bool
  default     = true
}

variable "k3s_version" {
  description = "k3s version to install (e.g., v1.28.5+k3s1). Leave empty for latest stable"
  type        = string
  default     = "v1.28.5+k3s1"
}

variable "node_name" {
  description = "Name for the k3s node"
  type        = string
  default     = "k3s-master"
}

variable "enable_tls_san" {
  description = "Add VPS host to TLS SAN for API server certificate"
  type        = bool
  default     = true
}

variable "additional_k3s_flags" {
  description = "Additional flags to pass to k3s installation"
  type        = string
  default     = ""
}

variable "configure_firewall" {
  description = "Configure UFW firewall with basic rules"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}

