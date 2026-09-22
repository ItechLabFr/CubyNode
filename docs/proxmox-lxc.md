# Proxmox VE LXC installation

CubyNode can run natively inside a Proxmox VE LXC. Docker is **not** required inside this control-plane LXC.

## One-line install

Execute on the Proxmox VE host as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

## What the installer asks

The normal interactive flow only asks for infrastructure choices that cannot be safely guessed:

1. **Template storage** — a Proxmox storage supporting `vztmpl`.
2. **LXC root-disk storage** — a Proxmox storage supporting `rootdir`.
3. **Disk size** — default: 20 GB.

When only one compatible storage exists, it is selected automatically.

The OS template is selected automatically. The preferred template is the newest available **Debian 13 standard** template. A supported Debian/Ubuntu fallback is used only if Debian 13 is unavailable.

## Automatic defaults

- CTID: next Proxmox cluster ID
- hostname: `cubynode-<CTID>`
- CPU: 2 cores
- RAM: 2048 MB
- swap: 512 MB
- networking: first `vmbr*` bridge + DHCP
- unprivileged container: enabled
- start at boot: enabled

## Installation inside the LXC

The bootstrap installs:

- ca-certificates
- curl
- git
- sudo
- PostgreSQL
- Python 3 (used by the root update helper)
- Node.js 24
- CubyNode from `ItechLabFr/CubyNode`

CubyNode is stored in:

```text
/opt/cubynode
```

Configuration is stored in:

```text
/etc/cubynode/cubynode.env
```

Credentials are stored root-only in:

```text
/root/cubynode-credentials
```

The services are:

```text
cubynode-agent.service
cubynode-api.service
```

## Non-interactive overrides

Automation can set:

```bash
CUBYNODE_TEMPLATE_STORAGE=local
CUBYNODE_ROOTFS_STORAGE=local-lvm
CUBYNODE_DISK_GB=30
CUBYNODE_LXC_TEMPLATE=debian-13-standard_..._amd64.tar.zst
bash ./scripts/proxmox-lxc-install.sh
```

`CUBYNODE_LXC_TEMPLATE` is optional; normally the installer automatically chooses the newest Debian 13 template.

## Updates from the admin panel

Open **Admin → Mises à jour**.

The panel reads the real local Git commit and compares it to the configured GitHub branch.

### Simple

```text
git fetch/reset
→ npm production dependencies
→ validation
→ services restart
```

### Complete

```text
Debian package upgrade
→ git fetch/reset
→ npm production dependencies
→ systemd/updater refresh
→ validation
→ services restart
```

The actual update is not executed directly by the Node.js API as root. The API can only invoke:

```text
/usr/local/sbin/cubynode-update-request simple
/usr/local/sbin/cubynode-update-request full
```

through explicit sudo rules. That helper starts a transient root systemd unit.

Update state:

```text
/var/lib/cubynode/update-status.json
```

Update log:

```text
/var/log/cubynode/update.log
```

If an application update fails after switching commits, the updater attempts to reset CubyNode to the previous Git commit and restart the services.

A complete Debian package upgrade cannot fully roll back OS packages automatically.

## Manual service diagnostics

```bash
systemctl status cubynode-api cubynode-agent
journalctl -u cubynode-api -u cubynode-agent --since today
cat /var/log/cubynode/update.log
```

## Security notes

- The LXC is unprivileged.
- CubyNode API runs as the `cubynode` system user.
- PostgreSQL listens locally by default.
- The update helper is root-owned and validates the update mode.
- No Docker socket is required for the control-plane LXC.
