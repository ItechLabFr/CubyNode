#!/usr/bin/env bash
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main"
DEFAULT_DISK_GB=20
DEFAULT_MEMORY_MB=2048
DEFAULT_CORES=2
DEFAULT_SWAP_MB=512

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root on the Proxmox VE host." >&2
  exit 1
fi
for cmd in pct pvesm pveam pvesh curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing Proxmox command: $cmd" >&2; exit 1; }
done

choose() {
  local prompt="$1"; shift
  local options=("$@")
  [[ "${#options[@]}" -gt 0 ]] || { echo "No option available for: $prompt" >&2; exit 1; }
  if [[ "${#options[@]}" -eq 1 ]]; then printf '%s' "${options[0]}"; return; fi
  echo >&2
  echo "$prompt" >&2
  local i
  for i in "${!options[@]}"; do printf '  %d) %s\n' "$((i+1))" "${options[$i]}" >&2; done
  local answer
  while true; do
    read -r -p "> " answer
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer>=1 && answer<=${#options[@]})); then
      printf '%s' "${options[$((answer-1))]}"
      return
    fi
  done
}

mapfile -t TEMPLATE_STORAGES < <(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
TEMPLATE_STORAGE="${CUBYNODE_TEMPLATE_STORAGE:-}"
[[ -n "$TEMPLATE_STORAGE" ]] || TEMPLATE_STORAGE="$(choose "Stockage des templates LXC" "${TEMPLATE_STORAGES[@]}")"

pveam update >/dev/null
mapfile -t AVAILABLE_TEMPLATES < <(pveam available --section system 2>/dev/null | awk '$1=="system"{print $2}' | grep -E '^(debian-(12|13)-standard|ubuntu-24\.04-standard)_' | sort -Vr)
[[ "${#AVAILABLE_TEMPLATES[@]}" -gt 0 ]] || { echo "No supported Debian/Ubuntu LXC template found." >&2; exit 1; }
LXC_TEMPLATE="${CUBYNODE_LXC_TEMPLATE:-}"
if [[ -z "$LXC_TEMPLATE" ]]; then
  LXC_TEMPLATE="$(printf '%s\n' "${AVAILABLE_TEMPLATES[@]}" | grep '^debian-13-standard_' | head -n1 || true)"
  [[ -n "$LXC_TEMPLATE" ]] || LXC_TEMPLATE="${AVAILABLE_TEMPLATES[0]}"
fi
echo "Template selected automatically: $LXC_TEMPLATE"

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk 'NR>1{print $1}' | grep -Fq "vztmpl/$LXC_TEMPLATE"; then
  echo "Downloading $LXC_TEMPLATE to $TEMPLATE_STORAGE..."
  pveam download "$TEMPLATE_STORAGE" "$LXC_TEMPLATE"
fi
TEMPLATE_REF="$TEMPLATE_STORAGE:vztmpl/$LXC_TEMPLATE"

mapfile -t ROOT_STORAGES < <(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
ROOT_STORAGE="${CUBYNODE_ROOTFS_STORAGE:-}"
[[ -n "$ROOT_STORAGE" ]] || ROOT_STORAGE="$(choose "Stockage du disque LXC" "${ROOT_STORAGES[@]}")"

DISK_GB="${CUBYNODE_DISK_GB:-}"
if [[ -z "$DISK_GB" ]]; then
  read -r -p "Taille disque LXC en Go [$DEFAULT_DISK_GB]: " DISK_GB
  DISK_GB="${DISK_GB:-$DEFAULT_DISK_GB}"
fi
[[ "$DISK_GB" =~ ^[0-9]+$ ]] && ((DISK_GB>=8)) || { echo "Disk size must be an integer >= 8 GB." >&2; exit 1; }

CTID="$(pvesh get /cluster/nextid)"
BRIDGE="$(ip -o link show type bridge 2>/dev/null | awk -F': ' '$2 ~ /^vmbr/{print $2; exit}')"
BRIDGE="${BRIDGE:-vmbr0}"
HOSTNAME="cubynode-$CTID"

echo
echo "Creating LXC $CTID ($HOSTNAME)..."
pct create "$CTID" "$TEMPLATE_REF"   --hostname "$HOSTNAME"   --rootfs "$ROOT_STORAGE:$DISK_GB"   --cores "$DEFAULT_CORES"   --memory "$DEFAULT_MEMORY_MB"   --swap "$DEFAULT_SWAP_MB"   --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp,type=veth"   --unprivileged 1   --onboot 1   --start 1

echo "Waiting for LXC network..."
for _ in {1..60}; do
  if pct exec "$CTID" -- bash -lc 'getent hosts github.com >/dev/null 2>&1'; then break; fi
  sleep 2
done
pct exec "$CTID" -- bash -lc 'getent hosts github.com >/dev/null 2>&1' || {
  echo "The LXC has no network/DNS access. CTID=$CTID" >&2
  exit 1
}

TMP_BOOTSTRAP="/tmp/cubynode-lxc-bootstrap-$CTID.sh"
curl -fsSL "$REPO_RAW/scripts/lxc-bootstrap.sh" -o "$TMP_BOOTSTRAP"
pct push "$CTID" "$TMP_BOOTSTRAP" /root/cubynode-bootstrap.sh --perms 0755
rm -f "$TMP_BOOTSTRAP"

echo "Installing CubyNode inside the LXC..."
pct exec "$CTID" -- env CUBYNODE_UPDATE_CHANNEL=main bash /root/cubynode-bootstrap.sh

IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \\$1}'" 2>/dev/null | tr -d '\r')"
echo
echo "============================================================"
echo " CubyNode 1.0.0-beta.1 installed"
echo " CTID:       $CTID"
echo " Template:   $LXC_TEMPLATE"
echo " Disk:       $ROOT_STORAGE:$DISK_GB GB"
echo " Panel:      http://$IP:8080"
echo "============================================================"
echo
pct exec "$CTID" -- cat /root/cubynode-credentials
