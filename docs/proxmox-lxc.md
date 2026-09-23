# Proxmox VE LXC installation

CubyNode can run natively inside a Proxmox VE LXC. Docker is **not** required inside this control-plane LXC.

## Private-repository install

While `ItechLabFr/CubyNode` is private, the installer needs a temporary fine-grained PAT for the initial bootstrap.

Repository access:

- selected repository: `ItechLabFr/CubyNode`
- Contents: Read-only
- Administration: Read and write

The Administration permission is used only to register a **read-only Deploy Key** through GitHub's repository deploy-key API. After that, the PAT is removed from the LXC.

Execute on the Proxmox VE host as root:

```bash
read -r -s -p "GitHub token: " TOKEN; echo
TOKEN_FILE="$(mktemp /tmp/cubynode-token.XXXXXX)"
AUTH_FILE="$(mktemp /tmp/cubynode-auth.XXXXXX)"
chmod 600 "$TOKEN_FILE" "$AUTH_FILE"
printf '%s' "$TOKEN" >"$TOKEN_FILE"
printf 'Authorization: Bearer %s\n' "$TOKEN" >"$AUTH_FILE"
unset TOKEN

CUBYNODE_GITHUB_TOKEN_FILE="$TOKEN_FILE" \
bash <(curl -fsSL \
  -H @"$AUTH_FILE" \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "https://api.github.com/repos/ItechLabFr/CubyNode/contents/scripts/proxmox-lxc-install.sh?ref=main")

rm -f "$TOKEN_FILE" "$AUTH_FILE"
```

The token is never stored in the Git remote URL.

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
- nesting: enabled before first boot (required by modern systemd in current Debian LXC templates)
- start at boot: enabled

## Installation inside the LXC

The bootstrap installs:

- ca-certificates
- curl
- git
- openssh-client
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


## Private GitHub authentication lifecycle

During initial install:

```text
temporary PAT
   ↓
private Git clone over HTTPS
   ↓
generate Ed25519 key inside LXC
   ↓
POST read-only Deploy Key to GitHub
   ↓
switch origin to git@github.com:ItechLabFr/CubyNode.git
   ↓
delete temporary PAT
```

The persistent private key is stored at:

```text
/var/lib/cubynode/github_deploy_key
```

Permissions:

```text
owner: cubynode
mode: 0600
```

GitHub host keys are pinned in:

```text
/etc/cubynode/github_known_hosts
```

Future **Simple** and **Complete** updates use the Deploy Key through the repository's `core.sshCommand` configuration. No PAT is required by the running panel.


## systemd 257 / nesting

Current Debian 13 LXC templates use a recent systemd. CubyNode creates the container with:

```text
features: nesting=1
```

before the first boot.

This avoids the Proxmox startup failure:

```text
WARN: Systemd 257 detected. You may need to enable nesting.
TASK ERROR: startup for container '<CTID>' failed
```

For a container already created without nesting:

```bash
pct set <CTID> --features nesting=1
pct start <CTID>
```

The installer intentionally does not enable `keyctl=1` because Docker is not required inside the CubyNode control-plane LXC.

## LXC first-boot troubleshooting

An LXC failure such as `sync_wait: 34 (expected sequence number 7)` is a **generic symptom** and does not, on its own, establish that nesting is missing. The installer sets `nesting=1` before first boot. Root-filesystem permissions, storage mount options, AppArmor, mismatched template architecture and Proxmox host configuration can also cause similar failures.

The installer now saves the **first boot debug log** at:

```text
/var/log/cubynode-lxc-start-<CTID>.log
```

It displays the most relevant startup errors in the TUI and preserves the failed LXC for inspection instead of deleting it.

For an existing failed CT (substitute its actual CTID):

```bash
pct config 102
pct start 102 --debug 2>&1 | tee /root/cubynode-102-debug.log
pveversion -v
journalctl -u pve-container@102.service --no-pager -n 100
```

Use the debug output to identify the actual failing phase **before** changing privileges, disabling AppArmor, removing the container or changing storage settings. In particular, `sync_wait` alone is not sufficient to diagnose a missing `nesting` feature.


## Native LXC template architecture

Native LXC instances must use the same CPU architecture as the Proxmox host. The installer now reads `dpkg --print-architecture` and chooses only matching Debian/Ubuntu templates (e.g. `_amd64.tar.zst` on an amd64 host). Explicit template overrides with the wrong architecture are rejected **before** creating the container.

An architecture mismatch typically causes `Exec format error - Failed to exec "/sbin/init"` at first boot; `nesting=1` does not solve this error. The root filesystem of an already-created container with the wrong CPU architecture must be replaced/recreated using the correct template after preserving any important data; simply changing `arch:` in the container config does not convert its binaries.


## Bootstrap fails after LXC boots

A successful `pct start` ends with `Started "/sbin/init"`. If the installer instead fails while executing the in-container bootstrap (currently the step after "Bootstrap privé transféré"), don't diagnose it as an LXC startup error.

For an existing failed CT, inspect its state and the root-only installer log on the Proxmox host:

```bash
pct status <CTID>
tail -n 100 /var/log/cubynode-lxc-installer.log
```

The installer writes the in-container bootstrap's output to a separate root-only file during new installs:

```text
/var/log/cubynode-lxc-bootstrap-<CTID>.log
```

That log may include credentials if bootstrap finished successfully. Redact access tokens, passwords, and URLs containing credentials before sharing any log. Do not destroy the CT when the bootstrap fails; it may be recoverable without downloading a new template.

## Recover a running LXC whose private bootstrap token was not transferred

If `pct status <CTID>` reports `running` but the bootstrap log ends with
`Temporary GitHub token file is missing`, **keep the existing CT**.
The Proxmox host needs to push a new temporary PAT into the CT, then rerun the bootstrap.

On the Proxmox host, as root, replace `103` below with the failed CTID.
This command securely prompts for the same scoped GitHub PAT; it is **not**
placed in shell history or a Git remote URL.

```bash
CTID=103
read -r -s -p "Temporary GitHub PAT: " PAT; echo
TOKEN_FILE="$(mktemp /tmp/cubynode-recovery-token.XXXXXX)"
AUTH_FILE="$(mktemp /tmp/cubynode-recovery-auth.XXXXXX)"
BOOT_FILE="$(mktemp /tmp/cubynode-recovery-bootstrap.XXXXXX)"
chmod 0600 "$TOKEN_FILE" "$AUTH_FILE" "$BOOT_FILE"
printf '%s' "$PAT" > "$TOKEN_FILE"
printf 'Authorization: Bearer %s\n' "$PAT" > "$AUTH_FILE"
unset PAT

curl -fsSL \
  -H @"$AUTH_FILE" \
  -H "Accept: application/vnd.github.raw+json" \
  "https://api.github.com/repos/ItechLabFr/CubyNode/contents/scripts/lxc-bootstrap.sh?ref=main" \
  -o "$BOOT_FILE"

pct push "$CTID" "$BOOT_FILE" /root/cubynode-bootstrap.sh --user root --group root --perms 0755
pct push "$CTID" "$TOKEN_FILE" /root/.cubynode-github-token --user root --group root --perms 0600

# Verify the secret arrived; never display its contents.
pct exec "$CTID" -- sh -c 'test -s /root/.cubynode-github-token && test -r /root/cubynode-bootstrap.sh' \
  && echo "Token transfer verified"

rm -f "$TOKEN_FILE" "$AUTH_FILE" "$BOOT_FILE"

# Resume only after checking that the verification above succeeded:
pct exec "$CTID" -- env CUBYNODE_GITHUB_TOKEN_FILE=/root/.cubynode-github-token CUBYNODE_UPDATE_CHANNEL=main bash /root/cubynode-bootstrap.sh
```

If the file-transfer verification fails, **do not run the final bootstrap command**. Check `pct status <CTID>` and `pct exec <CTID> -- ls -ld /root` instead.

The installer now verifies both file readability and matching SHA-256 checksums **before** removing its host-side token. A failed verification stops the installation at that stage and preserves the CT.


## Private Git clone asks for a username (bootstrap retry)

If the recovery bootstrap finishes installing Node.js and PostgreSQL, but
`git clone` requests a GitHub username and eventually reports
`Authentication failed`, the LXC and dependency installation have succeeded.
The old bootstrap used an HTTP Bearer header for Git HTTPS cloning, whereas
GitHub documents PATs for Git HTTPS as passwords, accompanied by a nonempty
username.

The private bootstrap now uses a temporary `GIT_ASKPASS` helper that supplies
`x-access-token` as the username and reads the PAT from a temporary
`0600` file as the password. Git's terminal prompt is disabled. The token
is never placed in the remote URL or in Git's persistent configuration.

**Recovery:** Keep the running CT and rerun the existing
[private-repository recovery commands](#recover-a-running-lxc-whose-private-bootstrap-token-was-not-transferred)
using the current bootstrap from `main` and the same temporary PAT.
The bootstrap may reuse already installed OS dependencies, then establishes a
dedicated read-only SSH Deploy Key for subsequent admin-panel updates.

If `git ls-remote` authentication still fails, confirm the fine-grained
token belongs to a user who has repository access and grants
`Contents: Read` for `ItechLabFr/CubyNode`. For automatic deploy-key
registration, it also needs `Administration: Read and write`.
Never paste the PAT or a verbose Git HTTP trace into a support request.


## Host-side token environment must not leak into the LXC

The outer installer launch can set `CUBYNODE_GITHUB_TOKEN_FILE` to a temporary **Proxmox host** path (for example `/tmp/tmp.XXXXXX/token`). This host path is not valid inside the container. The bootstrap always reads its own token at `/root/.cubynode-github-token`, which `pct push` has created. The launcher also passes this path explicitly when invoking the bootstrap inside the CT, so an inherited host environment cannot override it.

If a CT is already running and displays `Temporary GitHub token file does not exist in the LXC: /tmp/...`, check the container-local file without printing its contents:

```bash
pct exec <CTID> -- test -s /root/.cubynode-github-token
```

If the test succeeds, rerun the already transferred bootstrap using the container-local path:

```bash
pct exec <CTID> -- env CUBYNODE_GITHUB_TOKEN_FILE=/root/.cubynode-github-token CUBYNODE_UPDATE_CHANNEL=main bash /root/cubynode-bootstrap.sh
```

If the test fails, use the secure token-transfer recovery procedure above, rather than creating a new container. Keep PATs out of logs and support messages.


## Debian mirror DNS failure during bootstrap

When the LXC has started but apt reports `Temporary failure resolving 'deb.debian.org'`, it is a DNS/network problem **inside the CT**, not a LXC creation or GitHub-authentication error. Keep the existing container and inspect from the Proxmox host (replace the CTID):

```bash
pct status 102
pct exec 102 -- ip -4 addr show dev eth0
pct exec 102 -- ip -4 route
pct exec 102 -- cat /etc/resolv.conf
pct exec 102 -- getent ahostsv4 deb.debian.org
pct exec 102 -- getent ahostsv4 security.debian.org
```

If the CT has a valid IP and default gateway but DNS lookup fails, configure a reachable DNS server in Proxmox for **that CT**, for example:

```bash
pct set 102 --nameserver 1.1.1.1
pct reboot 102
pct exec 102 -- getent ahostsv4 deb.debian.org
```

Use the site's router/internal DNS instead when public DNS is restricted. If there is no IP or default route, fix DHCP/bridge/gateway first; a nameserver change will not restore missing connectivity.

The launcher now checks DNS for Debian, security updates, NodeSource and GitHub **before** transferring a PAT into the CT. The bootstrap also retries DNS and apt package fetches. These checks detect and tolerate transient failures but cannot override local firewalls or broken network infrastructure. If a bootstrap already failed, the token may have been cleaned up; use the safe same-CT recovery procedure above after restoring DNS.


## VLAN 10 par défaut

Le LXC CubyNode est créé sur `vmbr0` avec un tag VLAN `10` et une adresse IPv4 obtenue en DHCP :

```text
net0: name=eth0,bridge=vmbr0,tag=10,ip=dhcp,type=veth
```

Le VLAN peut être changé sans modifier le script en lançant l'installateur avec :

```bash
CUBYNODE_VLAN_TAG=20 ...
```

La valeur doit être comprise entre 1 et 4094. Le bridge Proxmox et le switch physique doivent transporter le VLAN choisi, et le VLAN doit disposer d'un serveur DHCP/DNS fonctionnel.
