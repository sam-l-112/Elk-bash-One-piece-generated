#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Phase 1: Clone and setup Ansible/k3s"
if [ ! -d "AQUA-CARE-2025-June" ]; then
  git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June
fi
cd AQUA-CARE-2025-June

bash tools/install_ansbile.sh
source .venv/bin/activate
pip install --upgrade ansible requests joblib tqdm

echo "🚀 Phase 2: Deploy k3s with Ansible"
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml

echo "🛠 Setup kubeconfig"
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
source ~/.bashrc

kubectl get po -A

echo "🚀 Phase 3: Deploy ELK Stack with Helm"
cd elk/
helm repo add elastic https://helm.elastic.co || true
helm repo update

for chart in elasticsearch filebeat logstash kibana; do
  if helm list | grep -q "^$chart"; then
    echo "⚠️ $chart 已存在，跳過安裝"
  else
    echo "⬆️ 安裝 $chart"
    helm install $chart elastic/$chart -f $chart/values.yml
  fi
done

kubectl get all -n default

echo "🌍 本機名稱與 IP"
HOST_IP=$(hostname -I | awk '{print $1}')
HOST_NAME=$(hostname)
echo "📟 主機名稱: $HOST_NAME"
echo "🌐 本機 IP: $HOST_IP"

echo "🔑 取得 elastic 使用者密碼"
ELASTIC_PASS=$(kubectl get secret elasticsearch-master-credentials -o jsonpath="{.data.password}" | base64 --decode)
echo "elastic 帳號密碼: $ELASTIC_PASS"

echo "📦 安裝 Filebeat"
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-9.x.list > /dev/null
sudo apt-get update
sudo apt-get install -y filebeat
sudo systemctl enable filebeat

echo "🔄 匯入測試資料"
cd elasticsearch
bash go.sh || echo "⚠️ go.sh 執行失敗，請手動檢查"

echo "🔑 建立 API Key"
bash create_api_key.sh > api_key_output.json
ENCODED_KEY=$(grep -oP '"encoded"\s*:\s*"\K[^"]+' api_key_output.json | tail -n 1)
if [[ -z "$ENCODED_KEY" ]]; then
  echo "❌ 無法自動取得 API Key，請手動執行 create_api_key.sh"
  exit 1
fi
echo "🔐 取得 API Key: $ENCODED_KEY"

echo "🔧 設定 Filebeat 使用 API Key 連接 Elasticsearch"
sudo tee /etc/filebeat/filebeat.yml > /dev/null <<EOF
output.elasticsearch:
  hosts: ["https://localhost:9200"]
  api_key: "$ENCODED_KEY"
  ssl.verification_mode: "none"
EOF

sudo filebeat test config
sudo filebeat test output
sudo systemctl restart filebeat

echo "⚙️ 測試 API Key"
bash test_api_key.sh || echo "⚠️ test_api_key.sh 執行失敗"

echo "🐍 啟用 Python 虛擬環境並執行資料匯入"
cd ../../
source .venv/bin/activate

echo "Python 路徑：$(which python)"

read -rp "請輸入 import_dataset.py 參數（無參數直接 Enter）: " PY_ARGS

python3 import_dataset.py $PY_ARGS

echo "✅ 全部完成！Kibana 網址: http://localhost:5601"
