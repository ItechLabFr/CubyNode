# 1.0.0-beta.1 implementation contract

## Functional scope

### Control plane
- HTTP API + static panel
- bearer-token authentication
- PostgreSQL persistence
- multi-agent synchronization
- honest empty states

### Docker
- Engine API through Unix socket
- managed workload discovery by label
- status, CPU/RAM, mapped ports, logs
- start / stop / restart

### Incus/LXC
- Incus REST API through Unix socket
- managed instance discovery via `user.cubynode.managed=true`
- status + memory usage
- start / stop / restart
- no Docker dependency inside LXC

Incus application-log streaming is not implemented in beta.1: the API returns 501 instead of fabricating output.

### Demo
`demo-minecraft` is the only demo workload. It is a real Alpine Docker container with CubyNode labels and heartbeat logs. It exercises lifecycle, metrics and logs without inserting fake rows into the API/database.

### Security baseline
- separate panel and agent bearer tokens
- agent port is not published by the provided Compose file
- runtime sockets are only consumed by the agent
- browser never accesses Docker/Incus directly
