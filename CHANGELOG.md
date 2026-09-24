# Changelog

All notable changes to this project are documented here.

The project follows Semantic Versioning.

## [Unreleased]

### Public repository hardening

- Switched Proxmox installation and updates to public HTTPS Git access.
- Removed the temporary GitHub PAT, private-clone helper and read-only Deploy Key lifecycle.
- Simplified the Proxmox installer to a token-free public bootstrap.
- Kept VLAN 10 + DHCP as the default LXC network.
- Added Debian/NodeSource/GitHub DNS preflight and APT retries.
- Added a CI security scan for common committed secret formats and unexpected personal e-mail addresses.
- Hardened ignored local secret/key file patterns.
- Set the native LXC bootstrap locale to `C.UTF-8` before PostgreSQL installation.

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
- Added automatic native Proxmox VE LXC installation from GitHub.
- Added a native LXC bootstrap with Node.js 24, PostgreSQL and systemd services.
- Added admin-panel simple and complete update flows.
- Added application rollback for failed native code updates.
- Added private GitHub bootstrap using a temporary fine-grained PAT and persistent read-only Deploy Key.
