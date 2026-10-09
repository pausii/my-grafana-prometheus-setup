#!/usr/bin/env bash
# ============================================================
# HUB — VERIFY, do not configure
# ============================================================
# This script changes NOTHING: no firewall reset, no new rules.
# The hub in the original setup already ran other services with
# UFW rules in use, and wiping those would have taken them down.
#
# Why the hub needs no new firewall rules at all: Prometheus
# (9090), Grafana (3000) and node_exporter (9100) all listen on
# 127.0.0.1 only. There is nothing to allow in, because there is
# nothing reachable.
set -uo pipefail

# --- fill in from your inventory ----------------------------
# These MUST be quoted. Unquoted, the shell reads "<" as an input
# redirection and the script dies with a syntax error before a
# single line runs.
NODE_B="<NODE_B_IPV6>"
NODE_C="<NODE_C_IPV4>"
# ------------------------------------------------------------

echo "=============================================="
echo " 1. Current UFW rules (NOT modified)"
echo "=============================================="
sudo ufw status verbose

echo
echo "=============================================="
echo " 2. Monitoring port bindings"
echo "=============================================="
echo "Must be 127.0.0.1, NOT 0.0.0.0 or [::]."
echo "A 0.0.0.0 here means the port is exposed to the internet,"
echo "bypassing UFW through Docker's iptables rules."
ss -tlnp 2>/dev/null | awk 'NR==1 || /:3000|:9090|:9091|:9100/'

echo
echo "=============================================="
echo " 3. Port conflicts before starting"
echo "=============================================="
for p in 3000 9090 9091 9100; do
  if ss -tln 2>/dev/null | grep -q ":$p "; then
    echo "  port $p : IN USE — check before compose up"
  else
    echo "  port $p : free"
  fi
done

echo
echo "=============================================="
echo " 4. Are the scrape targets reachable?"
echo "=============================================="
printf '  node-b (IPv6) : '; (ping6 -c1 -W3 "$NODE_B" >/dev/null 2>&1 && echo OK) || echo FAIL
printf '  node-c (IPv4) : '; (ping  -c1 -W3 "$NODE_C" >/dev/null 2>&1 && echo OK) || echo FAIL
