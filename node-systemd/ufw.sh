#!/usr/bin/env bash
# ============================================================
# UFW — systemd node
# ============================================================
# This kind of host often has UFW INACTIVE, so this script enables
# it. Order matters: allow SSH first, enable second. Reversed,
# your session drops and you cannot get back in.
#
# WARNING: open a second SSH session before running this.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

[[ -f .env ]] || { echo "STOP: no .env here. Copy .env.example and fill it in."; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a

ALLOW_FROM="${ALLOW_FROM:?set ALLOW_FROM in .env}"
SSH_PORT="${SSH_PORT:-22}"

echo "Rules to be applied:"
echo "  $SSH_PORT/tcp     : from anywhere"
echo "  9100/tcp   : from $ALLOW_FROM only"
echo "  everything else : DENIED"
read -rp "Continue? (type yes) " a; [[ "$a" == "yes" ]] || exit 1

ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp" comment 'SSH'
ufw allow from "$ALLOW_FROM" to any port 9100 proto tcp comment 'Prometheus scrape from hub'
ufw --force enable
echo
ufw status verbose numbered
