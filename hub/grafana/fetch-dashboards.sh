#!/usr/bin/env bash
# ============================================================
# Download community dashboards not vendored in this repo
# ============================================================
# "Node Exporter Full" (grafana.com dashboard 1860) is community
# work, not part of this project. It is downloaded at install time
# rather than copied into the repo, so ownership stays clear and
# this repo does not carry 360 KB belonging to someone else.
set -euo pipefail
cd "$(dirname "$0")/provisioning/dashboards"

echo "Downloading Node Exporter Full (1860)..."
curl -fsSL https://grafana.com/api/dashboards/1860/revisions/latest/download \
  -o node-exporter-full.json

# File provisioning rejects a dashboard that still carries an "id".
python3 - <<'PY'
import json
d = json.load(open('node-exporter-full.json'))
d['id'] = None
json.dump(d, open('node-exporter-full.json', 'w'), indent=1)
print(f"  {d['title']} — {len(d.get('panels', []))} panels, uid {d.get('uid')}")
PY
echo "Done. Grafana picks it up within 30 seconds."
