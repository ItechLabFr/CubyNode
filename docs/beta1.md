# 1.0.0-beta.1 implementation contract

## Functional scope

### Control plane

- HTTP API + static panel
- bearer-token authentication
- PostgreSQL persistence
- multi-agent synchronization
- honest empty states

### Docker

- Docker Engine API through the local Unix socket
- managed workload discovery by `cubynode.managed=true`
- Minecraft and Discord bot workload labels
- status, CPU/RAM, mapped ports and logs
- start / stop / restart
- host CPU, memory and storage telemetry

Docker is the only supported execution backend in the current beta.

### Demo profile

The optional `demo` Compose profile contains one real Alpine container named `Demo Minecraft`.

It is **not started by the default production installation**.

To enable it explicitly:

```bash
docker compose --profile demo up -d
```

All demo status, logs and resource values still come from Docker Engine. The API does not fabricate workload rows.

### Security baseline

- separate panel and agent bearer tokens
- agent port is not published by the provided Compose file
- Docker socket is consumed only by the agent
- browser never accesses Docker directly
- `.env` contains host-generated secrets and is not committed
