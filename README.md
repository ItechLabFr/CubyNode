# CubyNode

> **Working title** — the final product name is intentionally not fixed yet.

**Current version: `1.0.0-beta.1`**

CubyNode is a self-hosted control plane focused on exactly two workload families:

- Minecraft servers
- Discord bots

It supports two independent execution backends:

- **Docker Engine**
- **Incus/LXC** (Docker is not required inside LXC)

## beta.1 status

The beta.1 implementation provides a functional vertical slice:

- responsive light/dark dashboard
- token-protected control-plane API
- PostgreSQL persistence
- multi-node agent synchronization
- real host CPU/RAM/storage telemetry
- Docker discovery/stats/logs/start/stop/restart
- Incus/LXC discovery/state/start/stop/restart
- real activity log from observed runtime changes
- one real Docker demo workload
- no synthetic dashboard values

### Data policy

The only intentionally synthetic workload shipped with beta.1 is **Demo Minecraft** in `compose.yaml`.

Every value displayed by the UI comes from the agent/runtime or from PostgreSQL history built from those observations. When data does not exist, the UI displays an empty or collecting state.

## Quick start

Requirements: Linux, Docker Engine, Docker Compose v2.

```bash
git clone https://github.com/ItechLabFr/CubyNode.git
cd CubyNode
cp .env.example .env
# Replace all placeholder secrets
docker compose up -d --build
```

Or:

```bash
./scripts/install.sh
```

Open `http://HOST:8080` and enter `CUBYNODE_PANEL_TOKEN`.

## Runtime ownership

Docker workloads must carry:

```text
cubynode.managed=true
cubynode.kind=minecraft | discord_bot
cubynode.name=...
```

Incus/LXC instances use:

```text
user.cubynode.managed=true
user.cubynode.kind=minecraft | discord_bot
user.cubynode.name=...
```

## Incus/LXC

Incus is an independent runtime. Docker is not required in the LXC instance.

Mount the Incus Unix socket into the agent and set:

```env
CUBYNODE_INCUS_SOCKET=/var/lib/incus/unix.socket
```

## Multi-node

```env
CUBYNODE_AGENT_URLS=http://node-a:8081,http://node-b:8081
```

Each agent needs a unique `CUBYNODE_NODE_ID`.

## Development

```bash
npm install
npm run check
npm test
```

See [docs/architecture.md](docs/architecture.md) and [docs/beta1.md](docs/beta1.md).
