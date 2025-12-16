#!/usr/bin/env bash
set -euo pipefail

# install_filebeat.sh — Filebeat installer for Ubuntu 20.04/22.04 (EC2 client)
#
# What it does:
# - Adds Elastic APT repo (APT-safe single-line entry)
# - Installs Filebeat
# - Configures Filebeat to ship logs to your ELK server:
#     Option A (default): send directly to Elasticsearch on the ELK box
#     Option B: send to Logstash on the ELK box (recommended for pipelines)
# - Enables + starts the filebeat service
#
# Usage:
#   sudo ELK_HOST="10.0.1.81" ./install_filebeat.sh
#   sudo ELK_HOST="elk.internal" OUTPUT_MODE="logstash" ./install_filebeat.sh
#
# Env vars:
#   ELK_HOST      (required) ELK server IP/DNS reachable from client
#   OUTPUT_MODE   "logstash" or "elasticsearch" (default: logstash)
#   LOGSTASH_PORT default 5044
#   ES_PORT       default 9200
#
# Notes:
# - This is a "no-auth/no-TLS" setup that matches a lab ELK install.
# - If your Elastic stack has security enabled, tell me and I’ll generate the secure version.

ELASTIC_MAJOR="8.x"
ELK_HOST="${ELK_HOST:-}"
OUTPUT_MODE="${OUTPUT_MODE:-logstash}" # logstash|elasticsearch
LOGSTASH_PORT="${LOGSTASH_PORT:-5044}"
ES_PORT="${ES_PORT:-9200}"

KEYRING_PATH="/usr/share/keyrings/elastic-keyring.gpg"
REPO_LIST="/etc/apt/sources.list.d/elastic.list"
BAD_LIST="/etc/apt/sources.list.d/elastic-8.x.list"

log() { echo -e "\n==> $*"; }
die() { echo "❌ $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
  die "Please run as root: sudo $0"
fi

if [[ -z "${ELK_HOST}" ]]; then
  die 'ELK_HOST is required. Example: sudo ELK_HOST="10.0.1.81" ./install_filebeat.sh'
fi

if [[ "${OUTPUT_MODE}" != "logstash" && "${OUTPUT_MODE}" != "elasticsearch" ]]; then
  die 'OUTPUT_MODE must be "logstash" or "elasticsearch"'
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

log "Installing Filebeat..."
apt-get install -y filebeat

log "Configuring Filebeat..."
# Backup the original config once
if [[ ! -f /etc/filebeat/filebeat.yml.bak ]]; then
  cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak
fi

# Minimal config:
# - collect system logs from journald/syslog paths via the system module
# - ship to logstash (default) or elasticsearch
cat >/etc/filebeat/filebeat.yml <<EOF
# Managed by install_filebeat.sh

filebeat.inputs: []

filebeat.config.modules:
  path: \${path.config}/modules.d/*.yml
  reload.enabled: false

# Enable the system module (auth/syslog)
filebeat.modules:
  - module: system
    syslog:
      enabled: true
    auth:
      enabled: true

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
  - add_docker_metadata: ~
  - add_kubernetes_metadata: ~

setup.ilm.enabled: false
setup.template.enabled: false

EOF

if [[ "${OUTPUT_MODE}" == "logstash" ]]; then
  cat >>/etc/filebeat/filebeat.yml <<EOF
output.logstash:
  hosts: ["${ELK_HOST}:${LOGSTASH_PORT}"]
EOF
else
  cat >>/etc/filebeat/filebeat.yml <<EOF
output.elasticsearch:
  hosts: ["http://${ELK_HOST}:${ES_PORT}"]
EOF
fi

chmod 0644 /etc/filebeat/filebeat.yml

log "Enabling system module config (modules.d/system.yml)..."
filebeat modules enable system >/dev/null 2>&1 || true

log "Restarting and enabling Filebeat..."
systemctl daemon-reload
systemctl enable --now filebeat

log "Showing Filebeat status..."
systemctl status filebeat --no-pager -l || true

log "Quick connectivity hint..."
if [[ "${OUTPUT_MODE}" == "logstash" ]]; then
  echo "Filebeat is configured to send to Logstash at ${ELK_HOST}:${LOGSTASH_PORT}."
  echo "On the ELK server, ensure Logstash is listening on 0.0.0.0:${LOGSTASH_PORT} and port is open in SG."
else
  echo "Filebeat is configured to send to Elasticsearch at http://${ELK_HOST}:${ES_PORT}."
  echo "On the ELK server, Elasticsearch must be reachable remotely (network.host not 127.0.0.1) and port open in SG."
fi

log "Done."
echo ""
echo "To view shipped logs later:"
echo "  sudo journalctl -u filebeat --no-pager -n 200"
