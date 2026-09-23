#!/usr/bin/env bash
set -Eeuo pipefail

OWNER="ItechLabFr"
REPO="CubyNode"
REPO_HTTPS="https://github.com/$OWNER/$REPO.git"
REPO_SSH="git@github.com:$OWNER/$REPO.git"
CHANNEL="${CUBYNODE_UPDATE_CHANNEL:-main}"
TOKEN_FILE="${CUBYNODE_GITHUB_TOKEN_FILE:-/root/.cubynode-github-token}"
INSTALL_DIR="/opt/cubynode"
ENV_DIR="/etc/cubynode"
ENV_FILE="$ENV_DIR/cubynode.env"
STATE_DIR="/var/lib/cubynode"
LOG_DIR="/var/log/cubynode"
DEPLOY_KEY="$STATE_DIR/github_deploy_key"
KNOWN_HOSTS="$ENV_DIR/github_known_hosts"

[[ "${EUID}" -eq 0 ]] || { echo "This bootstrap must run as root inside the LXC." >&2; exit 1; }
if [[ ! -e "$TOKEN_FILE" ]]; then
  echo "Temporary GitHub token file does not exist in the LXC: $TOKEN_FILE" >&2
  exit 1
fi
if [[ ! -s "$TOKEN_FILE" || ! -r "$TOKEN_FILE" ]]; then
  echo "Temporary GitHub token file is empty or unreadable in the LXC: $TOKEN_FILE" >&2
  exit 1
fi
GITHUB_TOKEN="$(cat "$TOKEN_FILE")"
TOKEN_HEADER_FILE="$(mktemp /root/.cubynode-github-header.XXXXXX)"
GIT_AUTH_CONFIG="$(mktemp /tmp/cubynode-git-auth.XXXXXX)"
chmod 0600 "$TOKEN_HEADER_FILE" "$GIT_AUTH_CONFIG"
printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" >"$TOKEN_HEADER_FILE"

cleanup_token(){
  unset GITHUB_TOKEN
  shred -u "$TOKEN_FILE" "$TOKEN_HEADER_FILE" "$GIT_AUTH_CONFIG" 2>/dev/null || rm -f "$TOKEN_FILE" "$TOKEN_HEADER_FILE" "$GIT_AUTH_CONFIG"
}
trap cleanup_token EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssh-client sudo postgresql postgresql-contrib openssl python3 util-linux xz-utils

if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi
systemctl enable --now postgresql

if ! id cubynode >/dev/null 2>&1; then useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin cubynode; fi
install -d -o root -g cubynode -m 0750 "$ENV_DIR" "$STATE_DIR" "$LOG_DIR"

# Clone the private repository using an ephemeral HTTP Authorization header.
rm -rf "$INSTALL_DIR"
install -d -o cubynode -g cubynode -m 0755 "$INSTALL_DIR"
# Write sensitive Git config without putting the token on a process command line.
printf '[http]\\n\\textraHeader = Authorization: Bearer %s\\n' "$GITHUB_TOKEN" >"$GIT_AUTH_CONFIG"
chown cubynode:cubynode "$GIT_AUTH_CONFIG"
runuser -u cubynode -- git -c "include.path=$GIT_AUTH_CONFIG" clone --branch "$CHANNEL" --single-branch "$REPO_HTTPS" "$INSTALL_DIR"

# Generate a dedicated read-only SSH deploy key for all future Git operations.
ssh-keygen -q -t ed25519 -N '' -C "cubynode-$(hostname)" -f "$DEPLOY_KEY"
chown cubynode:cubynode "$DEPLOY_KEY" "$DEPLOY_KEY.pub"; chmod 0600 "$DEPLOY_KEY"; chmod 0644 "$DEPLOY_KEY.pub"
ssh-keyscan -t ed25519 github.com >"$KNOWN_HOSTS" 2>/dev/null
chown root:cubynode "$KNOWN_HOSTS"; chmod 0640 "$KNOWN_HOSTS"

PUBKEY="$(cat "$DEPLOY_KEY.pub")"
TITLE="CubyNode $(hostname) $(date -u +%Y%m%dT%H%M%SZ)"
HTTP_CODE="$(curl -sS -o /tmp/cubynode-deploy-key-response.json -w '%{http_code}'   -X POST   -H @"$TOKEN_HEADER_FILE"   -H "Accept: application/vnd.github+json"   -H "X-GitHub-Api-Version: 2026-03-10"   "https://api.github.com/repos/$OWNER/$REPO/keys"   -d "$(python3 -c 'import json,sys; print(json.dumps({"title":sys.argv[1],"key":sys.argv[2],"read_only":True}))' "$TITLE" "$PUBKEY")")"
if [[ "$HTTP_CODE" != "201" ]]; then
  echo "GitHub refused deploy-key creation (HTTP $HTTP_CODE)." >&2
  cat /tmp/cubynode-deploy-key-response.json >&2 || true
  echo "The temporary PAT needs Administration: Read/Write on this repository." >&2
  exit 1
fi
rm -f /tmp/cubynode-deploy-key-response.json

SSH_COMMAND="ssh -i $DEPLOY_KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=yes"
runuser -u cubynode -- git -C "$INSTALL_DIR" remote set-url origin "$REPO_SSH"
runuser -u cubynode -- git -C "$INSTALL_DIR" config core.sshCommand "$SSH_COMMAND"
runuser -u cubynode -- git -C "$INSTALL_DIR" fetch --prune origin "$CHANNEL"

# The PAT is no longer needed after the deploy key exists.
cleanup_token
trap - EXIT

runuser -u cubynode -- npm --prefix "$INSTALL_DIR" install --omit=dev --no-audit --no-fund --package-lock=false
runuser -u cubynode -- npm --prefix "$INSTALL_DIR" run check

DB_PASS="$(openssl rand -hex 24)"; PANEL_TOKEN="$(openssl rand -hex 32)"; AGENT_TOKEN="$(openssl rand -hex 32)"
HOST_ID="$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"; [[ -n "$HOST_ID" ]] || HOST_ID="control"

if sudo -u postgres psql -tAc "select 1 from pg_roles where rolname='cubynode'" | grep -q 1; then
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "alter role cubynode with login password '$DB_PASS';"
else
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "create role cubynode with login password '$DB_PASS';"
fi
sudo -u postgres psql -tAc "select 1 from pg_database where datname='cubynode'" | grep -q 1 || sudo -u postgres createdb -O cubynode cubynode

VERSION="$(runuser -u cubynode -- node -p "require('$INSTALL_DIR/package.json').version")"
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
chown root:cubynode "$ENV_FILE"; chmod 0640 "$ENV_FILE"

install -o root -g root -m 0644 "$INSTALL_DIR/install/systemd/cubynode-agent.service" /etc/systemd/system/cubynode-agent.service
install -o root -g root -m 0644 "$INSTALL_DIR/install/systemd/cubynode-api.service" /etc/systemd/system/cubynode-api.service
install -o root -g root -m 0755 "$INSTALL_DIR/scripts/cubynode-update" /usr/local/sbin/cubynode-update
install -o root -g root -m 0755 "$INSTALL_DIR/scripts/cubynode-update-request" /usr/local/sbin/cubynode-update-request

cat >/etc/sudoers.d/cubynode-updater <<'SUDOERS'
cubynode ALL=(root) NOPASSWD: /usr/local/sbin/cubynode-update-request simple
cubynode ALL=(root) NOPASSWD: /usr/local/sbin/cubynode-update-request full
SUDOERS
chmod 0440 /etc/sudoers.d/cubynode-updater; visudo -cf /etc/sudoers.d/cubynode-updater >/dev/null

cat >"$STATE_DIR/update-status.json" <<JSON
{"state":"idle","mode":null,"message":"No update has been run yet.","fromCommit":null,"toCommit":null,"rebootRequired":false,"updatedAt":null}
JSON
chown root:cubynode "$STATE_DIR/update-status.json"; chmod 0640 "$STATE_DIR/update-status.json"
touch "$LOG_DIR/update.log"; chown root:cubynode "$LOG_DIR/update.log"; chmod 0640 "$LOG_DIR/update.log"

cat >/root/cubynode-credentials <<CREDS
CubyNode URL: http://$(hostname -I | awk '{print $1}'):8080
Panel token: $PANEL_TOKEN
Version: $VERSION
Channel: $CHANNEL
Git access: read-only deploy key
CREDS
chmod 0600 /root/cubynode-credentials

systemctl daemon-reload
systemctl enable --now cubynode-agent.service cubynode-api.service
for _ in {1..30}; do curl -fsS http://127.0.0.1:8080/api/health >/dev/null 2>&1 && break; sleep 1; done
curl -fsS http://127.0.0.1:8080/api/health >/dev/null
echo; echo "CubyNode installation complete."; cat /root/cubynode-credentials
