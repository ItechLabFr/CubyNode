# Changelog

All notable changes to CubyNode are documented here.

The project follows Semantic Versioning.

## [Unreleased]

### Docker-first beta

- Made Docker Engine the only supported execution backend in the current beta.
- Added a one-command public Docker installation flow.
- Added a host-side Docker update script.
- Made the demo workload opt-in through the `demo` Compose profile.
- Removed non-Docker runtime code, installers, services, tests and documentation from the current tree.
- Removed the in-panel native self-updater; Docker deployment updates are executed explicitly on the host.
- Added a CI guard that keeps the current project tree Docker-only.
- Kept real Docker Engine status, metrics, logs and lifecycle operations as the source of workload data.

### Official CubyNode brand

- Confirmed CubyNode as the official product name and `cubynode.fr` as the official domain.
- Added official light and dark vector logo/icon variants.
- Added Apple touch, Android launcher, favicon and PWA icon assets.
- Added installable PWA metadata and a conservative service worker that excludes API traffic.
- Switched the panel brand icon automatically with the active light/dark theme.
- Fixed README logo rendering on GitHub mobile.

### Public repository hardening

- Switched installation and updates to public HTTPS Git access.
- Added a CI security scan for common committed secret formats and unexpected personal e-mail addresses.
- Hardened ignored local secret/key file patterns.

## [1.0.0-beta.1] - 2026-09-22

### Project start

- Established `1.0.0-beta.1` as the first official project version.
- Defined the product scope around Minecraft server hosting and Discord bot hosting.
- Added Docker Engine as the initial execution backend.
- Added the control-plane API, PostgreSQL persistence and node agent.
- Added real Docker workload discovery through labels.
- Added Docker status, CPU/RAM, mapped ports, logs and start/stop/restart actions.
- Added the initial self-hosted panel and multi-node synchronization model.
