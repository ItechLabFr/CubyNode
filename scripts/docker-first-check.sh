#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(git rev-parse --show-toplevel)"

matches="$(
  git grep -nEi '\b(incus|proxmox|lxc)\b' -- .     ':(exclude)scripts/docker-first-check.sh' || true
)"

if [[ -n "$matches" ]]; then
  echo "Docker-first check failed: deferred runtime references found in tracked files:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

echo "Docker-first check OK."
