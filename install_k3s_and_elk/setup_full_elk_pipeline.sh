#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------
# 📦 One‑Stop Installer: k3s + ELK + Filebeat + Data Pipeline (with API Key from create_api_key.sh)
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

for chart in elasticsearch filebeat logstash kibana; do
  if helm list | grep -q "$chart"; then
    echo "⚠️ $chart is already installed. Skipping."
  else
    echo "⬆️ Installing $chart ..."
    helm install $chart elastic/$chart -f $chart/values.yml
  fi
done

kubectl get all -n default

# === Phase 3: Password ===
HOST_IP=$(hostname -I | awk '{print $1}')
HOST_NAME=$(hostname)
echo "📡 本機名稱: $HOST_NAME"
echo "🌐 本機 IP: $HOST_IP"

ELASTIC_PASS=$(kubectl get secret elasticsearch-master-credentials \
  -o jsonpath="{.data.password}" | base64 --decode)
echo "→ elastic 帳號密碼: $ELASTIC_PASS"

# === Phase 4: Filebeat Install & Config ===
echo "📥 Install Filebeat on host"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-9.x.list > /dev/null

sudo apt-get update
sudo apt-get install -y filebeat
sudo systemctl enable filebeat

# === Phase 5: Import Data Pipeline and Auto Extract API Key ===
echo "🔄 Import sample data"
cd elasticsearch

bash go.sh || echo "⚠️ go.sh 執行失敗"
bash create_api_key.sh > api_key_output.json

ENCODED_KEY=$(grep -oP '"encoded"\s*:\s*"\K[^"]+' api_key_output.json | tail -n 1)
if [[ -z "$ENCODED_KEY" ]]; then
  echo "❌ 無法自動操作 API Key, 請手動執行 create_api_key.sh"
  exit 1
fi

echo "🔐 Extracted API Key: $ENCODED_KEY"

sudo tee /etc/filebeat/filebeat.yml > /dev/null <<EOF
output.elasticsearch:
  hosts: ["https://localhost:9200"]
  api_key: "$ENCODED_KEY"
  ssl.verification_mode: "none"
EOF

sudo filebeat test config
sudo filebeat test output
sudo systemctl restart filebeat

bash test_api_key.sh || echo "⚠️ test_api_key.sh 失敗"

read -rp "📅 是否啟用 dataset 匯入？(y/N): " IMPORT_DATA
if [[ $IMPORT_DATA == "y" || $IMPORT_DATA == "Y" ]]; then
  source ../../.venv/bin/activate
  python3 import_dataset.py
  echo "✅ Dataset 匯入完成"
else
  echo "⏭️ 已略過 dataset 匯入"
fi

echo "✨ All setup complete! You can now use Kibana at: http://localhost:5601"
