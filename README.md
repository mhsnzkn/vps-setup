# vps-hardening

Modular scripts + docs for securely bootstrapping a fresh Linux VPS
(Ubuntu 24.04 / Debian 12+) that will run Docker containers behind nginx.

Based on the hardening checklist at:
https://kagesystem.com/blog/harden-linux-vps/

## What this does

- Updates the system and enables automatic security updates
- Creates a non-root sudo user (root stays, but SSH access moves off it)
- Hardens SSH (key auth, no root login, no password login)
- Sets up a default-deny firewall (UFW), keeping port 22 open
- Applies basic kernel/network sysctl hardening
- Installs Docker + Docker Compose
- Optionally installs and configures nginx as a reverse proxy

## What this does NOT do (on purpose, for now)

- No fail2ban / CrowdSec
- No auditd / Lynis auditing
- No VPN-only SSH access
- No reverse proxy other than nginx (no Caddy, Traefik, etc.)

These can be added later as their own standalone scripts if needed.

## Usage

There are two ways to run this: on the box itself, or remotely from
your own machine via `deploy.sh`.

### Option A — run on the box itself

1. Copy the config template and edit it for this server:
   ```
   cp scripts/initial-setup/config/server.env.example scripts/initial-setup/config/server.env
   nano scripts/initial-setup/config/server.env
   ```
2. Copy the repo to the VPS (as root, over SSH) and run:
   ```
   sudo bash scripts/initial-setup/00-main.sh
   ```
3. Follow the prompts. The script will pause after creating the new
   user and ask you to verify login in a **second SSH session** before
   it touches SSH config. Do not skip this — see docs/runbook.md.
4. Once the main pass is done, if this box needs nginx:
   ```
   sudo bash scripts/initial-setup/nginx.sh
   ```

### Option B — run from your local machine via `deploy.sh` (no upload)

You don't have to SSH in and run things by hand, and you don't need
to copy this repo onto the server either. `deploy.sh` builds a single
self-contained bash script locally — this repo's shared helpers, your
config values, and the step you asked for, all inlined — and streams
it to the server over the SSH connection itself. Nothing from this
repo is left on disk on the server.

This needs only `ssh` on your machine and `bash` + `base64` on the
remote side (both present by default on any stock Debian/Ubuntu box)
— no `rsync`, no `scp`, no extra tooling to install anywhere.

```
cp scripts/initial-setup/config/server.env.example scripts/initial-setup/config/server.env
nano scripts/initial-setup/config/server.env

./scripts/initial-setup/deploy.sh root@203.0.113.10                        # full pass, runs 00-main.sh
./scripts/initial-setup/deploy.sh root@203.0.113.10 nginx.sh               # just the nginx step
./scripts/initial-setup/deploy.sh deploy@203.0.113.10 fail2ban.sh          # after the user exists, use it

# Using a specific SSH key instead of your default one:
./scripts/initial-setup/deploy.sh -i ~/.ssh/vps_key deploy@203.0.113.10
./scripts/initial-setup/deploy.sh -i ~/.ssh/vps_key -p 2222 deploy@203.0.113.10 nginx.sh
```

Because the script is streamed rather than piped through your local
terminal's stdin, prompts inside it read from `/dev/tty` explicitly —
so the interactive confirms still work exactly as if you'd typed the
commands yourself over a normal SSH session.

Important: after `03-ssh-hardening.sh` runs, root login and password
auth get disabled on the server. Any `deploy.sh` call after that point
needs to target the non-root user (`deploy@host`), not `root@host`.

**Already have a non-root sudo user from your VPS provider, with SSH
already working?** You don't need root at all. Set `NEW_USER` in
`scripts/initial-setup/config/server.env` to that username and target it directly:
```
./scripts/initial-setup/deploy.sh -i ~/.ssh/vps_key deploy@203.0.113.10
```
`02-create-user.sh` will detect the user already exists and offer to
use it as-is — skipping password reset and key setup since SSH is
already sorted.

See `docs/runbook.md` for the full step-by-step and `docs/verify.md`
for how to check each step actually worked.

## Structure

```
scripts/
  initial-setup/       one-time hardening scripts + config (run via deploy.sh)
    config/
      server.env.example variables — copy to server.env and edit per-server
    lib/common.sh        shared helper functions
    deploy.sh            remote runner — streams scripts to the server over SSH
    00-main.sh           orchestrator, runs 01-06 in order
    01-updates.sh        apt update/upgrade, unattended-upgrades
    02-create-user.sh    non-root sudo user + SSH key
    03-ssh-hardening.sh  sshd_config.d drop-in
    04-firewall.sh       UFW default-deny
    05-sysctl-hardening.sh kernel/network tunables
    06-docker.sh         Docker + Compose install
    nginx.sh             standalone reverse-proxy setup (run manually)
    fail2ban.sh          standalone fail2ban setup (run manually)
  update/              ongoing maintenance scripts (generic, no config file)
    update.sh            apt update + upgrade a single VPS
    update-all.sh        batch-update multiple VPS from a server list
    servers.txt.example  example server list for update-all.sh
docs/
  runbook.md            order of operations, what to check between steps
  verify.md             verification command per step
```

### Ongoing updates — `scripts/update/`

The update scripts are **generic** — they don't depend on `config/server.env`.
SSH key, username, and host are passed as command-line parameters, so you
can use them on any VPS without cloning the config file.

#### Single server

```bash
# Basic usage
./scripts/update/update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10

# Non-standard SSH port
./scripts/update/update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10 -p 2222

# Skip confirmation and auto-reboot if needed
./scripts/update/update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10 -y --reboot
```

#### Multiple servers

Create a `servers.txt` from the example:

```bash
cp scripts/update/servers.txt.example scripts/update/servers.txt
nano scripts/update/servers.txt
```

Then run:

```bash
./scripts/update/update-all.sh -f scripts/update/servers.txt
./scripts/update/update-all.sh -f scripts/update/servers.txt -y --reboot
```

Every script under `scripts/initial-setup/` can also be run on its own (they each
source `scripts/initial-setup/config/server.env` and `lib/common.sh` independently), which
is useful if you only need to re-apply one step on an existing box.

Each script (except `lib/common.sh`) defines a single `step_*()`
function and only calls it if the file is executed directly — guarded
by a `BASH_SOURCE`/`$0` check at the bottom. That's what makes
`deploy.sh`'s no-upload streaming mode possible: it extracts each
step's function body and assembles them into one in-memory bundle
rather than needing the files present on the server's disk.
