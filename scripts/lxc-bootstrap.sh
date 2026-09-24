#!/usr/bin/env bash
set -Eeuo pipefail

OWNER="ItechLabFr"
REPO="CubyNode"
REPO_HTTPS="https://github.com/$OWNER/$REPO.git"
CHANNEL="${CUBYNODE_UPDATE_CHANNEL:-main}"
INSTALL_DIR="/opt/cubynode"
ENV_DIR="/etc/cubynode"
ENV_FILE="$ENV_DIR/cubynode.env"
STATE_DIR="/var/lib/cubynode"
LOG_DIR="/var/log/cubynode"

[[ "${EUID}" -eq 0 ]] || { echo "This bootstrap must run as root inside the LXC." >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

dns_ready=false
for _ in {1..12}; do
  if getent ahostsv4 deb.debian.org >/dev/null 2>&1 &&
     getent ahostsv4 security.debian.org >/dev/null 2>&1 &&
     getent ahostsv4 deb.nodesource.com >/dev/null 2>&1 &&
     getent ahostsv4 github.com >/dev/null 2>&1; then
    dns_ready=true
    break
  fi
  echo "Waiting for Debian/NodeSource/GitHub DNS resolution..." >&2
  sleep 5
done
if ! $dns_ready; then
  echo "DNS resolution inside this LXC is unavailable. Check /etc/resolv.conf, DHCP, VLAN and the Proxmox bridge; do not recreate the container." >&2
  exit 1
fi

apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 install -y   ca-certificates   curl   git   sudo   postgresql   postgresql-contrib   openssl   python3   util-linux   xz-utils

if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)" -lt 24 ]]; then
  curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors https://deb.nodesource.com/setup_24.x | bash -
  apt-get -o Acquire::Retries=5 install -y nodejs
fi

systemctl enable --now postgresql

if ! id cubynode >/dev/null 2>&1; then
  useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin cubynode
fi
install -d -o root -g cubynode -m 0750 "$ENV_DIR" "$STATE_DIR" "$LOG_DIR"
install -d -o cubynode -g cubynode -m 0750 "$STATE_DIR/npm-cache"

run_cubynode_repo() {
  runuser -u cubynode -- env \
    HOME="$INSTALL_DIR" \
    npm_config_cache="$STATE_DIR/npm-cache" \
    sh -c 'cd "$1" && shift && exec "$@"' sh "$INSTALL_DIR" "$@"
}

# The repository is public: no PAT, deploy key or persistent Git credential is needed.
if ! runuser -u cubynode -- git ls-remote --exit-code "$REPO_HTTPS" "refs/heads/$CHANNEL" >/dev/null 2>&1; then
  echo "Unable to read public repository branch $OWNER/$REPO:$CHANNEL." >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
install -d -o cubynode -g cubynode -m 0755 "$INSTALL_DIR"
runuser -u cubynode -- git clone --branch "$CHANNEL" --single-branch "$REPO_HTTPS" "$INSTALL_DIR"
runuser -u cubynode -- git -C "$INSTALL_DIR" remote set-url origin "$REPO_HTTPS"

run_cubynode_repo npm install --omit=dev --no-audit --no-fund --package-lock=false
run_cubynode_repo npm run check

DB_PASS="$(openssl rand -hex 24)"
PANEL_TOKEN="$(openssl rand -hex 32)"
AGENT_TOKEN="$(openssl rand -hex 32)"
HOST_ID="$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
[[ -n "$HOST_ID" ]] || HOST_ID="control"

if sudo -u postgres psql -tAc "select 1 from pg_roles where rolname='cubynode'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "alter role cubynode with login password '$DB_PASS';"
else
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "create role cubynode with login password '$DB_PASS';"
fi
sudo -u postgres psql -tAc "select 1 from pg_database where datname='cubynode'" | grep -q 1 ||
  sudo -u postgres createdb -O cubynode cubynode

VERSION="$(run_cubynode_repo node -p 'require("./package.json").version')"
cat >"$ENV_FILE" <<ENV
DATABASE_URL=postgresql://cubynode:$DB_PASS@127.0.0.1:5432/cubynode
CUBYNODE_PANEL_TOKEN=$PANEL_TOKEN
CUBYNODE_AGENT_TOKEN=$AGENT_TOKEN
CUBYNODE_AGENT_URLS=http://127.0.0.1:8081
CUBYNODE_NODE_ID=control-$HOST_ID
CUBYNODE_NODE_NAME=CubyNode Control Plane
CUBYNODE_API_PORT=8080
CUBYNODE_AGENT_PORT=8081
CUBYNODE_METRICS_ROOT=/
CUBYNODE_VERSION=$VERSION
CUBYNODE_INSTALL_MODE=native-lxc
CUBYNODE_REPO_DIR=$INSTALL_DIR
CUBYNODE_UPDATE_CHANNEL=$CHANNEL
CUBYNODE_UPDATE_HELPER=/usr/local/sbin/cubynode-update-request
CUBYNODE_UPDATE_STATUS=$STATE_DIR/update-status.json
CUBYNODE_UPDATE_LOG=$LOG_DIR/update.log
ENV
chown root:cubynode "$ENV_FILE"
chmod 0640 "$ENV_FILE"

install -o root -g root -m 0644 "$INSTALL_DIR/install/systemd/cubynode-agent.service" /etc/systemd/system/cubynode-agent.service
install -o root -g root -m 0644 "$INSTALL_DIR/install/systemd/cubynode-api.service" /etc/systemd/system/cubynode-api.service
install -o root -g root -m 0755 "$INSTALL_DIR/scripts/cubynode-update" /usr/local/sbin/cubynode-update
install -o root -g root -m 0755 "$INSTALL_DIR/scripts/cubynode-update-request" /usr/local/sbin/cubynode-update-request

cat >/etc/sudoers.d/cubynode-updater <<'SUDOERS'
cubynode ALL=(root) NOPASSWD: /usr/local/sbin/cubynode-update-request simple
cubynode ALL=(root) NOPASSWD: /usr/local/sbin/cubynode-update-request full
SUDOERS
chmod 0440 /etc/sudoers.d/cubynode-updater
visudo -cf /etc/sudoers.d/cubynode-updater >/dev/null

cat >"$STATE_DIR/update-status.json" <<JSON
{"state":"idle","mode":null,"message":"No update has been run yet.","fromCommit":null,"toCommit":null,"rebootRequired":false,"updatedAt":null}
JSON
chown root:cubynode "$STATE_DIR/update-status.json"
chmod 0640 "$STATE_DIR/update-status.json"

touch "$LOG_DIR/update.log"
chown root:cubynode "$LOG_DIR/update.log"
chmod 0640 "$LOG_DIR/update.log"

cat >/root/cubynode-credentials <<CREDS
CubyNode URL: http://$(hostname -I | awk '{print $1}'):8080
Panel token: $PANEL_TOKEN
Version: $VERSION
Channel: $CHANNEL
Git access: public HTTPS
CREDS
chmod 0600 /root/cubynode-credentials

systemctl daemon-reload
systemctl enable --now cubynode-agent.service cubynode-api.service

for _ in {1..30}; do
  curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:8080/api/health >/dev/null

echo
echo "CubyNode installation complete."
cat /root/cubynode-credentials
