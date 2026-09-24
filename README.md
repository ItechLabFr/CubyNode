# CubyNode

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-light.svg">
    <img src="https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/assets/brand/logo-light.svg" alt="CubyNode" width="560">
  </picture>
</p>

<p align="center"><strong>Self-hosted Docker control plane for Minecraft servers and Discord bots.</strong><br><a href="https://cubynode.fr">cubynode.fr</a></p>

**Current version: `1.0.0-beta.1`**

CubyNode currently focuses on one runtime: **Docker Engine**.

It detects and controls real Docker containers for:

- Minecraft servers
- Discord bots

## Official Docker installation

Requirements:

- Linux host
- Docker Engine
- Docker Compose v2
- Git
- curl

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/docker-install.sh | sudo bash
```

Default installation directory:

```text
/opt/cubynode
```

The installer:

- clones the public CubyNode repository
- generates unique panel, agent and PostgreSQL secrets
- writes them to a local `.env` with mode `0600`
- builds the CubyNode API and agent images
- starts PostgreSQL, the agent and the panel
- prints the panel URL and access token

Default panel port:

```text
8080
```

Override it before installation:

```bash
curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/docker-install.sh | \
  sudo CUBYNODE_HTTP_PORT=9090 bash
```

## Docker update

Run on the Docker host:

```bash
sudo bash /opt/cubynode/scripts/docker-update.sh
```

This keeps the local `.env`, updates the source from the configured public branch, rebuilds the CubyNode containers and restarts the stack.

## Manual Docker Compose installation

```bash
git clone https://github.com/ItechLabFr/CubyNode.git
cd CubyNode
bash ./scripts/install.sh
```

## Managed Docker workloads

Only containers with this label are managed:

```text
cubynode.managed=true
```

Recommended labels:

```text
cubynode.kind=minecraft | discord_bot
cubynode.name=My server
cubynode.template=paper
```

Example:

```yaml
services:
  minecraft:
    image: eclipse-temurin:21-jre
    labels:
      cubynode.managed: "true"
      cubynode.kind: "minecraft"
      cubynode.name: "Survie"
```

CubyNode reads real state, resource usage, ports and logs directly from Docker Engine.

## Optional demo

The default installation starts **no fake workload**.

For development/testing only:

```bash
cd /opt/cubynode
docker compose --profile demo up -d
```

The demo is a real Docker container and is clearly labeled `cubynode.demo=true`.

## Multi-node

```env
CUBYNODE_AGENT_URLS=http://node-a:8081,http://node-b:8081
```

Each Docker agent needs a unique `CUBYNODE_NODE_ID`.

## Security

- the Docker socket is mounted only into the node agent
- the agent port is not published by the default Compose stack
- panel and agent tokens are separate
- runtime secrets are generated locally
- `.env` is ignored by Git
- CI scans tracked files and Git history for common secret formats
- CubyNode manages only explicitly labeled containers

## Development

Node.js 24+ and Docker Compose v2:

```bash
npm install
npm run check
npm test
npm run security:scan
```

Documentation:

- [Docker deployment](docs/docker.md)
- [Architecture](docs/architecture.md)
- [Beta 1 contract](docs/beta1.md)
- [Branding](docs/branding.md)
