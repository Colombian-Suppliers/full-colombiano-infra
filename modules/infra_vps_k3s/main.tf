terraform {
  required_version = ">= 1.6.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

locals {
  k3s_install_flags = join(" ", [
    "--write-kubeconfig-mode 644",
    "--disable traefik", # We'll install our own ingress controller for consistency
    "--disable servicelb",
    "--disable local-storage",
    "--node-name ${var.node_name}",
    var.k3s_version != "" ? "--k3s-version ${var.k3s_version}" : "",
    var.enable_tls_san ? "--tls-san ${var.vps_host}" : "",
    var.additional_k3s_flags != "" ? var.additional_k3s_flags : ""
  ])

  kubeconfig_path = "${path.root}/../../.kube/${var.environment}-k3s.yaml"
}

# Test SSH connectivity
resource "null_resource" "ssh_test" {
  count = var.provision_k3s ? 1 : 0

  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = ["echo 'SSH connection successful'"]
  }
}

# Install k3s
resource "null_resource" "install_k3s" {
  count      = var.provision_k3s ? 1 : 0
  depends_on = [null_resource.ssh_test]

  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  # Upload k3s install script
  provisioner "file" {
    content = templatefile("${path.module}/templates/install-k3s.sh", {
      k3s_version = var.k3s_version
      install_flags = local.k3s_install_flags
    })
    destination = "/tmp/install-k3s.sh"
  }

  # Execute installation
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/install-k3s.sh",
      "sudo /tmp/install-k3s.sh",
      "sudo systemctl enable k3s",
      "sudo systemctl start k3s",
      "sleep 30", # Wait for k3s to be ready
      "sudo k3s kubectl get nodes"
    ]
  }

  triggers = {
    k3s_version = var.k3s_version
    vps_host    = var.vps_host
  }
}

# Configure firewall (ufw)
resource "null_resource" "configure_firewall" {
  count      = var.provision_k3s && var.configure_firewall ? 1 : 0
  depends_on = [null_resource.install_k3s]

  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ufw",
      "sudo ufw --force enable",
      "sudo ufw default deny incoming",
      "sudo ufw default allow outgoing",
      "sudo ufw allow 22/tcp comment 'SSH'",
      "sudo ufw allow 80/tcp comment 'HTTP'",
      "sudo ufw allow 443/tcp comment 'HTTPS'",
      "sudo ufw allow 6443/tcp comment 'Kubernetes API'",
      "sudo ufw status"
    ]
  }
}

# Fetch kubeconfig
resource "null_resource" "fetch_kubeconfig" {
  count      = var.provision_k3s ? 1 : 0
  depends_on = [null_resource.install_k3s]

  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p $(dirname ${local.kubeconfig_path})
      ssh -i ${var.ssh_private_key_path} \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          ${var.vps_user}@${var.vps_host} \
          'sudo cat /etc/rancher/k3s/k3s.yaml' | \
          sed 's/127.0.0.1/${var.vps_host}/g' > ${local.kubeconfig_path}
      chmod 600 ${local.kubeconfig_path}
    EOT
  }

  triggers = {
    vps_host = var.vps_host
  }
}

# Wait for cluster to be ready
resource "null_resource" "wait_for_cluster" {
  count      = var.provision_k3s ? 1 : 0
  depends_on = [null_resource.fetch_kubeconfig]

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

# Create kubeconfig as local file for reference
resource "local_file" "kubeconfig" {
  count      = var.provision_k3s ? 1 : 0
  depends_on = [null_resource.fetch_kubeconfig]

  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name    = "${var.environment}-k3s-cluster"
    server_endpoint = "https://${var.vps_host}:6443"
    context_name    = "${var.environment}-k3s"
  })
  filename        = local.kubeconfig_path
  file_permission = "0600"

  lifecycle {
    ignore_changes = [content] # Let the fetch_kubeconfig update it
  }
}

# Output cluster info
data "external" "cluster_info" {
  count      = var.provision_k3s ? 1 : 0
  depends_on = [null_resource.wait_for_cluster]

  program = ["bash", "-c", <<-EOT
    export KUBECONFIG=${local.kubeconfig_path}
    
    version=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "unknown")
    nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    cat <<EOF
{
  "version": "$version",
  "nodes": "$nodes",
  "endpoint": "https://${var.vps_host}:6443"
}
EOF
  EOT
  ]
}

