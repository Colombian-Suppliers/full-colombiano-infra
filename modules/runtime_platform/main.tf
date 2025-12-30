terraform {
  required_version = ">= 1.6.0"
  required_providers {
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
  # Provider-specific configurations
  ingress_class = var.provider_type == "vps-k3s" ? "nginx" : "nginx"
  
  # cert-manager service account annotations by provider
  cert_manager_sa_annotations = var.provider_type == "aws-eks" && var.cert_manager_iam_role_arn != "" ? {
    "eks.amazonaws.com/role-arn" = var.cert_manager_iam_role_arn
  } : var.provider_type == "gcp-gke" && var.cert_manager_gcp_sa_email != "" ? {
    "iam.gke.io/gcp-service-account" = var.cert_manager_gcp_sa_email
  } : {}

  # external-dns service account annotations by provider
  external_dns_sa_annotations = var.provider_type == "aws-eks" && var.external_dns_iam_role_arn != "" ? {
    "eks.amazonaws.com/role-arn" = var.external_dns_iam_role_arn
  } : var.provider_type == "gcp-gke" && var.external_dns_gcp_sa_email != "" ? {
    "iam.gke.io/gcp-service-account" = var.external_dns_gcp_sa_email
  } : {}

  # external-dns provider configuration
  external_dns_provider = var.provider_type == "aws-eks" ? "aws" : var.provider_type == "gcp-gke" ? "google" : "cloudflare"
}

################################################################################
# Namespaces
################################################################################

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
    labels = {
      name        = "platform"
      environment = var.environment
    }
  }
}

resource "kubernetes_namespace" "apps" {
  metadata {
    name = "apps"
    labels = {
      name        = "apps"
      environment = var.environment
    }
  }
}

################################################################################
# Ingress Controller (nginx-ingress)
################################################################################

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.nginx_ingress_version
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/nginx-ingress.yaml", {
      provider_type = var.provider_type
      replica_count = var.ingress_replica_count
    })
  ]

  set {
    name  = "controller.service.type"
    value = var.provider_type == "vps-k3s" ? "NodePort" : "LoadBalancer"
  }

  # For VPS, use hostPort
  dynamic "set" {
    for_each = var.provider_type == "vps-k3s" ? [1] : []
    content {
      name  = "controller.hostPort.enabled"
      value = "true"
    }
  }

  # For VPS, use host network
  dynamic "set" {
    for_each = var.provider_type == "vps-k3s" ? [1] : []
    content {
      name  = "controller.hostNetwork"
      value = "true"
    }
  }
}

################################################################################
# cert-manager
################################################################################

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.platform.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.provider_type == "aws-eks" && var.cert_manager_iam_role_arn != "" ? var.cert_manager_iam_role_arn : ""
  }

  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = var.provider_type == "gcp-gke" && var.cert_manager_gcp_sa_email != "" ? var.cert_manager_gcp_sa_email : ""
  }

  values = [
    templatefile("${path.module}/helm-values/cert-manager.yaml", {
      provider_type = var.provider_type
    })
  ]
}

################################################################################
# ClusterIssuers (Let's Encrypt)
################################################################################

# Staging issuer
resource "kubernetes_manifest" "letsencrypt_staging" {
  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-staging-key"
        }
        solvers = var.cert_manager_use_dns01 ? [
          {
            dns01 = var.provider_type == "aws-eks" ? {
              route53 = {
                region = var.aws_region
              }
            } : var.provider_type == "gcp-gke" ? {
              cloudDNS = {
                project = var.gcp_project_id
              }
            } : {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token"
                  key  = "api-token"
                }
              }
            }
          }
        ] : [
          {
            http01 = {
              ingress = {
                class = local.ingress_class
              }
            }
          }
        ]
      }
    }
  }
}

# Production issuer
resource "kubernetes_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = var.cert_manager_use_dns01 ? [
          {
            dns01 = var.provider_type == "aws-eks" ? {
              route53 = {
                region = var.aws_region
              }
            } : var.provider_type == "gcp-gke" ? {
              cloudDNS = {
                project = var.gcp_project_id
              }
            } : {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token"
                  key  = "api-token"
                }
              }
            }
          }
        ] : [
          {
            http01 = {
              ingress = {
                class = local.ingress_class
              }
            }
          }
        ]
      }
    }
  }
}

################################################################################
# metrics-server
################################################################################

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/metrics-server.yaml", {
      provider_type = var.provider_type
    })
  ]
}

################################################################################
# external-dns (optional)
################################################################################

resource "helm_release" "external_dns" {
  count = var.enable_external_dns ? 1 : 0

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.external_dns_version
  namespace  = kubernetes_namespace.platform.metadata[0].name

  set {
    name  = "provider"
    value = local.external_dns_provider
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.provider_type == "aws-eks" && var.external_dns_iam_role_arn != "" ? var.external_dns_iam_role_arn : ""
  }

  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = var.provider_type == "gcp-gke" && var.external_dns_gcp_sa_email != "" ? var.external_dns_gcp_sa_email : ""
  }

  dynamic "set" {
    for_each = var.external_dns_domain_filters
    content {
      name  = "domainFilters[${set.key}]"
      value = set.value
    }
  }

  values = [
    templatefile("${path.module}/helm-values/external-dns.yaml", {
      provider_type = var.provider_type
      provider      = local.external_dns_provider
    })
  ]
}

################################################################################
# kube-prometheus-stack (optional)
################################################################################

resource "helm_release" "kube_prometheus" {
  count = var.enable_kube_prometheus ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_version
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/kube-prometheus.yaml", {
      environment              = var.environment
      ingress_enabled          = var.prometheus_ingress_enabled
      prometheus_ingress_host  = var.prometheus_ingress_host
      grafana_ingress_host     = var.grafana_ingress_host
    })
  ]

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = var.prometheus_retention
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = var.prometheus_storage_size
  }
}

