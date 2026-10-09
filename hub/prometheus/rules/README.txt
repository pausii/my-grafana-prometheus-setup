Alert rules live here. Prometheus loads every *.yml in this
directory (see rule_files in prometheus.yml).

Validate before reloading:
  docker exec prometheus promtool check rules /etc/prometheus/rules/node.yml

Reload without restarting, so no data is lost:
  curl -X POST http://127.0.0.1:9090/-/reload
