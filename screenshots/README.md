# Screenshots

Drop images here and they will render in the main README, which
already references these filenames.

Suggested order — each one shows something the text claims, so a
reader can check the claim instead of taking my word for it.

| File | What to capture | Where |
|---|---|---|
| `grafana-home.png` | The Fixed Servers dashboard, full page | Grafana home after login |
| `grafana-ephemeral.png` | Ephemeral Servers dashboard with a few hosts pushing | Grafana → folder Ephemeral |
| `grafana-netio.png` | The netIn/netOut totals and the per-5-minute bar chart | Ephemeral dashboard, lower half |
| `prometheus-targets.png` | All targets UP | `http://localhost:9090/targets` |
| `prometheus-alerts.png` | Alert rules loaded, all inactive | `http://localhost:9090/alerts` |
| `promtool-test.png` | `SUCCESS` from the alert unit test | `docker exec prometheus promtool test rules /tmp/node_test.yml` |
| `ufw-bypass.png` | A published container port answering from outside while UFW denies it | terminal, see "Docker punches through UFW" |
| `quadlet-status.png` | `Loaded: ...container; generated` and the real process in the cgroup | `systemctl status node-exporter` on the Podman host |
| `push-endpoint-test.png` | 401 / 403 / 404 / 400 responses from the push endpoint | terminal, see "The push endpoint" |

Keep them reasonably sized — 1600px wide is plenty, and PNG
compresses screenshots better than JPEG.

Crop or blur anything that shows a real address, hostname or
token. The whole point of this repo is that it carries none.
