#!/usr/bin/env sh
set -eu

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required." >&2
  exit 1
fi

if [ ! -f .env ]; then
  random_hex() {
    bytes="$1"
    if command -v openssl >/dev/null 2>&1; then
      openssl rand -hex "$bytes"
    elif command -v od >/dev/null 2>&1; then
      od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
    else
      echo "openssl or od is required to generate secure secrets." >&2
      exit 1
    fi
  }
  panel_token="$(random_hex 32)"
  agent_token="$(random_hex 32)"
  postgres_password="$(random_hex 24)"

  cat > .env <<ENV
POSTGRES_DB=cubynode
POSTGRES_USER=cubynode
POSTGRES_PASSWORD=${postgres_password}
CUBYNODE_PANEL_TOKEN=${panel_token}
CUBYNODE_AGENT_TOKEN=${agent_token}
CUBYNODE_NODE_ID=$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
CUBYNODE_NODE_NAME=$(hostname)
CUBYNODE_HTTP_PORT=8080
ENV
  chmod 600 .env
fi

docker compose up -d --build

printf '\nCubyNode is starting.\n'
printf 'Panel: http://localhost:%s\n' "$(grep '^CUBYNODE_HTTP_PORT=' .env | cut -d= -f2)"
printf 'Access token: %s\n' "$(grep '^CUBYNODE_PANEL_TOKEN=' .env | cut -d= -f2-)"
printf '\nThe token is stored in .env. Keep it private.\n'
