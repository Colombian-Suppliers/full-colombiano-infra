#!/bin/bash
set -e

echo "=== Installing k3s ==="

# Update system
apt-get update
apt-get install -y curl

# Check if k3s is already installed
if command -v k3s &> /dev/null; then
    echo "k3s is already installed. Checking version..."
    k3s --version
    
    # Optionally upgrade/reinstall
    # systemctl stop k3s
    # /usr/local/bin/k3s-uninstall.sh
fi

# Install k3s
export INSTALL_K3S_VERSION="${k3s_version}"
curl -sfL https://get.k3s.io | sh -s - server ${install_flags}

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
sleep 10

# Verify installation
k3s kubectl get nodes
k3s kubectl get pods -A

echo "=== k3s installation complete ==="

