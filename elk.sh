#!/bin/bash
set -e

# 1. Clone repo & 安裝 Ansible
if [ ! -d "AQUA-CARE-2025-June" ]; then
  git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June
fi
cd AQUA-CARE-2025-June
bash tools/install_ansbile.sh

# 2. 建立 Python virtualenv 並啟動
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible requests joblib tqdm

# 3. 用 Ansible 安裝 K3s
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml
source ~/.bashrc
kubectl get po -A

# 4. 安裝 ELK Stack via Helm
cd elk
helm repo add elastic https://helm.elastic.co
helm repo update

helm upgrade --install elasticsearch elastic/elasticsearch -f elasticsearch/values.yml
helm upgrade --install filebeat elastic/filebeat -f filebeat/values.yml
helm upgrade --install logstash elastic/logstash -f logstash/values.yml
helm upgrade --install kibana elastic/kibana -f kibana/values.yml

# 5. 等待 Elasticsearch 起來
echo "等待 Elasticsearch 啟動中..."
kubectl rollout status sts/elasticsearch-master -n default --timeout=300s

# 6. 取得 Elastic 密碼
ES_PASS=$(kubectl get secret elasticsearch-master-credentials -o jsonpath="{.data.password}" | base64 --decode)
echo "Elasticsearch password is: ${ES_PASS}"

# 7. 調整 Filebeat 本地設定
FILEBEAT_CFG="/etc/filebeat/filebeat.yml"
if [ -w "$FILEBEAT_CFG" ]; then
  sudo sed -i "s|#25.*|host: \"https://elasticsearch-master.default.svc:9200\"|g" $FILEBEAT_CFG
  sudo sed -i "s|#28.*|protocol: \"https\"|g" $FILEBEAT_CFG
  sudo sed -i "s|#175.*|username: \"elastic\"|g" $FILEBEAT_CFG
  sudo sed -i "s|#176.*|password: \"${ES_PASS}\"|g" $FILEBEAT_CFG
  echo "Filebeat config updated in $FILEBEAT_CFG"
else
  echo "請自行以 root 編輯 $FILEBEAT_CFG，然後再執行測試及重啟 Filebeat"
fi

# 8. 測試 Filebeat 並重啟
echo "Testing Filebeat config..."
sudo filebeat test config
echo "Testing Filebeat output..."
sudo filebeat test output
sudo systemctl restart filebeat
echo "Filebeat 已重啟"

# 9. 測試 Elasticsearch via go.sh
cd elasticsearch
bash go.sh

# 10. 建立 API Key
bash create_api_key.sh

# 11. 匯入 dataset
cd ../dataset
python import_dataset.py

echo "🎉 ELK on K3s + Data import 完成！"
