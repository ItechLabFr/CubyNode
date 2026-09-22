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

Run this as `root` on the Proxmox VE host:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

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
- CubyNode clone from GitHub
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
