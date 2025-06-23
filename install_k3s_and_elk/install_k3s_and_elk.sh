#!/usr/bin/env bash
set -euo pipefail

# === Step 1: Clone AQUA-CARE Project ===
echo "🔧 Step 1: Clone AQUA-CARE Project"
git clone https://github.com/DevSecOpsLab-CSIE-NPU/AQUA-CARE-2025-June
cd AQUA-CARE-2025-June

# === Step 2: Setup Ansible Environment ===
echo "🧰 Step 2: Setup Ansible Environment"
bash tools/install_ansbile.sh
source .venv/bin/activate
pip install --upgrade ansible requests joblib tqdm

# === Step 3: Install k3s ===
echo "🚀 Step 3: Install k3s using Ansible"
ansible-playbook -i ansible/inventories/hosts.ini ansible/playbooks/install_k3s.yaml

# === Step 4: Setup kubeconfig ===
echo "📂 Step 4: Configure kubeconfig"
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=$HOME/.kube/config
if ! grep -q "KUBECONFIG" ~/.bashrc; then
  echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
fi
source ~/.bashrc

echo "✅ k3s installation completed. Verifying..."
kubectl get po -A

# === Step 5: Fix Elastic APT Key Conflict ===
echo "🧹 Step 5: Clean Elastic APT Sources and Import GPG Key"
sudo rm -f /etc/apt/sources.list.d/elastic*.list
sudo apt-key del D27D666CD88E42B4 2>/dev/null || true
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
https://artifacts.elastic.co/packages/9.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-9.x.list > /dev/null

sudo apt-get update

# === Step 6: Install ELK Stack ===
echo "📦 Step 6: Install ELK Stack using Helm"
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
    echo "✅ $CHART already installed. Skipping."
  else
    echo "⬆️ Installing $CHART..."
    helm install "$CHART" "elastic/$CHART" -f "${CHARTS[$CHART]}"
    echo "⏳ Waiting for $CHART to deploy..."
    sleep 15
  fi
  sleep 5
  kubectl get pods | grep "$CHART" || true
done

kubectl get all -n default

echo "🎉 K3s and ELK stack installation complete."
echo "📌 You can now access Kibana after confirming the pods are ready."
echo "   e.g. ssh -L 5601:localhost:5601 ubuntu@<your_server_ip>"
