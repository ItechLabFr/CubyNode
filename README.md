# CubyNode

> **Working title** — the final product name is intentionally not fixed yet.

**Current version: `1.0.0-beta.1`**

CubyNode is a self-hosted control plane focused on exactly two workloads:

- **Minecraft servers**
- **Discord bots**

The platform is designed to run workloads through two execution backends:

- **Docker Engine** for application containers
- **LXC system containers through Incus** as a standalone runtime — Docker is not required inside an LXC workload

## Product principles

1. **Minecraft + Discord only** — no generic VPS/cloud catalog in the user experience.
2. **Runtime-agnostic core** — Docker and Incus are independent implementation backends behind one internal runtime interface.
3. **One runtime per workload** — an instance runs either with Docker or with Incus/LXC; nesting Docker inside LXC is not part of the default architecture.
4. **Multi-node from day one** — one control plane, multiple execution nodes.
5. **Secure by default** — secrets never returned in clear text after creation, scoped permissions, audit log and encrypted node communication.
6. **Simple deployment** — the user chooses a template and resources; the platform handles runtime-specific details.

## High-level architecture

```text
                    Web Panel
                        │
                        ▼
                 Control Plane API
              ┌─────────┴─────────┐
              │                   │
         PostgreSQL            Redis
              │
              ▼
         Node Scheduler
              │
       ┌──────┴──────┐
       │             │
       ▼             ▼
   Node Agent     Node Agent
       │             │
  ┌────┴────┐   ┌────┴────┐
  │ Docker  │   │  Incus  │
  │ Driver  │   │ Driver  │
  └────┬────┘   └────┬────┘
       │             │
 Minecraft/Bots  Minecraft/Bots
```

See [docs/architecture.md](docs/architecture.md) for the technical design.

## Versioning

The project starts at **`1.0.0-beta.1`**.

Pre-release progression:

```text
1.0.0-beta.1
1.0.0-beta.2
...
1.0.0-rc.1
...
1.0.0
```

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Status

**1.0.0-beta.1 — initial implementation phase.**

The repository is the source of truth for platform design, architecture and implementation decisions.
