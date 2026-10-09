
# ============================================================
# Main body
# ============================================================

SERVER="" COUNTRY="" CITY="" PROVIDER="" PUSH_PASS=""
UNINSTALL=0 DRYRUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push-pass) PUSH_PASS="$2"; shift 2 ;;
    --server)    SERVER="$2";    shift 2 ;;
    --country)   COUNTRY="$2";   shift 2 ;;
    --city)      CITY="$2";      shift 2 ;;
    --provider)  PROVIDER="$2";  shift 2 ;;
    --push-url)  PUSH_URL="$2";  shift 2 ;;
    --push-user) PUSH_USER="$2"; shift 2 ;;
    --dry-run)   DRYRUN=1;       shift ;;
    --uninstall) UNINSTALL=1;    shift ;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
done

if [[ $UNINSTALL -eq 1 ]]; then
  echo "== Stopping and removing =="
  docker rm -f node-exporter prometheus-agent 2>/dev/null || true
  rm -rf "$DIR"
  echo "Done. Metrics stop flowing; the series go stale on the hub"
  echo "within a few minutes. Nothing to clean up there."
  exit 0
fi

[[ -n "$PUSH_PASS" ]] || { echo "STOP: --push-pass is required."; exit 1; }

# ---------- detection ----------
echo "== Detecting host identity =="
IP_FAMILY=""
detect_public_ip            # sets PUBLIC_IP and IP_FAMILY
RDNS=$(detect_rdns "$PUBLIC_IP")
[[ -n "$PROVIDER" ]] || PROVIDER=$(detect_provider)

ZONE=$(detect_zone)
PROVIDER_SRC=""
GEO_CC="" GEO_CITY="" GEO_VOTES=""
COUNTRY_SRC="" CITY_SRC=""

# Country and datacenter code come from the zone when its format is
# recognised (xx-yyy1), since that is the provider's own term.
DC=""
if [[ "$ZONE" =~ ^([a-z]{2})-([a-z]{3})[0-9]*$ ]]; then
  [[ -n "$COUNTRY" ]] || { COUNTRY="${BASH_REMATCH[1]}"; COUNTRY_SRC="zone $ZONE"; }
  DC="${BASH_REMATCH[2]}"
fi

# Geo also runs when the provider is still unknown, because its
# response carries the ASN owner's name.
if [[ -z "$CITY" || -z "$COUNTRY" || -z "$DC" || "$PROVIDER" == "unknown" ]]; then
  GEO_ASN_ORG=""
  if detect_geo; then
    if [[ "$PROVIDER" == "unknown" && -n "$GEO_ASN_ORG" ]]; then
      PROVIDER=$(provider_from_asn "$GEO_ASN_ORG")
      [[ "$PROVIDER" != "unknown" ]] && PROVIDER_SRC="ASN: ${GEO_ASN_ORG}"
    fi
    [[ -z "$COUNTRY" ]] && { COUNTRY="$GEO_CC"; COUNTRY_SRC="geo-IP, votes: ${GEO_VOTES}"; }
    [[ -z "$CITY"    ]] && { CITY=$(slug "$GEO_CITY"); CITY_SRC="geo-IP"; }
    # Rough DC code: first three letters of the city. It will not
    # always match the provider's official code — use --server for
    # an exact name.
    [[ -z "$DC" ]] && DC=$(printf '%s' "$CITY" | tr -d '-' | cut -c1-3)
  fi
fi

[[ -n "$CITY"    ]] || { CITY="${DC:-unknown}"; CITY_SRC="zone code"; }
[[ -n "$COUNTRY" ]] || { COUNTRY="xx"; COUNTRY_SRC="detection failed"; }
[[ -n "$DC"      ]] || DC="xxx"

# The server name is its public IP address.
#
# For short-lived hosts this beats sequential numbering: unique
# with no coordination, no need to ask the hub, no race when
# several are created at once, and immediately usable to SSH in
# when something needs checking.
#
# The <country>-<dc>-<nn> scheme is for FIXED servers, whose names
# are chosen deliberately.
if [[ -z "$SERVER" ]]; then
  SERVER="${PUBLIC_IP:-unknown}"
fi

cat <<INFO

  public IP  : ${PUBLIC_IP:-unknown}   ($([[ "${IP_FAMILY}" == "-4" ]] && echo IPv4 || echo IPv6))
  rDNS       : ${RDNS:-none}
  DMI vendor : $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo '-')
  zone       : ${ZONE:-not detected}
  ------------------------------------------------
  provider   : ${PROVIDER}${PROVIDER_SRC:+   (from ${PROVIDER_SRC})}
  country    : ${COUNTRY}${COUNTRY_SRC:+   (from ${COUNTRY_SRC})}
  city       : ${CITY}${CITY_SRC:+   (from ${CITY_SRC})}
  server     : ${SERVER}   (= public IP)
  ------------------------------------------------
INFO

if [[ "$PROVIDER" == "unknown" || "$COUNTRY" == "xx" ]]; then
  echo "  WARNING: some fields were not detected. Override with"
  echo "  --provider / --country / --city / --server as needed."
  echo
fi

if [[ $DRYRUN -eq 1 ]]; then
  echo "  (--dry-run: stopping here, nothing changed)"
  exit 0
fi

echo "== 1/5 Ensure Docker is present =="
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found, installing via the official script..."
  curl -fsSL https://get.docker.com | sh
fi
docker --version

echo
echo "== 2/5 Write the agent configuration =="
mkdir -p "$DIR/data"
cat > "$DIR/agent.yml" <<EOF
global:
  scrape_interval: 15s
  external_labels:
    monitor: 'ephemeral-agent'

scrape_configs:
  # job "node-ephemeral" — NOT "node".
  # The job name is the primary separator: every fixed-server alert
  # rule and dashboard filters on job="node", so this host is
  # automatically outside their scope.
  - job_name: 'node-ephemeral'
    static_configs:
      - targets: ['127.0.0.1:9100']
        labels:
          server: '${SERVER}'
          country: '${COUNTRY}'
          city: '${CITY}'
          provider: '${PROVIDER}'
          environment: 'ephemeral'
          runtime: 'docker'
    relabel_configs:
      - source_labels: [server]
        target_label: instance

remote_write:
  - url: '${PUSH_URL}'
    basic_auth:
      username: '${PUSH_USER}'
      password: '${PUSH_PASS}'
    queue_config:
      # Survives disconnection: samples are held and resent rather
      # than dropped.
      capacity: 10000
      max_samples_per_send: 2000
      max_shards: 10
EOF
# This file holds the push token, so it must not be 644. But the
# prom/prometheus image runs as "nobody" (uid 65534), not root —
# with mode 600 owned by root, the container just restart-loops
# with "permission denied". Keep 600, change the owner.
chown 65534:65534 "$DIR/agent.yml"
chmod 600 "$DIR/agent.yml"
chown -R 65534:65534 "$DIR/data"
echo "  -> $DIR/agent.yml (600, owned by uid 65534/nobody)"

echo
echo "== 3/5 Start node_exporter =="
# Listens on 127.0.0.1 ONLY. The agent is on the same machine, so
# nothing needs to reach it from outside. That removes the entire
# firewall question.
docker rm -f node-exporter >/dev/null 2>&1 || true
docker run -d --name node-exporter --restart unless-stopped \
  --network host --pid host -v /:/host:ro,rslave \
  "prom/node-exporter:${NODE_EXPORTER_VERSION}" \
  --path.rootfs=/host \
  --web.listen-address=127.0.0.1:9100 \
  '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/docker/.+|var/lib/containers/.+)($|/)' \
  '--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|procfs|pstore|securityfs|selinuxfs|squashfs|sysfs|tracefs)$' \
  >/dev/null
echo "  node-exporter running on 127.0.0.1:9100"

echo
echo "== 4/5 Start Prometheus in agent mode =="
docker rm -f prometheus-agent >/dev/null 2>&1 || true
docker run -d --name prometheus-agent --restart unless-stopped \
  --network host \
  -v "$DIR/agent.yml:/etc/prometheus/agent.yml:ro" \
  -v "$DIR/data:/agent" \
  "prom/prometheus:${PROMETHEUS_VERSION}" \
  --config.file=/etc/prometheus/agent.yml \
  --agent \
  --storage.agent.path=/agent \
  --web.listen-address=127.0.0.1:9092 \
  >/dev/null
echo "  prometheus-agent running on 127.0.0.1:9092"

echo
echo "== 5/5 Verify =="
sleep 5
echo "--- local metrics ---"
if curl -fsS http://127.0.0.1:9100/metrics -o /tmp/m.txt 2>/dev/null; then
  echo "  node_exporter: $(grep -c '^node_' /tmp/m.txt) metrics"
else
  echo "  node_exporter FAILED"
fi
rm -f /tmp/m.txt

echo "--- did the push succeed? ---"
# prometheus_remote_storage_samples_total counts samples ACTUALLY
# delivered to the hub. Do not confuse it with ..._samples_in_total,
# which only counts samples entering the queue.
#
# The agent replays its WAL before sending anything; on a slow
# machine that can take 20 seconds or more. Waiting a fixed time
# reports "failed" when it merely has not started yet, so wait for
# evidence instead, with a cap.
SENT=0; FAILED=0
for i in $(seq 1 12); do
  AGENT=$(curl -fsS http://127.0.0.1:9092/metrics 2>/dev/null || true)
  SENT=$(printf '%s\n' "$AGENT" | awk '/^prometheus_remote_storage_samples_total\{/{s+=$2} END{printf "%d", s+0}')
  FAILED=$(printf '%s\n' "$AGENT" | awk '/^prometheus_remote_storage_samples_failed_total\{/{f+=$2} END{printf "%d", f+0}')
  [[ "$SENT" -gt 0 || "$FAILED" -gt 0 ]] && break
  printf '  waiting for the agent to send... (%d/12)\r' "$i"
  sleep 5
done
echo
echo "  samples sent   : $SENT"
echo "  samples failed : $FAILED"

if [[ "$SENT" -gt 0 ]]; then
  echo
  echo "-------------------------------------------"
  echo "SUCCESS. ${SERVER} is pushing metrics to the hub."
  echo "Grafana -> folder Ephemeral -> Ephemeral Servers"
  echo "-------------------------------------------"
else
  echo
  echo "No samples sent yet. Check:"
  echo "  docker logs prometheus-agent --tail 30"
  exit 1
fi
