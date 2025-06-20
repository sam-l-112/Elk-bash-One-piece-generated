#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# 📦 One‑Stop Installer: k3s + ELK + Filebeat + Data Pipeline
# --------------------------------------------

# === Phase 1: k3s + ELK Base Deployment ===
echo "🔧 Clone and setup Ansible/k3s"
git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June || true
cd AQUA-CARE-2025-June

bash tools/install_ansbile.sh
source .venv/bin/activate
pip install ansible requests joblib tqdm
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml

# Configure kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc
kubectl get po -A

# === Phase 2: Install ELK ===
echo "📦 Deploy ELK via Helm"
cd elk/
helm repo add elastic https://helm.elastic.co || true
helm repo update

# Conditional install if not already present
for chart in elasticsearch filebeat logstash kibana; do
  if helm list | grep -q "$chart"; then
    echo "⚠️ $chart is already installed. Skipping."
  else
    echo "⬆️ Installing $chart ..."
    helm install $chart elastic/$chart -f $chart/values.yml
  fi
done

kubectl get all -n default

# === Phase 3: SSH Tunnel & Password ===
HOST_IP=$(hostname -I | awk '{print $1}')
HOST_NAME=$(hostname)
echo "📡 本機名稱: $HOST_NAME"
echo "🌐 本機 IP: $HOST_IP"

ELASTIC_PASS=$(kubectl get secret elasticsearch-master-credentials \
  -o jsonpath="{.data.password}" | base64 --decode)
echo "→ elastic 帳號密碼: $ELASTIC_PASS"

read -rp "🔑 請輸入 SSH 金鑰路徑 (預設: ~/.ssh/id_rsa): " SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
read -rp "🌍 請輸入遠端 VCS IP 位置: " REMOTE_IP

echo "🔗 SSH tunnel 指令:"
echo "ssh -L 0.0.0.0:5601:localhost:5601 -i $SSH_KEY ubuntu@$REMOTE_IP"

# === Phase 4: Filebeat Install & Config ===
echo "📥 Install Filebeat on host"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install -y apt-transport-https
echo "deb https://artifacts.elastic.co/packages/9.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-9.x.list
sudo apt-get update
sudo apt-get install -y filebeat
sudo systemctl enable filebeat

read -rp "✍️ 是否要自動修改 Filebeat 設定檔？(y/N): " MODIFY_FB
if [[ $MODIFY_FB == "y" || $MODIFY_FB == "Y" ]]; then
  sudo sed -i "s/^.*username:.*/  username: \"elastic\"/" /etc/filebeat/filebeat.yml
  sudo sed -i "s/^.*password:.*/  password: \"$ELASTIC_PASS\"/" /etc/filebeat/filebeat.yml
  sudo sed -i "s/^.*verification_mode:.*/    verification_mode: \"none\"/" /etc/filebeat/filebeat.yml
  echo "✅ Filebeat 配置已更新"
else
  echo "⚠️ 請手動修改 /etc/filebeat/filebeat.yml"
fi

sudo filebeat test config
sudo filebeat test output
sudo systemctl restart filebeat

# === Phase 5: Import Data Pipeline ===
echo "🔄 Import sample data"
cd elasticsearch
bash go.sh
bash create_api_key.sh
bash test_api_key.sh

read -rp "📅 是否啟用 dataset 匯入？(y/N): " IMPORT_DATA
if [[ $IMPORT_DATA == "y" || $IMPORT_DATA == "Y" ]]; then
  source ../../.venv/bin/activate
  python3 import_dataset.py
  echo "✅ Dataset 匯入完成"
else
  echo "⏭️ 已略過 dataset 匯入"
fi

echo "✨ All setup complete! You can now use Kibana at: http://localhost:5601"
