#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Step 1: Clone AQUA-CARE Project"
git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June
cd AQUA-CARE-2025-June

echo "🧰 Step 2: Setup Ansible Environment"
bash tools/install_ansbile.sh
source .venv/bin/activate
pip install --upgrade ansible requests joblib tqdm

echo "🚀 Step 3: Install k3s using Ansible"
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml

echo "📂 Step 4: Configure kubeconfig"
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc

echo "✅ k3s installation completed. Verifying..."
kubectl get po -A

echo "📦 Step 5: Install ELK Stack using Helm"
cd elk/

helm repo add elastic https://helm.elastic.co || true
helm repo update

declare -A CHARTS=(
  [elasticsearch]="elasticsearch/values.yml"
  [filebeat]="filebeat/values.yml"
  [logstash]="logstash/values.yml"
  [kibana]="kibana/values.yml"
)

for CHART in "${!CHARTS[@]}"; do
  if helm list -A | grep -q "^$CHART"; then
    echo "✅ $CHART 已安裝，跳過"
  else
    echo "⬆️ Installing $CHART..."
    helm install "$CHART" "elastic/$CHART" -f "${CHARTS[$CHART]}"
    echo "⏳ 等待 $CHART 部署..."
    sleep 15
  fi
done

echo "✅ ELK stack 安裝完成，請稍候幾分鐘等待服務啟動。"
kubectl get all -n default
