#!/usr/bin/env bash
# ============================================================
# node_exporter as a binary + systemd unit
# Run as root.
# ============================================================
set -euo pipefail

# Resolved BEFORE any "cd" below. Otherwise $(dirname "$0") is
# evaluated relative to /tmp later on and the unit file is not
# found — exactly the bug this script hit the first time.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -f "$SCRIPT_DIR/.env" ]] || { echo "STOP: no .env. Copy .env.example and fill it in."; exit 1; }
# shellcheck disable=SC1091
set -a; source "$SCRIPT_DIR/.env"; set +a
LISTEN_ADDR="${LISTEN_ADDR:?set LISTEN_ADDR in .env}"

VERSION="1.12.1"
ARCH="linux-amd64"
TARBALL="node_exporter-${VERSION}.${ARCH}.tar.gz"
BASE="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}"

echo "== 1/6 Download binary and checksums =="
cd /tmp
curl -fsSLO "${BASE}/${TARBALL}"
curl -fsSLO "${BASE}/sha256sums.txt"

echo
echo "== 2/6 Verify the checksum =="
# Not a formality. This binary runs at every boot with read access
# to all of /proc and /sys. If the download were tampered with —
# a poisoned mirror, a MITM — a checksum mismatch is the only
# warning you get. A container image gets this from its digest;
# here you have to do it yourself.
grep "  ${TARBALL}\$" sha256sums.txt | sha256sum -c -
echo "  checksum matches"

echo
echo "== 3/6 Install the binary =="
tar -xzf "$TARBALL"
install -m 0755 -o root -g root "node_exporter-${VERSION}.${ARCH}/node_exporter" /usr/local/bin/node_exporter
rm -rf "node_exporter-${VERSION}.${ARCH}" "$TARBALL" sha256sums.txt
/usr/local/bin/node_exporter --version 2>&1 | head -1 | sed 's/^/  /'

echo
echo "== 4/6 Unprivileged system user =="
if ! id node_exporter >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
  echo "  user node_exporter created"
else
  echo "  user node_exporter already exists"
fi

echo
echo "== 5/6 systemd unit =="
# Per-host settings live here, not in the unit — so the unit file
# is identical on every systemd node.
printf 'LISTEN_ADDR=%s\n' "$LISTEN_ADDR" > /etc/default/node_exporter
chmod 0644 /etc/default/node_exporter
echo "  -> /etc/default/node_exporter (LISTEN_ADDR=$LISTEN_ADDR)"
install -m 0644 "$SCRIPT_DIR/node_exporter.service" /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl enable --now node_exporter.service
echo "  enabled and started"

echo
echo "== 6/6 Verify =="
sleep 3
systemctl --no-pager --lines=0 status node_exporter.service | head -5 | sed 's/^/  /'
echo
M=$(curl -fsS --max-time 10 http://127.0.0.1:9100/metrics || true)
if [[ -n "$M" ]]; then
  echo "  node_ metrics       : $(printf '%s\n' "$M" | grep -c '^node_')"
  echo "  systemd units watched: $(printf '%s\n' "$M" | grep -c '^node_systemd_unit_state{.*state="active"')"
  echo "  units FAILED now    : $(printf '%s\n' "$M" | grep '^node_systemd_unit_state{' | grep 'state="failed"} 1' | grep -oE 'name="[^"]+"' | tr '\n' ' ')"
  echo
  echo "SUCCESS. Next: bash ufw.sh"
else
  echo "FAILED. Check: journalctl -u node_exporter -n 30 --no-pager"
  exit 1
fi
