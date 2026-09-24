#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${CUBYNODE_INSTALL_DIR:-/opt/cubynode}"
CHANNEL="${CUBYNODE_CHANNEL:-main}"

[[ -d "$INSTALL_DIR/.git" ]] || { echo "CubyNode Git checkout not found: $INSTALL_DIR" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required." >&2; exit 1; }

cd "$INSTALL_DIR"
[[ -f .env ]] || { echo "Missing $INSTALL_DIR/.env" >&2; exit 1; }

git fetch --prune origin "$CHANNEL"
git checkout -B "$CHANNEL" "origin/$CHANNEL"

docker compose build --pull api agent
docker compose pull postgres
docker compose up -d --remove-orphans

echo
echo "CubyNode updated to $(git rev-parse --short HEAD)."
docker compose ps
