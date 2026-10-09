#!/usr/bin/env bash
# ============================================================
# PREFLIGHT — run on an IPv6-only node
# ============================================================
# IPv6-only hosts hit one classic problem: some registries and
# package mirrors have no IPv6 address. The host cannot reach them
# directly, so "docker pull" fails with a confusing "no route to
# host" or "i/o timeout" — while the network itself is perfectly
# healthy.
#
# The fix is DNS64 + NAT64. A DNS64 resolver synthesises AAAA
# answers for domains that only have A records, pointing at a
# NAT64 gateway that translates your IPv6 traffic to IPv4. Most
# providers offering IPv6-only instances run one.
#
# This script confirms that BEFORE you run compose.
set -uo pipefail

echo "=============================================="
echo " 1. IPv6 address and route"
echo "=============================================="
ip -6 addr show scope global | grep inet6
ip -6 route show default

echo
echo "=============================================="
echo " 2. Which DNS resolver is in use"
echo "=============================================="
resolvectl status 2>/dev/null | grep -i 'DNS Servers' || cat /etc/resolv.conf

echo
echo "=============================================="
echo " 3. Can the registry be resolved? (DNS64 test)"
echo "=============================================="
getent ahostsv6 registry-1.docker.io | head -3 \
  || echo ">> RESOLUTION FAILED — DNS64 not active <<"

echo
echo "=============================================="
echo " 4. Real connection test"
echo "=============================================="
if curl -6 -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 15 \
     https://registry-1.docker.io/v2/ ; then
  echo "OK — registry reachable over IPv6 (401 is expected)"
else
  echo ">> FAILED — image pulls will not work <<"
fi

echo
echo "=============================================="
echo " 5. Actual pull"
echo "=============================================="
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not installed yet — run install-docker.sh first."
elif docker pull prom/node-exporter:v1.12.1; then
  echo "OK — image ready, continue with docker compose up -d"
else
  echo ">> PULL FAILED <<"
fi
