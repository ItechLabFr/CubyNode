# CubyNode

> **Working title** — the final product name is intentionally not fixed yet.

**Current version: `1.0.0-beta.1`**

CubyNode is a self-hosted control plane dedicated to:

- Minecraft servers
- Discord bots

Execution backends remain independent:

- Docker Engine
- LXC/Incus

The control plane itself can now be installed **natively in a Proxmox VE LXC without Docker**.

## Automatic Proxmox LXC installation

The repository is currently private. Use a temporary **fine-grained GitHub PAT** restricted to `ItechLabFr/CubyNode` with:

- **Contents: Read-only**
- **Administration: Read and write** (only needed so the installer can register the permanent read-only Deploy Key)

Run as `root` on the Proxmox VE host:

```bash
read -r -s -p "GitHub token: " TOKEN; echo
TOKEN_FILE="$(mktemp /tmp/cubynode-token.XXXXXX)"
AUTH_FILE="$(mktemp /tmp/cubynode-auth.XXXXXX)"
chmod 600 "$TOKEN_FILE" "$AUTH_FILE"
printf '%s' "$TOKEN" >"$TOKEN_FILE"
printf 'Authorization: Bearer %s\n' "$TOKEN" >"$AUTH_FILE"
unset TOKEN

CUBYNODE_GITHUB_TOKEN_FILE="$TOKEN_FILE" \
bash <(curl -fsSL \
  -H @"$AUTH_FILE" \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "https://api.github.com/repos/ItechLabFr/CubyNode/contents/scripts/proxmox-lxc-install.sh?ref=main")

rm -f "$TOKEN_FILE" "$AUTH_FILE"
```

The PAT is used only for the initial private-repository bootstrap. The installer generates an **Ed25519 read-only Deploy Key**, registers it on GitHub, switches the repository remote to SSH, then deletes the temporary PAT from the LXC. Future panel updates use only the Deploy Key.

The installer automatically handles:

- next available CTID
- hostname
- unprivileged LXC
- bridge / DHCP networking
- 2 vCPU
- 2 GB RAM
- 512 MB swap
- latest Debian 13 standard template by default
- template download
- Node.js 24
- PostgreSQL
- authenticated clone from the private GitHub repository
- dedicated read-only GitHub Deploy Key for future updates
- systemd services
- panel + agent tokens
- startup on boot
- native updater

The only interactive choices are:

1. template storage
2. LXC root-disk storage
3. LXC disk size

If only one compatible storage exists, it is selected automatically.

The final URL and panel token are printed at the end and stored inside the LXC at:

```text
/root/cubynode-credentials
```

See [docs/proxmox-lxc.md](docs/proxmox-lxc.md).

## Admin updates

Native LXC installations expose update controls in **Admin → Mises à jour**.

### Simple update

- fetch the configured GitHub channel
- update the CubyNode source tree
- install production npm dependencies
- run syntax/check validation
- restart the CubyNode agent and API
- rollback the application tree if the update fails

### Complete update

Includes the simple update plus:

- `apt update`
- Debian distribution package upgrade
- required package refresh
- systemd service refresh
- updater helper refresh

If Debian reports that a reboot is required, the panel records that state; the installer does not reboot the LXC automatically.

The updater runs as a transient root systemd unit. The web API itself does not receive an unrestricted root shell.

## Data policy

CubyNode does not seed fake dashboard statistics.

Every node, workload, state, CPU/RAM/storage value, log and activity item displayed by the panel comes from a runtime/agent observation or from PostgreSQL history built from those observations.

The Docker Compose development setup contains one intentional demo workload named `Demo Minecraft`. It is a real Docker container and is the only synthetic workload shipped with beta.1.

## Docker Compose development install

For development/testing on a Docker host:

```bash
git clone https://github.com/ItechLabFr/CubyNode.git
cd CubyNode
cp .env.example .env
# replace placeholder secrets
docker compose up -d --build
```

## Managed workloads

Docker labels:

```text
cubynode.managed=true
cubynode.kind=minecraft | discord_bot
cubynode.name=...
```

Incus instance config:

```text
user.cubynode.managed=true
user.cubynode.kind=minecraft | discord_bot
user.cubynode.name=...
```

## Multi-node

```env
CUBYNODE_AGENT_URLS=http://node-a:8081,http://node-b:8081
```

Each agent needs a unique `CUBYNODE_NODE_ID`.

## Development

Node.js 24+:

```bash
npm install
npm run check
npm test
```

Documentation:

- [Architecture](docs/architecture.md)
- [Beta 1 contract](docs/beta1.md)
- [Proxmox LXC installation](docs/proxmox-lxc.md)
- [Branding](docs/branding.md)
