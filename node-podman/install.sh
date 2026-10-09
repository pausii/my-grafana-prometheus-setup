#!/usr/bin/env bash
# ============================================================
# node_exporter via ROOTFUL Podman + Quadlet
#   bash install.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== 1/5 Check Podman =="
if ! command -v podman >/dev/null 2>&1; then
  apt-get update && apt-get install -y podman
fi
podman --version

# Quadlet requires Podman 4.4 or newer.
VER=$(podman --version | awk '{print $3}')
if (( ${VER%%.*} < 4 )); then
  echo "Podman $VER is too old for Quadlet."
  exit 1
fi

echo
echo "== 2/5 Install the Quadlet unit =="
install -d -m 0755 /etc/containers/systemd
install -m 0644 "$SCRIPT_DIR/node-exporter.container" /etc/containers/systemd/
echo "  -> /etc/containers/systemd/node-exporter.container"

echo
echo "== 3/5 Show the unit Quadlet GENERATES =="
# Purely educational: prints the .service unit systemd invents
# from the .container file above. You never write this file, but
# this is what actually runs. Look at ExecStart — it is a full
# "podman run" command with every flag.
/usr/lib/systemd/system-generators/podman-system-generator --dryrun 2>/dev/null \
  | sed -n '/node-exporter/,/^$/p' | head -40 \
  || echo "  (generator dry-run unavailable, continuing)"

echo
echo "== 4/5 Reload systemd and start =="
# daemon-reload is what triggers the Quadlet generator.
systemctl daemon-reload
systemctl start node-exporter.service

echo
echo "== 5/5 Verify =="
sleep 8
systemctl --no-pager status node-exporter.service || true
echo
# Do NOT pipe curl into head here: head closes the pipe after a few
# lines, curl exits 23, and the check looks like a failure while
# the metrics are fine. Worse, node_exporter logs hundreds of
# "broken pipe" errors. Capture the whole response first.
METRICS=$(curl -fsS --max-time 15 http://127.0.0.1:9100/metrics || true)
if [[ -n "$METRICS" ]]; then
  printf '%s\n' "$METRICS" | head -5
  echo
  echo "SUCCESS — $(printf '%s\n' "$METRICS" | grep -c '^node_') node_ metrics"
  echo "Next: bash ufw.sh"
else
  echo "FAILED. Check: journalctl -u node-exporter.service -n 50 --no-pager"
  exit 1
fi
