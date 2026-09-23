#!/usr/bin/env bash
set -Eeuo pipefail

OWNER="ItechLabFr"
REPO="CubyNode"
CHANNEL="${CUBYNODE_UPDATE_CHANNEL:-main}"
API="https://api.github.com/repos/$OWNER/$REPO"
VERSION_LABEL="1.0.0-beta.1"

DEFAULT_DISK_GB=20
DEFAULT_MEMORY_MB=2048
DEFAULT_CORES=2
DEFAULT_SWAP_MB=512
LOG_FILE="/var/log/cubynode-lxc-installer.log"

TUI=false
[[ -t 0 && -t 1 ]] && command -v whiptail >/dev/null 2>&1 && TUI=true

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CYAN=$'\033[38;5;45m'; BLUE=$'\033[38;5;39m'; GREEN=$'\033[38;5;82m'
  RED=$'\033[38;5;203m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  CYAN=""; BLUE=""; GREEN=""; RED=""; BOLD=""; DIM=""; RESET=""
fi

AUTH_FILE=""
TMP_BOOTSTRAP=""
TMP_TOKEN=""
GITHUB_TOKEN=""

cleanup() {
  rm -f "${AUTH_FILE:-}" "${TMP_BOOTSTRAP:-}" "${TMP_TOKEN:-}"
  unset GITHUB_TOKEN CUBYNODE_GITHUB_TOKEN
}
trap cleanup EXIT

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

banner() {
  clear 2>/dev/null || true
  printf '%s%s' "$CYAN" "$BOLD"
  cat <<'EOF'
╭────────────────────────────────────────────────────╮
│                                                    │
│        ◇────◇       C U B Y N O D E                │
│       ╱      ╲      LXC INSTALLER                   │
│      ◇───◇────◇                                     │
│       ╲ ╱ ╲  ╱      Minecraft • Discord             │
│        ◇───◇       Proxmox VE                      │
│                                                    │
╰────────────────────────────────────────────────────╯
EOF
  printf '%s' "$RESET"
  printf '  %s%s%s  ·  %sProxmox VE → LXC natif%s\n\n' "$DIM" "$VERSION_LABEL" "$RESET" "$DIM" "$RESET"
}

die() {
  local message="$1"
  if $TUI; then
    whiptail --title "CubyNode • Erreur" --msgbox "$message\n\nLog : $LOG_FILE" 11 74
  else
    printf '\n%s✕ %s%s\nLog : %s\n' "$RED" "$message" "$RESET" "$LOG_FILE" >&2
  fi
  exit 1
}

on_error() {
  local rc=$? line="${BASH_LINENO[0]:-?}" log_tail
  log_tail="$(tail -n 8 "$LOG_FILE" 2>/dev/null || true)"
  if $TUI; then
    whiptail --title "CubyNode • Installation interrompue" --msgbox       "Une erreur est survenue (ligne $line, code $rc).\n\n$log_tail\n\nLog complet : $LOG_FILE" 20 78
  else
    printf '\n%s✕ Installation interrompue%s (ligne %s, code %s)\n%s\n' "$RED" "$RESET" "$line" "$rc" "$log_tail" >&2
  fi
  exit "$rc"
}
trap on_error ERR

step() {
  local n="$1" total="$2" title="$3" detail="${4:-}"
  if $TUI; then
    whiptail --title "CubyNode • Étape $n/$total" --infobox "$title\n\n$detail" 10 72
  else
    printf '\n%s[%s/%s]%s %s%s%s\n' "$BLUE" "$n" "$total" "$RESET" "$BOLD" "$title" "$RESET"
    [[ -n "$detail" ]] && printf '      %s%s%s\n' "$DIM" "$detail" "$RESET"
  fi
}

ok() { $TUI || printf '      %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }

password_box() {
  local text="$1" value
  if $TUI; then
    value="$(whiptail --title "CubyNode • GitHub privé" --passwordbox "$text" 12 76 3>&1 1>&2 2>&3)" || exit 130
  else
    read -r -s -p "GitHub token: " value
    echo
  fi
  printf '%s' "$value"
}

storage_menu() {
  local title="$1" content="$2"; shift 2
  local options=("$@")
  [[ "${#options[@]}" -gt 0 ]] || die "Aucun stockage compatible avec $content."

  if [[ "${#options[@]}" -eq 1 ]]; then
    printf '%s' "${options[0]}"
    return
  fi

  if $TUI; then
    local args=() item info
    for item in "${options[@]}"; do
      info="$(pvesm status 2>/dev/null | awk -v id="$item" 'NR>1 && $1==id {printf "%s • %s • %s", $2,$3,$6; exit}')"
      [[ -n "$info" ]] || info="stockage actif"
      args+=("$item" "$info")
    done
    whiptail --title "CubyNode • $title" --menu       "Choisis le stockage pour $content." 19 78 10 "${args[@]}" 3>&1 1>&2 2>&3 || exit 130
  else
    printf '\n%s%s%s\n' "$BOLD" "$title" "$RESET" >&2
    local i answer
    for i in "${!options[@]}"; do printf '  %s%d)%s %s\n' "$CYAN" "$((i+1))" "$RESET" "${options[$i]}" >&2; done
    while true; do
      read -r -p "> " answer
      if [[ "$answer" =~ ^[0-9]+$ ]] && ((answer>=1 && answer<=${#options[@]})); then
        printf '%s' "${options[$((answer-1))]}"
        return
      fi
    done
  fi
}

disk_box() {
  local value
  if [[ -n "${CUBYNODE_DISK_GB:-}" ]]; then printf '%s' "$CUBYNODE_DISK_GB"; return; fi
  if $TUI; then
    value="$(whiptail --title "CubyNode • Taille du disque" --inputbox       "Taille du disque système du LXC en Go.\n\nMinimum : 8 Go" 12 70 "$DEFAULT_DISK_GB" 3>&1 1>&2 2>&3)" || exit 130
  else
    read -r -p "Taille du disque LXC en Go [$DEFAULT_DISK_GB]: " value
    value="${value:-$DEFAULT_DISK_GB}"
  fi
  printf '%s' "$value"
}

confirm_install() {
  local message="$1"
  if $TUI; then
    whiptail --title "CubyNode • Résumé" --yes-button "Installer" --no-button "Annuler" --yesno "$message" 22 78
  else
    printf '\n%s%sRésumé%s\n%s\n' "$CYAN" "$BOLD" "$RESET" "$message"
    read -r -p "Lancer l'installation ? [O/n] " answer
    [[ ! "$answer" =~ ^[Nn] ]]
  fi
}

progress() {
  local percent="$1" title="$2" filled empty bar
  filled=$((percent/5)); empty=$((20-filled))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"
  if $TUI; then
    whiptail --title "CubyNode • Installation" --infobox "$title\n\n[$bar]  $percent%" 10 72
  else
    printf '      %s✓%s %-34s %3s%%\n' "$GREEN" "$RESET" "$title" "$percent"
  fi
}

github_raw() {
  local file="$1" output="$2"
  curl -fsSL     -H @"$AUTH_FILE"     -H "Accept: application/vnd.github.raw+json"     "$API/contents/$file?ref=$CHANNEL"     -o "$output" >>"$LOG_FILE" 2>&1
}

[[ "${EUID}" -eq 0 ]] || die "Lance ce script en root sur le host Proxmox VE."
for cmd in pct pvesm pveam pvesh curl ip awk dpkg; do
  command -v "$cmd" >/dev/null 2>&1 || die "Commande Proxmox manquante : $cmd"
done

banner

step 1 6 "Accès au dépôt privé" "Le PAT est temporaire et sera remplacé par une Deploy Key GitHub read-only."
if [[ -n "${CUBYNODE_GITHUB_TOKEN_FILE:-}" && -r "$CUBYNODE_GITHUB_TOKEN_FILE" ]]; then
  GITHUB_TOKEN="$(cat "$CUBYNODE_GITHUB_TOKEN_FILE")"
elif [[ -n "${CUBYNODE_GITHUB_TOKEN:-}" ]]; then
  GITHUB_TOKEN="$CUBYNODE_GITHUB_TOKEN"
else
  GITHUB_TOKEN="$(password_box "Fine-grained PAT pour $OWNER/$REPO\n\nContents: Read-only\nAdministration: Read/Write")"
fi
unset CUBYNODE_GITHUB_TOKEN
[[ -n "$GITHUB_TOKEN" ]] || die "Le token GitHub est requis tant que le dépôt est privé."

AUTH_FILE="$(mktemp /tmp/cubynode-github-auth.XXXXXX)"
chmod 0600 "$AUTH_FILE"
printf 'Authorization: Bearer %s\n' "$GITHUB_TOKEN" >"$AUTH_FILE"
curl -fsSL -H @"$AUTH_FILE" -H "Accept: application/vnd.github+json" "$API" >/dev/null 2>>"$LOG_FILE"   || die "Le token ne permet pas d'accéder à $OWNER/$REPO."
ok "Dépôt privé accessible"

step 2 6 "Stockage du template" "Détection des stockages Proxmox compatibles LXC."
mapfile -t TEMPLATE_STORAGES < <(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
TEMPLATE_STORAGE="${CUBYNODE_TEMPLATE_STORAGE:-}"
[[ -n "$TEMPLATE_STORAGE" ]] || TEMPLATE_STORAGE="$(storage_menu "Template LXC" "les templates LXC" "${TEMPLATE_STORAGES[@]}")"
ok "Template storage : $TEMPLATE_STORAGE"

step 3 6 "Template système" "Sélection automatique du dernier Debian 13 pour l'architecture de l'hôte."

# Native LXC executes /sbin/init using the host kernel: never select an
# ARM64 rootfs on an amd64 Proxmox host (or vice versa). That would fail
# before systemd starts with "Exec format error".
HOST_ARCH="$(dpkg --print-architecture)"
case "$HOST_ARCH" in
  amd64|arm64) ;;
  *) die "Architecture Proxmox non prise en charge automatiquement : $HOST_ARCH." ;;
esac
pveam update >>"$LOG_FILE" 2>&1
mapfile -t AVAILABLE_TEMPLATES < <(
  pveam available --section system 2>/dev/null |
    awk '$1=="system"{print $2}' |
    grep -E '^(debian-(12|13)-standard|ubuntu-24\.04-standard)_' |
    grep -E "_${HOST_ARCH}\.tar\.(zst|gz|xz)$" |
    sort -Vr
)
[[ "${#AVAILABLE_TEMPLATES[@]}" -gt 0 ]] || die "Aucun template Debian/Ubuntu compatible $HOST_ARCH trouvé dans pveam."

LXC_TEMPLATE="${CUBYNODE_LXC_TEMPLATE:-}"
if [[ -z "$LXC_TEMPLATE" ]]; then
  LXC_TEMPLATE="$(printf '%s\n' "${AVAILABLE_TEMPLATES[@]}" | grep '^debian-13-standard_' | head -n1 || true)"
  [[ -n "$LXC_TEMPLATE" ]] || LXC_TEMPLATE="${AVAILABLE_TEMPLATES[0]}"
fi

# Reject even explicitly overridden templates when their architecture differs.
# This validation occurs BEFORE downloading or creating the container.
[[ "$LXC_TEMPLATE" =~ _${HOST_ARCH}\.tar\.(zst|gz|xz)$ ]] ||
  die "Template incompatible : $LXC_TEMPLATE. Hôte : $HOST_ARCH. Choisir un template _${HOST_ARCH}.tar.zst."
printf '%s\n' "${AVAILABLE_TEMPLATES[@]}" | grep -Fxq -- "$LXC_TEMPLATE" ||
  die "Template non disponible pour $HOST_ARCH : $LXC_TEMPLATE."

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | awk 'NR>1{print $1}' | grep -Fq "vztmpl/$LXC_TEMPLATE"; then
  pveam download "$TEMPLATE_STORAGE" "$LXC_TEMPLATE" >>"$LOG_FILE" 2>&1
fi
TEMPLATE_REF="$TEMPLATE_STORAGE:vztmpl/$LXC_TEMPLATE"
ok "$LXC_TEMPLATE • $HOST_ARCH"

step 4 6 "Stockage du LXC" "Choix du stockage du disque système."
mapfile -t ROOT_STORAGES < <(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
ROOT_STORAGE="${CUBYNODE_ROOTFS_STORAGE:-}"
[[ -n "$ROOT_STORAGE" ]] || ROOT_STORAGE="$(storage_menu "Disque LXC" "le disque système CubyNode" "${ROOT_STORAGES[@]}")"
DISK_GB="$(disk_box)"
[[ "$DISK_GB" =~ ^[0-9]+$ ]] && ((DISK_GB>=8)) || die "La taille du disque doit être un entier supérieur ou égal à 8 Go."
ok "$ROOT_STORAGE • $DISK_GB Go"

step 5 6 "Préparation" "Calcul du CTID et détection du bridge réseau."
CTID="$(pvesh get /cluster/nextid)"
BRIDGE="$(ip -o link show type bridge 2>/dev/null | awk -F': ' '$2 ~ /^vmbr/{print $2; exit}')"
BRIDGE="${BRIDGE:-vmbr0}"
HOSTNAME="cubynode-$CTID"

SUMMARY="CubyNode $VERSION_LABEL

CTID            $CTID
Hostname        $HOSTNAME
Template        $LXC_TEMPLATE
Architecture    $HOST_ARCH
Template store  $TEMPLATE_STORAGE
Disque          $ROOT_STORAGE • $DISK_GB Go

CPU             $DEFAULT_CORES cores
RAM             $DEFAULT_MEMORY_MB Mo
Swap            $DEFAULT_SWAP_MB Mo
Réseau          $BRIDGE • DHCP
Sécurité        LXC non privilégié
Nesting         activé (systemd 257)
Auto-start      activé"

confirm_install "$SUMMARY" || exit 0

step 6 6 "Installation" "Création et configuration du conteneur CubyNode."

# Important: do not start during pct create. nesting=1 must exist before the
# first boot for current Debian/systemd containers.
pct create "$CTID" "$TEMPLATE_REF"   --hostname "$HOSTNAME"   --description "CubyNode control plane • $VERSION_LABEL"   --rootfs "$ROOT_STORAGE:$DISK_GB"   --cores "$DEFAULT_CORES"   --memory "$DEFAULT_MEMORY_MB"   --swap "$DEFAULT_SWAP_MB"   --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp,type=veth"   --unprivileged 1   --features nesting=1   --onboot 1 >>"$LOG_FILE" 2>&1

progress 20 "LXC $CTID créé avec nesting=1"

# Always keep the first-boot debug trace: sync_wait/Failed to spawn alone
# does not identify the cause of an LXC startup failure.
START_LOG="/var/log/cubynode-lxc-start-${CTID}.log"
if ! pct start "$CTID" --debug >"$START_LOG" 2>&1; then
  chmod 0600 "$START_LOG"
  cat "$START_LOG" >>"$LOG_FILE"
  {
    printf '\n===== Proxmox version =====\n'
    pveversion -v || true
    printf '\n===== Container configuration =====\n'
    pct config "$CTID" || true
    printf '\n===== Proxmox container journal =====\n'
    journalctl -u "pve-container@${CTID}.service" -n 100 --no-pager || true
  } >>"$START_LOG" 2>&1

  # Surface relevant errors instead of the last eight incidental log lines
  # (which often contain only cleanup and the generic sync_wait message).
  START_CAUSE="$(grep -iE 'permission denied|failed to exec|no such file|exec format|apparmor|failed to (mount|setup|run)|prestart.*(failed|error)|symlink encountered|not permitted|cgroup' "$START_LOG" \
    | grep -ivE 'sync_wait:|failed to spawn container' | head -n 7 || true)"
  [[ -n "$START_CAUSE" ]] || START_CAUSE="Cause non identifiée dans le résumé. Consulter le log debug complet."

  ERROR_MESSAGE="Impossible de démarrer le LXC $CTID.

$START_CAUSE

Diagnostic enregistré dans :
$START_LOG

Le LXC n'a pas été supprimé.
Pour investiguer : pct start $CTID --debug"
  if $TUI; then
    whiptail --title "CubyNode • Diagnostic LXC $CTID" --scrolltext --msgbox "$ERROR_MESSAGE" 22 84
  else
    printf '\n%s✕ %s%s\n' "$RED" "$ERROR_MESSAGE" "$RESET" >&2
  fi
  exit 1
fi
chmod 0600 "$START_LOG"
cat "$START_LOG" >>"$LOG_FILE"
progress 35 "Premier démarrage réussi"

for _ in {1..60}; do
  pct exec "$CTID" -- bash -lc 'getent hosts github.com >/dev/null 2>&1' >>"$LOG_FILE" 2>&1 && break
  sleep 2
done
pct exec "$CTID" -- bash -lc 'getent hosts github.com >/dev/null 2>&1' >>"$LOG_FILE" 2>&1   || die "Le LXC a démarré mais n'a pas d'accès réseau/DNS."
progress 50 "Réseau et DNS disponibles"

TMP_BOOTSTRAP="/tmp/cubynode-lxc-bootstrap-$CTID.sh"
TMP_TOKEN="/tmp/cubynode-github-token-$CTID"
github_raw "scripts/lxc-bootstrap.sh" "$TMP_BOOTSTRAP"
printf '%s' "$GITHUB_TOKEN" >"$TMP_TOKEN"
chmod 0600 "$TMP_TOKEN"

# Proxmox must write both files as the container's root user.
# Verify that the token really exists and matches before deleting the host copy.
pct push "$CTID" "$TMP_BOOTSTRAP" /root/cubynode-bootstrap.sh --user root --group root --perms 0755 >>"$LOG_FILE" 2>&1
pct push "$CTID" "$TMP_TOKEN" /root/.cubynode-github-token --user root --group root --perms 0600 >>"$LOG_FILE" 2>&1

if ! pct exec "$CTID" -- /bin/sh -c 'test -s /root/.cubynode-github-token && test -r /root/cubynode-bootstrap.sh' >>"$LOG_FILE" 2>&1; then
  die "Le transfert du token GitHub vers le LXC $CTID a échoué. L'installation s'arrête AVANT le bootstrap. Le conteneur reste disponible pour diagnostic."
fi

# A positive size/readability check alone could still accept an incomplete
# transfer. Compare content without printing or logging the token itself.
HOST_TOKEN_HASH="$(sha256sum "$TMP_TOKEN" | awk '{print $1}')"
CT_TOKEN_HASH="$(pct exec "$CTID" -- sha256sum /root/.cubynode-github-token | awk '{print $1}')"
if [[ -z "$CT_TOKEN_HASH" || "$HOST_TOKEN_HASH" != "$CT_TOKEN_HASH" ]]; then
  unset HOST_TOKEN_HASH CT_TOKEN_HASH
  die "Le token GitHub n'a pas été copié intégralement dans le LXC $CTID."
fi
unset HOST_TOKEN_HASH CT_TOKEN_HASH

# Remove the token from the Proxmox host only after verifying the copy.
unset GITHUB_TOKEN
rm -f "$TMP_TOKEN" "$AUTH_FILE"
AUTH_FILE=""
TMP_TOKEN=""

progress 60 "Bootstrap privé vérifié"

# Keep bootstrap output separate from the earlier (successful) LXC boot trace.
# Both logs may contain operational details and remain root-readable only.
BOOTSTRAP_LOG="/var/log/cubynode-lxc-bootstrap-${CTID}.log"
install -o root -g root -m 0600 /dev/null "$BOOTSTRAP_LOG"
if ! pct exec "$CTID" -- env CUBYNODE_UPDATE_CHANNEL="$CHANNEL" bash /root/cubynode-bootstrap.sh >"$BOOTSTRAP_LOG" 2>&1; then
  # Read only bootstrap errors: old LXC first-boot debug lines are irrelevant
  # once the container has started and transferred the bootstrap script.
  BOOTSTRAP_ERROR="$(grep -iE '(^E:|error|failed|fatal|denied|could not|not found|unable|refused|unsupported|timed out|invalid)' "$BOOTSTRAP_LOG" | tail -n 8 || true)"
  [[ -n "$BOOTSTRAP_ERROR" ]] || BOOTSTRAP_ERROR="$(tail -n 12 "$BOOTSTRAP_LOG" || true)"
  [[ -n "$BOOTSTRAP_ERROR" ]] || BOOTSTRAP_ERROR="Le bootstrap a quitté avec une erreur sans message exploitable."

  ERROR_MESSAGE="Le conteneur LXC $CTID a bien démarré, mais l'installation de CubyNode a échoué.

$BOOTSTRAP_ERROR

Journal dédié : $BOOTSTRAP_LOG

Le conteneur est conservé pour diagnostic.
Vérifier : pct status $CTID"

  if $TUI; then
    whiptail --title "CubyNode • Échec du bootstrap" --scrolltext --msgbox "$ERROR_MESSAGE" 22 84
  else
    printf '\n%s✕ %s%s\n' "$RED" "$ERROR_MESSAGE" "$RESET" >&2
  fi
  exit 1
fi
# Credentials may appear at the end of successful bootstrap logs; never copy
# the complete bootstrap log to the installer log or a non-root-readable path.
progress 90 "CubyNode et PostgreSQL installés"

IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \\$1}'" 2>/dev/null | tr -d '\r')"
CREDENTIALS="$(pct exec "$CTID" -- cat /root/cubynode-credentials 2>/dev/null)"
progress 100 "Installation terminée"

SUCCESS="Installation terminée ✓

Panel
http://$IP:8080

CTID            $CTID
Hostname        $HOSTNAME
Disque          $ROOT_STORAGE • $DISK_GB Go
Template        $LXC_TEMPLATE
Git             Deploy Key read-only

$CREDENTIALS"

if $TUI; then
  whiptail --title "CubyNode • Prêt" --msgbox "$SUCCESS" 22 78
else
  banner
  printf '%s%s✓ Installation terminée%s\n\n%s\n' "$GREEN" "$BOLD" "$RESET" "$SUCCESS"
fi
