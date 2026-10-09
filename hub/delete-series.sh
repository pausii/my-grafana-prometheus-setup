#!/usr/bin/env bash
# ============================================================
# delete-series.sh — remove orphaned series from the EPHEMERAL
# Prometheus. Run on the hub, inside the compose directory.
# ============================================================
# Ephemeral servers leave orphaned series behind when their labels
# change — for example when a host re-registers under its IPv4
# address instead of its IPv6 one. Those series do not disappear
# until retention expires; they simply stop being updated.
#
#   bash delete-series.sh <EXAMPLE_IPV6>
#   bash delete-series.sh --list
set -euo pipefail

P=http://127.0.0.1:9091

if [[ "${1:-}" == "--list" || $# -eq 0 ]]; then
  echo "Series present in the ephemeral Prometheus:"
  curl -s "$P/api/v1/label/server/values" \
    | tr ',' '\n' | grep -oE '"[^"]+"' | tr -d '"' | grep -v '^data$\|^success$\|^status$' \
    | while read -r n; do
        live=$(curl -s -G --data-urlencode "query=up{server=\"$n\"}" "$P/api/v1/query" \
               | grep -c '"value"' || true)
        [[ "$live" -gt 0 ]] && echo "  $n   (ACTIVE — do not delete)" || echo "  $n   (inactive)"
      done
  echo
  echo "Usage: bash delete-series.sh <server-name>"
  exit 0
fi

TARGET="$1"

# Refuse to delete a server that is still pushing — it would just
# reappear seconds later.
LIVE=$(curl -s -G --data-urlencode "query=up{server=\"$TARGET\"}" "$P/api/v1/query" \
       | grep -c '"value"' || true)
if [[ "$LIVE" -gt 0 ]]; then
  echo "STOP: '$TARGET' is STILL pushing metrics."
  echo "Stop it on the host first (bash bootstrap.sh --uninstall),"
  echo "or re-run bootstrap so it uses its new labels."
  echo
  echo "Note: Prometheus considers a series live for 5 minutes after"
  echo "its last sample (lookback delta), so allow ~5 minutes after"
  echo "stopping an agent before cleaning up its old name."
  exit 1
fi

echo "Deleting all series with server=\"$TARGET\"..."
curl -sS -X POST -g \
  "$P/api/v1/admin/tsdb/delete_series?match[]={server=\"$TARGET\"}" \
  -w '  delete_series -> HTTP %{http_code}\n'

# delete_series only tombstones. Disk space is reclaimed once the
# tombstones are cleaned.
curl -sS -X POST "$P/api/v1/admin/tsdb/clean_tombstones" \
  -w '  clean_tombstones -> HTTP %{http_code}\n'

echo
# Verify by SAMPLE COUNT, not by the label list. delete_series
# removes the data, but the server NAME stays in the head block's
# index until that block is compacted (~2h). Checking
# /api/v1/label/... would look like the deletion failed.
LEFT=$(curl -s -G --data-urlencode "query=count_over_time({server=\"$TARGET\"}[7d])" \
       "$P/api/v1/query" | grep -c '"value"' || true)

if [[ "$LEFT" -eq 0 ]]; then
  echo "DELETED: no samples remain for '$TARGET'."
  echo
  echo "Its name may still appear in /api/v1/label/server/values for"
  echo "a few hours — that is index residue, not data. The Grafana"
  echo "dropdown does not show it because it uses query_result."
else
  echo "WARNING: $LEFT series still hold samples. Try again."
fi

echo
echo "Currently pushing:"
curl -s -G --data-urlencode 'query=up{job="node-ephemeral"}' "$P/api/v1/query" \
  | tr ',' '\n' | grep -oE '"server":"[^"]+"' | cut -d'"' -f4 | sed 's/^/  /' | sort -u
