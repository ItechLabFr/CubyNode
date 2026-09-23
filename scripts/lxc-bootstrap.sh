#!/usr/bin/env bash
set -Eeuo pipefail

OWNER="ItechLabFr"
REPO="CubyNode"
REPO_HTTPS="https://github.com/$OWNER/$REPO.git"
REPO_SSH="git@github.com:$OWNER/$REPO.git"
CHANNEL="${CUBYNODE_UPDATE_CHANNEL:-main}"
# The host launcher uses CUBYNODE_GITHUB_TOKEN_FILE for its host-side PAT.
# pct exec can propagate that host path into the container; the container
# must ALWAYS read the file pct push placed at this fixed in-container path.
TOKEN_FILE="/root/.cubynode-github-token"
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
GIT_ASKPASS_FILE="$(mktemp /tmp/cubynode-git-askpass.XXXXXX)"
GIT_SECRET_FILE="$(mktemp /tmp/cubynode-git-secret.XXXXXX)"
chmod 0600 "$TOKEN_HEADER_FILE" "$GIT_SECRET_FILE"
chmod 0700 "$GIT_ASKPASS_FILE"
printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" >"$TOKEN_HEADER_FILE"

# GitHub REST accepts Bearer for the download, but Git over HTTPS expects
# a username and a PAT supplied as the password. Use a temporary askpass
# helper: nothing secret is placed in argv, clone URLs or git config.
printf '%s' "$GITHUB_TOKEN" >"$GIT_SECRET_FILE"
cat >"$GIT_ASKPASS_FILE" <<'ASKPASS'
#!/bin/sh
case "${1:-}" in
  *Username*|*username*) printf '%s\n' 'x-access-token' ;;
  *Password*|*password*) exec cat "$CUBYNODE_GIT_TOKEN_FILE" ;;
  *) exit 1 ;;
esac
ASKPASS

cleanup_token(){
  unset GITHUB_TOKEN
  local secret
  for secret in "$TOKEN_FILE" "$TOKEN_HEADER_FILE" "$GIT_SECRET_FILE" "$GIT_ASKPASS_FILE"; do
    [[ ! -e "$secret" ]] || shred -u "$secret" 2>/dev/null || rm -f "$secret"
  done
}
trap cleanup_token EXIT

export DEBIAN_FRONTEND=noninteractive
# apt may encounter temporary DNS errors after the launcher preflight has
# succeeded. Retry DNS before apt, and retry transient apt fetch failures.
DNS_READY=false
for _ in {1..12}; do
  if getent ahostsv4 deb.debian.org >/dev/null 2>&1 &&
     getent ahostsv4 security.debian.org >/dev/null 2>&1 &&
     getent ahostsv4 deb.nodesource.com >/dev/null 2>&1 &&
     getent ahostsv4 github.com >/dev/null 2>&1; then
    DNS_READY=true
    break
  fi
  echo "Waiting for Debian/NodeSource/GitHub DNS resolution..." >&2
  sleep 5
done
if ! $DNS_READY; then
  echo "DNS resolution inside this LXC is unavailable. Check /etc/resolv.conf, the DHCP gateway and Proxmox nameserver settings; do not recreate the container." >&2
  exit 1
fi
apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 install -y ca-certificates curl git openssh-client sudo postgresql postgresql-contrib openssl python3 util-linux xz-utils

if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || echo 0)" -lt 24 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get -o Acquire::Retries=5 install -y nodejs
fi
systemctl enable --now postgresql

if ! id cubynode >/dev/null 2>&1; then useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin cubynode; fi
chown cubynode:cubynode "$GIT_SECRET_FILE" "$GIT_ASKPASS_FILE"
install -d -o root -g cubynode -m 0750 "$ENV_DIR" "$STATE_DIR" "$LOG_DIR"

# Verify HTTPS Git access before altering the installation tree.
git_private() {
  runuser -u cubynode -- env \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS="$GIT_ASKPASS_FILE" \
    CUBYNODE_GIT_TOKEN_FILE="$GIT_SECRET_FILE" \
    git -c credential.helper= "$@"
}
if ! git_private ls-remote --exit-code "$REPO_HTTPS" "refs/heads/$CHANNEL" >/dev/null; then
  echo "GitHub private clone authentication failed. Ensure the fine-grained PAT has Contents: Read on $OWNER/$REPO and that its owner has repository access." >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
install -d -o cubynode -g cubynode -m 0755 "$INSTALL_DIR"
git_private clone --branch "$CHANNEL" --single-branch "$REPO_HTTPS" "$INSTALL_DIR"

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
