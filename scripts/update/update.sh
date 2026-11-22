#!/usr/bin/env bash
# Run apt update + apt upgrade on a remote VPS over SSH.
#
# This script runs FROM YOUR LOCAL MACHINE. It connects to the server
# via SSH, runs the update/upgrade commands remotely, and reports back.
# Nothing is copied to the server.
#
# Usage:
#   ./update.sh -i <identity_file> -u <user> -h <host> [-p port]
#
#   -i identity_file   Path to the SSH private key (certificate) for
#                       authentication.
#   -u user            SSH username on the remote server.
#   -h host            Server IP address or hostname.
#   -p port            SSH port (default: 22).
#   -y                 Skip confirmation prompt (auto-yes).
#   --reboot           Reboot the server automatically if the kernel
#                       was updated and a reboot is required.
#   --help             Show this help.
#
# Examples:
#   ./update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10
#   ./update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10 -p 2222
#   ./update.sh -i ~/.ssh/vps_key -u deploy -h 203.0.113.10 -y --reboot

set -euo pipefail

# --- colors (local terminal) ------------------------------------------------
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"

log()  { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"; }
die()  { echo -e "${COLOR_RED}[x]${COLOR_RESET} $*" >&2; exit 1; }

# --- argument parsing -------------------------------------------------------
usage() {
  sed -n '2,/^[^#]/{ s/^# \{0,1\}//p }' "$0"
  exit 1
}

IDENTITY_FILE=""
SSH_USER=""
SSH_HOST=""
SSH_PORT="22"
AUTO_YES="false"
AUTO_REBOOT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)          IDENTITY_FILE="$2"; shift 2 ;;
    -u)          SSH_USER="$2";      shift 2 ;;
    -h)          SSH_HOST="$2";      shift 2 ;;
    -p)          SSH_PORT="$2";      shift 2 ;;
    -y)          AUTO_YES="true";    shift   ;;
    --reboot)    AUTO_REBOOT="true"; shift   ;;
    --help)      usage ;;
    *)           die "Unknown option: $1. Use --help for usage." ;;
  esac
done

[[ -n "$IDENTITY_FILE" ]] || die "Missing required option: -i <identity_file>"
[[ -n "$SSH_USER" ]]      || die "Missing required option: -u <user>"
[[ -n "$SSH_HOST" ]]      || die "Missing required option: -h <host>"

if [[ ! -f "$IDENTITY_FILE" ]]; then
  die "Identity file not found: ${IDENTITY_FILE}"
fi

PERMS="$(stat -c '%a' "$IDENTITY_FILE" 2>/dev/null || stat -f '%Lp' "$IDENTITY_FILE" 2>/dev/null || echo '')"
if [[ -n "$PERMS" && "$PERMS" != "600" && "$PERMS" != "400" ]]; then
  warn "${IDENTITY_FILE} has permissions ${PERMS} — ssh may refuse to use it."
  warn "Fix with: chmod 600 ${IDENTITY_FILE}"
fi

TARGET="${SSH_USER}@${SSH_HOST}"

# --- confirmation -----------------------------------------------------------
if [[ "$AUTO_YES" != "true" ]]; then
  echo "Target:  ${TARGET} (port ${SSH_PORT})"
  echo "Key:     ${IDENTITY_FILE}"
  echo "Action:  apt update + apt full-upgrade"
  [[ "$AUTO_REBOOT" == "true" ]] && echo "Reboot:  yes (if required)"
  echo
  read -r -p "Proceed? [y/N] " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] || { echo "Aborted."; exit 0; }
fi

# --- build the remote script ------------------------------------------------
REMOTE_SCRIPT='#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"
log()  { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[x]${RESET} $*" >&2; exit 1; }

log "Updating package lists..."
apt update

log "Upgrading installed packages..."
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y

log "Removing packages no longer needed..."
apt autoremove --purge -y

log "Cleaning local package cache..."
apt clean

if [[ -f /var/run/reboot-required ]]; then
  warn "A reboot is required (kernel or core library was updated)."
  REBOOT_PACKAGES=""
  [[ -f /var/run/reboot-required.pkgs ]] && REBOOT_PACKAGES="$(cat /var/run/reboot-required.pkgs)"
  [[ -n "$REBOOT_PACKAGES" ]] && warn "Packages requiring reboot: ${REBOOT_PACKAGES}"
  if [[ "${1:-}" == "--reboot" ]]; then
    warn "Auto-reboot requested — rebooting in 5 seconds..."
    sleep 5
    reboot
  else
    warn "Reboot manually when convenient: sudo reboot"
  fi
else
  log "No reboot required."
fi

log "System update complete."
'

# --- connect and run --------------------------------------------------------
log "Connecting to ${TARGET} (port ${SSH_PORT})..."

REBOOT_FLAG=""
[[ "$AUTO_REBOOT" == "true" ]] && REBOOT_FLAG="--reboot"

ENCODED="$(printf '%s' "$REMOTE_SCRIPT" | base64 | tr -d '\n')"

ssh -t \
  -p "${SSH_PORT}" \
  -i "${IDENTITY_FILE}" \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 \
  "${TARGET}" \
  "echo ${ENCODED} | base64 -d | sudo bash -s -- ${REBOOT_FLAG}"

echo
log "Update of ${TARGET} finished."
