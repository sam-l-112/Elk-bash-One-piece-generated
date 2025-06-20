#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# 📦 Unified k3s + ELK Installer
# ----------------------------

echo "===== 🚀 Phase 1: Install k3s ====="
curl -sfL https://get.k3s.io | sh -
echo "Waiting for k3s to initialize..."
sleep 5
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "✅ k3s installed. Nodes and pods status:"
kubectl get nodes
kubectl get pods -A

echo -e "\n===== 🌐 Phase 2: Deploy ELK Stack via ECK ====="
echo "Adding Helm repo for Elastic..."
helm repo add elastic https://helm.elastic.co
helm repo update

echo "Installing ECK Operator in 'elastic-system' namespace..."
helm install elastic-operator elastic/eck-operator \
  -n elastic-system --create-namespace

echo "Deploying ELK Stack using 'eck-stack' chart to 'elastic-stack' namespace..."
helm install eck-stack elastic/eck-stack \
  -n elastic-stack --create-namespace \
  -f elk/values.yml

echo -e "\n✅ ELK Stack deployed successfully!"
kubectl get all -n elastic-stack
