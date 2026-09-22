# CubyNode

> **Working title** — the final product name is intentionally not fixed yet.

CubyNode is a self-hosted control plane focused on exactly two workloads:

- **Minecraft servers**
- **Discord bots**

The platform is designed to run workloads through two execution backends:

- **Docker Engine** for application containers
- **LXC system containers through Incus** for stronger system-container isolation and flexible node layouts

## Product principles

1. **Minecraft + Discord only** — no generic VPS/cloud catalog in the user experience.
2. **Runtime-agnostic core** — Docker and Incus are implementation backends behind one internal runtime interface.
3. **Multi-node from day one** — one control plane, multiple execution nodes.
4. **Secure by default** — secrets never returned in clear text after creation, scoped permissions, audit log and encrypted node communication.
5. **Simple deployment** — the user chooses a template and resources; the platform handles runtime-specific details.

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

## Status

**Pre-alpha / architecture phase.**

The repository is currently the source of truth for the platform design and implementation decisions.
