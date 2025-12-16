#!/usr/bin/env bash
set -euo pipefail

# install_elk.sh — ELK (Elasticsearch, Logstash, Kibana) installer for Ubuntu 20.04/22.04
#
# Key behaviors:
# - Fixes/avoids malformed Elastic repo list entries (writes single-line repo entry)
# - Removes the known-bad /etc/apt/sources.list.d/elastic-8.x.list if present
# - Forces Elasticsearch to use standard Debian/Ubuntu paths via systemd override:
#     ES_PATH_CONF=/etc/elasticsearch
#     ES_PATH_DATA=/var/lib/elasticsearch
#     ES_PATH_LOGS=/var/log/elasticsearch
#   (Prevents ES from trying to write logs under /usr/share/elasticsearch/logs)
# - Creates required dirs with correct ownership
# - Provides an optional "reset auto-config" step if prior failed starts left partial state

ELASTIC_MAJOR="8.x"

KEYRING_PATH="/usr/share/keyrings/elastic-keyring.gpg"
REPO_LIST="/etc/apt/sources.list.d/elastic.list"
BAD_LIST="/etc/apt/sources.list.d/elastic-8.x.list"

ES_OVERRIDE_DIR="/etc/systemd/system/elasticsearch.service.d"
ES_OVERRIDE_FILE="${ES_OVERRIDE_DIR}/override.conf"

RESET_ES_AUTOCONFIG="${RESET_ES_AUTOCONFIG:-0}"  # set to 1 to wipe keystore/certs if stuck

log() { echo -e "\n==> $*"; }
die() { echo "❌ $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
  die "Please run as root: sudo $0"
fi

log "Removing known-bad Elastic repo list file if present..."
rm -f "${BAD_LIST}"

log "Installing prerequisites..."
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  apt-transport-https

log "Ensuring keyrings directory exists..."
install -d -m 0755 /usr/share/keyrings

log "Adding Elastic GPG key..."
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | gpg --dearmor \
  | tee "${KEYRING_PATH}" >/dev/null
chmod 0644 "${KEYRING_PATH}"

log "Writing Elastic APT repository (single line, APT-safe)..."
printf "deb [signed-by=%s] %s stable main\n" \
  "${KEYRING_PATH}" \
  "https://artifacts.elastic.co/packages/${ELASTIC_MAJOR}/apt" \
  | tee "${REPO_LIST}" >/dev/null

log "Updating package index..."
apt-get update -y

log "Installing Elasticsearch, Logstash, Kibana..."
apt-get install -y elasticsearch logstash kibana

log "Ensuring Elasticsearch standard directories exist with correct ownership..."
install -d -o elasticsearch -g elasticsearch -m 0750 /var/lib/elasticsearch
install -d -o elasticsearch -g elasticsearch -m 0750 /var/log/elasticsearch
install -d -o elasticsearch -g elasticsearch -m 0750 /etc/elasticsearch

log "Forcing Elasticsearch paths via systemd override (prevents /usr/share/.../logs usage)..."
install -d -m 0755 "${ES_OVERRIDE_DIR}"
cat >"${ES_OVERRIDE_FILE}" <<'EOF'
[Service]
Environment=ES_PATH_CONF=/etc/elasticsearch
Environment=ES_PATH_DATA=/var/lib/elasticsearch
Environment=ES_PATH_LOGS=/var/log/elasticsearch
EOF
chmod 0644 "${ES_OVERRIDE_FILE}"

log "Configuring Elasticsearch (minimal, local-only bind by default)..."
# We keep this minimal and safe-by-default. You can change network.host if you explicitly want remote access.
cat >/etc/elasticsearch/elasticsearch.yml <<'EOF'
cluster.name: elk-cluster
node.name: node-1
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node

# Standard Debian/Ubuntu paths (also enforced by systemd override)
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
EOF
chmod 0644 /etc/elasticsearch/elasticsearch.yml

if [[ "${RESET_ES_AUTOCONFIG}" == "1" ]]; then
  log "RESET_ES_AUTOCONFIG=1 set — wiping partial auto-config state (keystore/certs)..."
  systemctl stop elasticsearch || true
  rm -f /etc/elasticsearch/elasticsearch.keystore || true
  rm -rf /etc/elasticsearch/certs || true
fi

log "Configuring Kibana..."
cat >/etc/kibana/kibana.yml <<'EOF'
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
EOF
chmod 0644 /etc/kibana/kibana.yml

log "Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable elasticsearch logstash kibana

log "Starting Elasticsearch..."
if ! systemctl start elasticsearch; then
  echo ""
  echo "Elasticsearch failed to start. Last 200 log lines:"
  journalctl -u elasticsearch --no-pager -n 200 || true
  echo ""
  echo "Effective unit (including overrides):"
  systemctl cat elasticsearch || true
  echo ""
  die "Elasticsearch did not start."
fi

log "Starting Logstash and Kibana..."
systemctl start logstash
systemctl start kibana

log "Health checks..."
echo -n "Elasticsearch HTTP status: "
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9200 || true

echo -n "Kibana port 5601: "
ss -ltn | awk '$4 ~ /:5601$/ {print "LISTEN"; found=1} END{if(!found) print "NOT LISTENING"}'

log "Done."
echo "Elasticsearch: http://127.0.0.1:9200 (local only)"
echo "Kibana:        http://<server-ip>:5601"
echo ""
echo "If Elasticsearch still fails due to partial auto-config, rerun with:"
echo "  sudo RESET_ES_AUTOCONFIG=1 $0"
echo ""
echo "⚠️ NOTE: Elastic 8.x security (TLS/auth) is not intentionally configured by this script."
