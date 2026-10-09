#!/usr/bin/env bash
# ============================================================
# PREFLIGHT — run on the HUB before installing anything
# ============================================================
# Answers the one question that decides whether the plan works at
# all: can the hub actually reach each node?
#
# Worth running first. Discovering a routing or firewall problem
# after four installs is far more expensive than discovering it
# now.
set -uo pipefail

# --- fill in from your inventory ----------------------------
NODE_B="<NODE_B_IPV6>"
NODE_C="<NODE_C_IPV4>"
NODE_D="<NODE_D_IPV4>"
# ------------------------------------------------------------

echo "=============================================="
echo " 1. This host's global IPv6 address"
echo "=============================================="
# This is what a node's firewall must allow if the hub reaches it
# over IPv6 — NOT the hub's IPv4 address. Getting this wrong is a
# common and confusing failure: the rule looks right and the
# target stays DOWN.
ip -6 addr show scope global 2>/dev/null | grep inet6 || echo ">> NO GLOBAL IPv6 <<"

echo
echo "=============================================="
echo " 2. Default IPv6 route"
echo "=============================================="
ip -6 route show default || echo ">> NO DEFAULT IPv6 ROUTE <<"

echo
echo "=============================================="
echo " 3. Outbound IPv6 connectivity"
echo "=============================================="
ping6 -c 2 -W 3 2606:4700:4700::1111 >/dev/null 2>&1 \
  && echo "OK  — outbound IPv6 works" \
  || echo "FAIL — no outbound IPv6 from this host"

echo
echo "=============================================="
echo " 4. Reachability of each node"
echo "=============================================="
printf '  node-b : '; ping6 -c 2 -W 3 "$NODE_B" >/dev/null 2>&1 && echo OK || echo FAIL
printf '  node-c : '; ping  -c 2 -W 3 "$NODE_C" >/dev/null 2>&1 && echo OK || echo FAIL
printf '  node-d : '; ping  -c 2 -W 3 "$NODE_D" >/dev/null 2>&1 && echo OK || echo FAIL

echo
echo "=============================================="
echo " 5. Docker and firewall state"
echo "=============================================="
docker --version 2>/dev/null || echo "Docker not installed"
docker compose version 2>/dev/null || echo "Compose plugin not installed"
sudo ufw status verbose 2>/dev/null || echo "UFW not installed"
grep '^IPV6' /etc/default/ufw 2>/dev/null \
  || echo "(/etc/default/ufw not found)"
# IPV6=yes matters: with it off, every IPv6 rule you add is
# silently ignored.
