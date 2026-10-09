#!/usr/bin/env bash
# ============================================================
# UFW — Podman node
# ============================================================
# ADDITIVE: adds one rule, removes nothing.
#
# This kind of host has no private link to the hub, so
# node_exporter must listen on a public interface. UFW is
# genuinely the only guard here — unlike the Docker node, which
# also binds to a private address. Install this rule BEFORE
# starting the exporter.
#
# Per-host values come from .env, so this file is identical on
# every Podman node.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

[[ -f .env ]] || { echo "STOP: no .env here. Copy .env.example and fill it in."; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a

ALLOW_FROM="${ALLOW_FROM:?set ALLOW_FROM in .env}"

if ! command -v ufw >/dev/null 2>&1; then
  echo "UFW not installed: sudo apt-get install -y ufw"
  echo "WARNING: never run 'ufw enable' before allowing SSH, or you"
  echo "will lock yourself out."
  exit 1
fi

if [[ "$ALLOW_FROM" == *:* ]] && ! grep -q '^IPV6=yes' /etc/default/ufw; then
  echo "STOP: ALLOW_FROM is IPv6 but /etc/default/ufw has IPV6=no."
  exit 1
fi

echo "=== rules BEFORE ==="
sudo ufw status numbered

echo
echo "Exactly one rule will be ADDED:"
echo "  9100/tcp  ALLOW IN  from $ALLOW_FROM"
read -rp "Continue? (type yes) " a; [[ "$a" == "yes" ]] || exit 1

sudo ufw allow from "$ALLOW_FROM" to any port 9100 proto tcp comment 'Prometheus scrape from hub'

echo
echo "=== rules AFTER ==="
sudo ufw status numbered
