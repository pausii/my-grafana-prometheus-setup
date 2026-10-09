#!/usr/bin/env bash
# ============================================================
# UFW — Docker node
# ============================================================
# ADDITIVE: this only ADDS one rule. No reset, no change to rules
# already in use.
#
# An earlier version used "ufw --force reset", which would have
# wiped the existing web rules and taken the site down. Removed.
#
# Per-host values come from .env, so this file is identical on
# every Docker node.
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

[[ -f .env ]] || { echo "STOP: no .env here. Copy .env.example and fill it in."; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a

ALLOW_FROM="${ALLOW_FROM:?set ALLOW_FROM in .env}"
VLAN_IFACE="${VLAN_IFACE:-}"

# Only check the private interface if this host is supposed to have
# one. Hosts without a private link skip this entirely.
if [[ -n "$VLAN_IFACE" ]]; then
  if ! ip -4 addr show "$VLAN_IFACE" >/dev/null 2>&1; then
    echo "STOP: interface $VLAN_IFACE not found."
    echo "Check the private network, or clear VLAN_IFACE in .env."
    exit 1
  fi
fi

# UFW must process IPv6, otherwise any IPv6 rule is silently
# ignored — the rule appears in the list and does nothing.
if [[ "$ALLOW_FROM" == *:* ]] && ! grep -q '^IPV6=yes' /etc/default/ufw; then
  echo "STOP: ALLOW_FROM is IPv6 but /etc/default/ufw has IPV6=no."
  echo "  sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw"
  exit 1
fi

echo "=== rules BEFORE ==="
sudo ufw status numbered

echo
echo "Exactly one rule will be ADDED:"
echo "  9100/tcp  ALLOW IN  from $ALLOW_FROM"
echo "Nothing else is touched."
read -rp "Continue? (type yes) " a; [[ "$a" == "yes" ]] || exit 1

sudo ufw allow from "$ALLOW_FROM" to any port 9100 proto tcp comment 'Prometheus scrape from hub'

echo
echo "=== rules AFTER ==="
sudo ufw status numbered

echo
echo "To undo:"
echo "  sudo ufw delete allow from $ALLOW_FROM to any port 9100 proto tcp"
