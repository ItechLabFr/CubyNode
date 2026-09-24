# Proxmox VE LXC installation

CubyNode can run natively inside a Proxmox VE LXC. Docker is **not** required inside this control-plane LXC.

The repository is public, so installation and updates use public HTTPS Git access. **No GitHub token, PAT or Deploy Key is required.**

## Install

Run on the Proxmox VE host as `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

The installer validates that the public repository is reachable before creating anything.

## Interactive choices

The normal flow asks only for infrastructure choices that cannot be safely guessed:

1. **Template storage** — Proxmox storage supporting `vztmpl`.
2. **LXC root-disk storage** — Proxmox storage supporting `rootdir`.
3. **Disk size** — default: 20 GB.

When only one compatible storage exists, it is selected automatically.

## Automatic defaults

- CTID: next Proxmox cluster ID
- hostname: `cubynode-<CTID>`
- CPU: 2 cores
- RAM: 2048 MB
- swap: 512 MB
- bridge: first available `vmbr*`
- VLAN: **10**
- IPv4: DHCP
- unprivileged container: enabled
- nesting: enabled before first boot
- start at boot: enabled
- preferred OS: newest compatible Debian 13 standard template

The installer reads the Proxmox host architecture with `dpkg --print-architecture` and only accepts matching templates.

## VLAN

The default network configuration is:

```text
net0: name=eth0,bridge=vmbr0,tag=10,ip=dhcp,type=veth
```

The actual bridge is the first detected `vmbr*`.

Override the VLAN without editing the script:

```bash
CUBYNODE_VLAN_TAG=20 bash <(curl -fsSL https://raw.githubusercontent.com/ItechLabFr/CubyNode/main/scripts/proxmox-lxc-install.sh)
```

The VLAN must be between 1 and 4094.

The selected bridge, physical switch/trunk and upstream router must carry that VLAN. The VLAN must provide working DHCP, routing and DNS.

## Non-interactive overrides

Automation can set:

```bash
CUBYNODE_TEMPLATE_STORAGE=local \
CUBYNODE_ROOTFS_STORAGE=local-lvm \
CUBYNODE_DISK_GB=30 \
CUBYNODE_VLAN_TAG=10 \
bash ./scripts/proxmox-lxc-install.sh
```

The optional template override is:

```bash
CUBYNODE_LXC_TEMPLATE=debian-13-standard_..._amd64.tar.zst
```

A wrong-architecture override is rejected before the CT is created.

## Installation inside the LXC

The bootstrap installs:

- ca-certificates
- curl
- git
- sudo
- PostgreSQL
- Python 3
- util-linux
- Node.js 24
- CubyNode from the public GitHub repository

CubyNode is cloned over HTTPS into:

```text
/opt/cubynode
```

The persistent Git remote is:

```text
https://github.com/ItechLabFr/CubyNode.git
```

No Git credential is written to disk.

Configuration is stored in:

```text
/etc/cubynode/cubynode.env
```

The file is owned by `root:cubynode` with mode `0640`.

The generated panel credential is stored root-only in:

```text
/root/cubynode-credentials
```

with mode `0600`.

The services are:

```text
cubynode-agent.service
cubynode-api.service
```

## DNS and network preflight

Before transferring and running the bootstrap, the Proxmox installer checks DNS resolution inside the CT for:

- `deb.debian.org`
- `security.debian.org`
- `deb.nodesource.com`
- `github.com`

The bootstrap performs its own DNS check again and uses APT retries.

A failure such as:

```text
Temporary failure resolving 'deb.debian.org'
```

means the CT has a network/DNS problem, not a GitHub authentication problem.

Keep the CT and inspect:

```bash
pct status <CTID>
pct exec <CTID> -- ip -4 addr show dev eth0
pct exec <CTID> -- ip -4 route
pct exec <CTID> -- cat /etc/resolv.conf
pct exec <CTID> -- getent ahostsv4 deb.debian.org
```

If the CT has an IPv4 address and default route but DNS lookup fails, set a DNS server reachable from that VLAN. Example only:

```bash
pct set <CTID> --nameserver 1.1.1.1
pct reboot <CTID>
pct exec <CTID> -- getent ahostsv4 deb.debian.org
```

Use the local router/internal DNS instead when public DNS is blocked.

## systemd 257 / nesting

Modern Debian LXC templates need namespace support expected by systemd. CubyNode creates the CT with:

```text
features: nesting=1
```

**before the first boot**.

For an existing CT created without it:

```bash
pct set <CTID> --features nesting=1
pct start <CTID>
```

CubyNode does not enable `keyctl=1` because Docker is not required inside the control-plane LXC.

## Native LXC architecture

Native LXC executes userspace with the host kernel. The container root filesystem must therefore match the Proxmox host architecture.

The installer supports automatic selection for:

- `amd64`
- `arm64`

A mismatch typically fails with:

```text
Exec format error - Failed to exec "/sbin/init"
```

Changing only the `arch:` value in the CT configuration does not convert an incompatible root filesystem.

## First-boot diagnostics

The installer starts the newly created CT with Proxmox debug output captured in:

```text
/var/log/cubynode-lxc-start-<CTID>.log
```

If the first boot fails, the CT is preserved.

Useful commands:

```bash
pct config <CTID>
pct start <CTID> --debug
pveversion -v
journalctl -u pve-container@<CTID>.service --no-pager -n 100
```

A generic `sync_wait` message is not enough to determine the root cause; inspect the preceding debug error.

## Bootstrap diagnostics

If the CT starts but application installation fails, the container is preserved.

The host keeps the root-only bootstrap log at:

```text
/var/log/cubynode-lxc-bootstrap-<CTID>.log
```

Check:

```bash
pct status <CTID>
tail -n 100 /var/log/cubynode-lxc-bootstrap-<CTID>.log
```

The successful bootstrap prints credentials at the end, so bootstrap logs must remain root-readable and should be redacted before sharing.

## Admin updates

Open **Admin → Mises à jour**.

The panel reads the real local Git commit and compares it with the configured public branch.

### Simple

```text
git fetch/reset
→ npm production dependencies
→ validation
→ services restart
```

If switching commits fails later in the process, the updater attempts to return the application tree to the previous commit.

### Complete

```text
Debian package upgrade
→ git fetch/reset
→ npm production dependencies
→ updater/systemd refresh
→ validation
→ services restart
```

The API does not receive an unrestricted root shell. It can invoke only:

```text
/usr/local/sbin/cubynode-update-request simple
/usr/local/sbin/cubynode-update-request full
```

through explicit sudo rules.

Update state:

```text
/var/lib/cubynode/update-status.json
```

Update log:

```text
/var/log/cubynode/update.log
```

A Debian package upgrade itself cannot be fully rolled back automatically.

## Manual service diagnostics

```bash
systemctl status cubynode-api cubynode-agent
journalctl -u cubynode-api -u cubynode-agent --since today
cat /var/log/cubynode/update.log
```

## Security notes

- The LXC is unprivileged.
- `nesting=1` is enabled only for the systemd/LXC requirement.
- CubyNode API runs as the `cubynode` system user.
- PostgreSQL listens locally by default.
- Panel/agent/database secrets are generated on the target LXC.
- GitHub credentials are not required or stored.
- The update helper is root-owned and validates the requested mode.
- No Docker socket is required by the control-plane LXC itself.
- CI scans tracked content for common secret formats and unexpected personal e-mail addresses.
