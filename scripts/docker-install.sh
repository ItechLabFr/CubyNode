#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${CUBYNODE_REPO_URL:-https://github.com/ItechLabFr/CubyNode.git}"
CHANNEL="${CUBYNODE_CHANNEL:-main}"
INSTALL_DIR="${CUBYNODE_INSTALL_DIR:-/opt/cubynode}"

die(){ echo "CubyNode: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "$1 is required."; }

need git
need docker

docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required."
docker info >/dev/null 2>&1 || die "Docker daemon is unavailable for the current user."

if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
  die "$INSTALL_DIR already exists and is not a Git checkout."
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --prune origin "$CHANNEL"
  git -C "$INSTALL_DIR" checkout -B "$CHANNEL" "origin/$CHANNEL"
else
  install -d "$(dirname "$INSTALL_DIR")"
  git clone --branch "$CHANNEL" --single-branch "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

if [[ -n "${CUBYNODE_HTTP_PORT:-}" && ! -f .env ]]; then
  export CUBYNODE_HTTP_PORT
fi

./scripts/install.sh

echo
echo "CubyNode Docker installation complete."
echo "Directory: $INSTALL_DIR"
