# CubyNode

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-light.svg">
    <img src="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-light.svg" alt="CubyNode" width="560">
  </picture>
</p>

<p align="center"><strong>Self-hosted control plane for Minecraft servers and Discord bots.</strong><br><a href="https://cubynode.fr">cubynode.fr</a></p>

**Current version: `1.0.0-beta.1`**

CubyNode is a self-hosted control plane for:

- Minecraft servers
- Discord bots

Runtime backends remain independent:

- Docker Engine
- LXC/Incus

The control plane itself can be installed **natively in a Proxmox VE LXC without Docker**.

## Proxmox LXC installation

The repository is public. **No GitHub token, PAT or Deploy Key is required.**

Run as `root` on the Proxmox VE host:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

The installer automatically handles:

- next available CTID
- hostname
- unprivileged LXC
- `nesting=1` before first boot
- VLAN 10 on the selected Proxmox bridge
- DHCP networking
- 2 vCPU
- 2 GB RAM
- 512 MB swap
- latest compatible Debian 13 standard template
- host/template architecture matching
- template download
- DNS preflight for Debian, NodeSource and GitHub
- Node.js 24
- PostgreSQL
- public HTTPS clone from GitHub
- systemd services
- panel + agent tokens generated locally
- startup on boot
- native updater

The interactive choices are:

1. template storage
2. LXC root-disk storage
3. LXC disk size

If only one compatible storage exists, it is selected automatically.

The default network is:

```text
bridge: first vmbr* bridge
VLAN:   10
IPv4:   DHCP
```

Override the VLAN when needed:

```bash
CUBYNODE_VLAN_TAG=20 bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

The final URL and panel token are printed at the end and stored root-only inside the LXC:

```text
/root/cubynode-credentials
```

See [docs/proxmox-lxc.md](docs/proxmox-lxc.md).

## Admin updates

Native LXC installations expose update controls in **Admin → Mises à jour**.

### Simple update

- fetch the configured public GitHub channel
- update the CubyNode source tree
- install production npm dependencies
- run validation
- restart the CubyNode agent and API
- roll back the application tree if the update fails

### Complete update

Includes the simple update plus:

- Debian package update
- required package refresh
- systemd service refresh
- updater helper refresh

The updater runs as a transient root systemd unit. The web API itself does not receive an unrestricted root shell.

## Data policy

CubyNode does not seed fake dashboard statistics.

Every node, workload, state, CPU/RAM/storage value, log and activity item displayed by the panel comes from a runtime/agent observation or PostgreSQL history built from those observations.

The Docker Compose development setup contains one intentional demo workload named `Demo Minecraft`. It is a real Docker container and is the only synthetic workload shipped with beta.1.

## Docker Compose development install

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

## Security

- No GitHub credential is needed for installation or updates.
- Runtime secrets are generated on the target system and are not committed to this repository.
- `.env` is ignored; only `.env.example` with placeholders is tracked.
- The panel credential file is mode `0600` and stored at `/root/cubynode-credentials`.
- CI runs `scripts/security-scan.sh` to reject common committed secret formats and unexpected personal e-mail addresses.

## Development

Node.js 24+:

```bash
npm install
npm run check
npm test
npm run security:scan
```

Documentation:

- [Architecture](docs/architecture.md)
- [Beta 1 contract](docs/beta1.md)
- [Proxmox LXC installation](docs/proxmox-lxc.md)
- [Branding](docs/branding.md)
