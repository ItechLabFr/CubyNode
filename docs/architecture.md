# Architecture

## Scope

The platform manages only two product families:

- Minecraft servers
- Discord bots

A workload can be deployed on a compatible node using either Docker or Incus/LXC according to the selected template and node capabilities.

## Components

### 1. Web Panel

Responsibilities:

- authentication and account management
- server/bot creation wizard
- console and logs
- file manager
- backups
- schedules
- environment variables and secrets
- resource graphs
- sub-users and permissions
- administrative node management

The panel must never talk directly to Docker or Incus.

### 2. Control Plane API

The API is the authoritative application layer.

Responsibilities:

- users, teams and permissions
- workload state
- templates
- scheduling and placement
- quotas
- audit events
- backup metadata
- secret references
- node registration and health

### 3. Node Agent

A small agent runs on every execution node.

Responsibilities:

- register node capabilities
- report CPU, memory, disk and network usage
- receive signed workload operations
- stream console/log events
- execute runtime operations through a runtime driver
- manage local files and backup streams

The control plane communicates with the agent; the control plane does not expose Docker or Incus sockets over the public network.

## Runtime abstraction

The core must expose one internal contract, for example:

```text
RuntimeDriver
├── Capabilities()
├── CreateInstance(spec)
├── Start(id)
├── Stop(id)
├── Restart(id)
├── Delete(id)
├── Inspect(id)
├── Stats(id)
├── Logs(id)
├── Exec(id, command)
├── Upload(id, path, stream)
├── Download(id, path)
├── Snapshot(id)
└── Restore(id, snapshot)
```

### Docker driver

The Docker backend communicates with Docker Engine through its versioned Engine API.

Primary mapping:

- workload -> Docker container
- persistent data -> volumes/bind mounts
- allocations -> Docker networks/port bindings
- CPU/RAM/PIDs -> container resource limits
- logs/console -> attach/log streams
- templates -> image + environment + mounts + startup configuration

### Incus / LXC driver

LXC support is implemented through **Incus** rather than by shelling out to raw LXC commands.

Primary mapping:

- workload -> Incus system container
- persistent data -> storage volumes
- allocations -> proxy/network devices
- CPU/RAM -> Incus limits
- console -> Incus console/exec APIs
- metrics/events -> Incus API streams
- templates -> image + profile + cloud-init/startup configuration

This gives the project a stable remote API, authentication, events and resource reporting while workloads still run as LXC system containers.

## Workload model

```text
Workload
├── id
├── kind                 minecraft | discord_bot
├── runtime              docker | incus
├── template_id
├── node_id
├── state
├── resources
│   ├── cpu
│   ├── memory
│   ├── disk
│   └── pids
├── networking
├── mounts
├── startup
├── environment
└── secret_refs
```

The UI should not expose backend-specific complexity unless an administrator explicitly enables advanced settings.

## Template model

Templates declare which runtimes they support.

Examples:

```yaml
id: minecraft-paper
kind: minecraft
runtimes:
  - docker
  - incus
resources:
  memory_min: 1024
startup:
  command: java -Xms128M -Xmx{{memory}}M -jar server.jar nogui
```

Discord templates can follow the same model for Node.js, Python, Java and Bun.

## Suggested node capabilities

Every agent reports a capability document:

```json
{
  "runtimes": ["docker", "incus"],
  "architectures": ["amd64"],
  "cpu_threads": 16,
  "memory_bytes": 68719476736,
  "storage": {
    "default": {
      "free_bytes": 800000000000
    }
  }
}
```

The scheduler only places workloads on nodes satisfying the template and resource requirements.

## Security baseline

- mutually authenticated control-plane/agent connection
- no public Docker socket
- no public Incus Unix socket
- short-lived operation credentials
- encrypted secrets at rest
- secrets redacted from logs
- per-workload filesystem boundaries
- resource limits mandatory
- audit log for administrative operations
- configurable unprivileged Incus containers by default
- administrator-only access to privileged modes

## Initial implementation order

1. Core API + authentication
2. Node registration and heartbeat
3. Runtime driver interface
4. Docker driver
5. Workload lifecycle
6. Live console/log streaming
7. Minecraft Paper template
8. Discord Node.js template
9. Incus/LXC driver
10. File manager, backups and schedules
11. Permissions and audit log
12. Multi-node scheduler
