# Architecture

## Current scope

CubyNode currently targets two workload families:

- Minecraft servers
- Discord bots

**Docker Engine is the only execution backend supported by the current beta.**

## Components

### Web Panel

Responsibilities:

- authentication
- workload overview
- console and logs
- resource graphs
- node status
- administrative information

The browser never talks directly to the Docker socket.

### Control Plane API

The API is the authoritative application layer.

Responsibilities:

- workload and node state
- PostgreSQL history
- agent synchronization
- lifecycle requests
- activity events
- authentication

### Node Agent

The agent runs in Docker on every managed node.

Responsibilities:

- report node CPU, memory and storage
- detect CubyNode-managed Docker containers
- read Docker stats and logs
- start, stop and restart managed containers

The Docker Unix socket is mounted only into the agent container. It is not exposed over the network.

## Docker runtime

CubyNode communicates with Docker Engine through the local versioned Engine API.

Current mapping:

- workload -> Docker container
- status -> Docker container state
- CPU/RAM -> Docker stats API
- ports -> Docker port mappings
- logs -> Docker logs API
- lifecycle -> Docker start / stop / restart API
- discovery -> Docker labels

Managed containers use these labels:

```text
cubynode.managed=true
cubynode.kind=minecraft | discord_bot
cubynode.name=...
```

Optional labels:

```text
cubynode.template=...
cubynode.demo=true
```

## Multi-node

The control plane can synchronize several Docker agents:

```env
CUBYNODE_AGENT_URLS=http://node-a:8081,http://node-b:8081
```

Each agent must use a unique `CUBYNODE_NODE_ID`.

## Security baseline

- no public Docker socket
- separate panel and agent bearer tokens
- runtime secrets generated on the host
- browser never receives the agent token
- only containers explicitly labeled `cubynode.managed=true` are managed
- activity is persisted in PostgreSQL
- no fabricated runtime statistics

## Implementation order

1. Docker installation and update flow
2. Docker node registration and metrics
3. Docker workload discovery
4. lifecycle and logs
5. Minecraft templates
6. Discord bot templates
7. workload creation
8. file manager
9. backups and schedules
10. permissions and audit log
11. multi-node scheduling
