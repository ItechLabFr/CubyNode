# Changelog

All notable changes to this project are documented here.

The project follows Semantic Versioning.

## [1.0.0-beta.1] - 2026-09-22

### Project start

- Established `1.0.0-beta.1` as the first official project version.
- Defined the product scope around Minecraft server hosting and Discord bot hosting only.
- Defined a runtime-agnostic architecture.
- Added Docker as a first-class execution backend.
- Added Incus/LXC as a first-class execution backend.
- Confirmed that Docker and LXC are independent runtimes; Docker is not required inside LXC workloads.
- Defined the initial control-plane, node-agent and scheduler architecture.
- Added the provisional runtime-neutral logo and branding direction.
