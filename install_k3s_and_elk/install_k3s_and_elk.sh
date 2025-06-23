#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Step 1: Clone AQUA-CARE Project"
git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June
cd AQUA-CARE-2025-June

echo "🧰 Step 2: Install Ansible & Python Dependencies"
bash tools/install_ansbile.sh
source .venv/bin/activate
pip install --upgrade ansible requests joblib tqdm

echo "📦 Step 3: Install k3s"
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml
source ~/.bashrc
kubectl get po -A

echo "📦 Step 4: Install ELK Stack via Helm"
cd elk/

helm repo add elastic https://helm.elastic.co || true
helm repo update

declare -A CHARTS=(
  [elasticsearch]="elasticsearch/values.yml"
  [filebeat]="filebeat/values.yml"
  [logstash]="logstash/values.yml"
  [kibana]="kibana/values.yml"
)

for chart in "${!CHARTS[@]}"; do
  if helm list -A | grep -q "^$chart"; then
    echo "✅ $chart 已安裝，跳過"
  else
    echo "⬆️ 安裝 $chart"
    helm install "$chart" "elastic/$chart" -f "${CHARTS[$chart]}"
    sleep 10
  fi
done

echo "✅ k3s + ELK 安裝完成"
kubectl get all -A
