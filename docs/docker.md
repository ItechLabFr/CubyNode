# Docker deployment

Docker Engine is the official CubyNode deployment and workload runtime for the current beta.

## Requirements

- Linux
- Docker Engine
- Docker Compose v2
- Git
- curl

The Docker daemon must be running before CubyNode is installed.

## One-command installation

```bash
curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/docker-install.sh | sudo bash
```

Default directory:

```text
/opt/cubynode
```

Default panel port:

```text
8080
```

Custom port:

```bash
curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/docker-install.sh | \
  sudo CUBYNODE_HTTP_PORT=9090 bash
```

## Services

The production Compose stack contains:

- `postgres` — persistent PostgreSQL database
- `agent` — node telemetry and Docker Engine integration
- `api` — HTTP API and web panel

The agent receives the local Docker Unix socket:

```text
/var/run/docker.sock
```

The socket is not published over TCP.

The agent HTTP port is internal to the Compose network by default.

## Secrets

The installer creates:

```text
/opt/cubynode/.env
```

with mode `0600`.

It contains:

- PostgreSQL password
- panel token
- agent token
- node identity
- panel port

Do not commit or share this file.

## Status

```bash
cd /opt/cubynode
docker compose ps
```

Health endpoint:

```bash
curl -fsS http://127.0.0.1:8080/api/health
```

Logs:

```bash
cd /opt/cubynode
docker compose logs -f --tail=200
```

## Update

```bash
sudo bash /opt/cubynode/scripts/docker-update.sh
```

The update workflow:

1. fetches the configured public Git branch
2. updates the tracked CubyNode source
3. preserves `.env`
4. rebuilds the API and agent images
5. refreshes PostgreSQL image metadata
6. recreates the running stack without deleting the PostgreSQL volume

## Managed workloads

CubyNode only discovers containers carrying:

```text
cubynode.managed=true
```

Recommended metadata:

```text
cubynode.kind=minecraft
cubynode.name=Survie
cubynode.template=paper
```

or:

```text
cubynode.kind=discord_bot
cubynode.name=Moderation
cubynode.template=nodejs
```

Example:

```yaml
services:
  minecraft:
    image: eclipse-temurin:21-jre
    restart: unless-stopped
    labels:
      cubynode.managed: "true"
      cubynode.kind: "minecraft"
      cubynode.name: "Survie"
      cubynode.template: "paper"
```

## Optional demo

The demo workload is disabled by default.

Enable it only for testing:

```bash
cd /opt/cubynode
docker compose --profile demo up -d
```

Disable it again:

```bash
cd /opt/cubynode
docker compose --profile demo stop demo-minecraft
docker compose rm -f demo-minecraft
```

## Data persistence

PostgreSQL data is stored in the named volume:

```text
cubynode-postgres
```

Do not use `docker compose down -v` unless you intentionally want to delete the database.

## Uninstall

Stop the stack without deleting database data:

```bash
cd /opt/cubynode
docker compose down
```

To remove CubyNode completely, back up anything you need first, then remove the repository and its Docker volume manually.

## Security notes

Access to the Docker socket is effectively privileged access to the Docker host.

For this reason:

- only the CubyNode agent receives the socket
- the browser never receives Docker access
- the API container does not receive the Docker socket
- the agent API is not published by the default Compose stack
- only explicitly labeled containers are managed
