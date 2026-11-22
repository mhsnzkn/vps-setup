#!/usr/bin/env bash
# Update multiple VPS servers in sequence.
#
# Reads a list of servers from a file (one per line) and runs
# update.sh against each one. Useful for maintaining several boxes.
#
# Usage:
#   ./update-all.sh -f <servers_file> [-y] [--reboot]
#
#   -f servers_file    Path to a file listing servers to update.
#                       Each line: <identity_file> <user> <host> [port]
#                       Blank lines and lines starting with # are ignored.
#   -y                 Skip confirmation prompt for each server.
#   --reboot           Reboot servers automatically if required.
#   --help             Show this help.
#
# Server file format (servers.txt):
#   # identity_file           user     host             port
#   ~/.ssh/vps_key            deploy   203.0.113.10
#   ~/.ssh/other_key          admin    198.51.100.5     2222
#
# Examples:
#   ./update-all.sh -f servers.txt
#   ./update-all.sh -f servers.txt -y --reboot

set -euo pipefail

COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"

log()  { echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $*"; }
warn() { echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"; }
die()  { echo -e "${COLOR_RED}[x]${COLOR_RESET} $*" >&2; exit 1; }

usage() {
  sed -n '2,/^[^#]/{ s/^# \{0,1\}//p }' "$0"
  exit 1
}

SERVERS_FILE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)        SERVERS_FILE="$2"; shift 2 ;;
    -y)        EXTRA_ARGS+=("-y"); shift ;;
    --reboot)  EXTRA_ARGS+=("--reboot"); shift ;;
    --help)    usage ;;
    *)         die "Unknown option: $1. Use --help for usage." ;;
  esac
done

[[ -n "$SERVERS_FILE" ]] || die "Missing required option: -f <servers_file>"
[[ -f "$SERVERS_FILE" ]] || die "Servers file not found: ${SERVERS_FILE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update.sh"

[[ -f "$UPDATE_SCRIPT" ]] || die "update.sh not found at ${UPDATE_SCRIPT}"

succeeded=()
failed=()

while IFS= read -r line || [[ -n "$line" ]]; do
  # skip blank lines and comments
  line="$(echo "$line" | sed 's/#.*$//' | xargs)"
  [[ -z "$line" ]] && continue

  identity_file="$(echo "$line" | awk '{print $1}')"
  user="$(echo "$line" | awk '{print $2}')"
  host="$(echo "$line" | awk '{print $3}')"
  port="$(echo "$line" | awk '{print $4}')"

  [[ -z "$identity_file" || -z "$user" || -z "$host" ]] && {
    warn "Skipping malformed line: ${line}"
    continue
  }

  port_args=()
  [[ -n "$port" ]] && port_args=(-p "$port")

  echo
  echo "============================================================"
  log "Updating: ${user}@${host}"
  echo "============================================================"

  if bash "$UPDATE_SCRIPT" -i "$identity_file" -u "$user" -h "$host" "${port_args[@]}" "${EXTRA_ARGS[@]}"; then
    succeeded+=("${user}@${host}")
  else
    warn "Update failed for ${user}@${host}"
    failed+=("${user}@${host}")
  fi

done < "$SERVERS_FILE"

echo
echo "============================================================"
log "Batch update complete."

if [[ ${#succeeded[@]} -gt 0 ]]; then
  log "Succeeded (${#succeeded[@]}): ${succeeded[*]}"
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  warn "Failed (${#failed[@]}): ${failed[*]}"
  exit 1
fi
