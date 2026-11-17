# Screenshots

Five are in place. The rest are listed below for when the
situation that shows them comes round again.

## Present

| File | What it shows |
|---|---|
| `grafana-home.png` | The fixed-servers dashboard: four hosts up, CPU/memory/disk, trends, and the inventory table. The cores/RAM/disk values are blurred; the column headers are left readable so the shape of the table is still clear |
| `prometheus-targets.png` | All four targets UP, with the full label set per target |
| `prometheus-alerts.png` | Seven alert rules loaded across three groups, all inactive |
| `grafana-ephemeral.png` | The ephemeral dashboard with four rented workers pushing in: age, CPU/memory/disk, cumulative net in/out, the two network charts, push-path health, and the inventory table. Every IP address is blurred; city, provider and runtime are left readable |
| `grafana-netio.png` | The two network panels from that same dashboard, cropped out: throughput in and out per host, and the per-5-minute volume bars |

## Still to capture

Terminal output, so they need a manual screenshot — or just read
them as the fenced blocks already in the main README.

| File | Command |
|---|---|
| `promtool-test.png` | `docker exec prometheus promtool test rules /tmp/node_test.yml` |
| `ufw-bypass.png` | `curl` against a published container port that UFW never allowed |
| `quadlet-status.png` | `systemctl status node-exporter` on the Podman host |
| `push-endpoint-test.png` | the 401 / 403 / 404 / 400 sequence against the push endpoint |

## How the existing ones were made

Headless Chrome through puppeteer-core, logging in and capturing
the page. Three things that mattered:

**Do not use `fullPage`, and do not scroll.** Grafana virtualises
the dashboard — panels outside the viewport are removed from the
DOM. `fullPage` captures empty boxes, and scrolling to force
rendering unmounts the panels already drawn. Set a viewport tall
enough for the whole dashboard instead, then take an ordinary
viewport screenshot.

**Wait for the queries, not for the clock.** A fixed delay catches
Grafana mid-query and every panel renders blank. Wait until the
"Cancel" button disappears.

**`clip` is the same trap as `fullPage`.** Asking for a rectangle
makes Chrome re-render the page, and Grafana virtualises the panels
again — the crop comes out empty even though the coordinates are
right. Take the ordinary viewport screenshot and cut the rectangle
out of the PNG afterwards. `grafana-netio.png` is cut that way, from
panel rectangles read out of the DOM rather than guessed.

Column values are blurred the same way, found by locating the
column index from `[role=columnheader]` and applying the blur to
`[role=gridcell]` at that index — position in the data, not a
guessed rectangle in the image. Headers stay readable on purpose.

**IP addresses are masked in the DOM before the capture**, not
blurred in the image afterwards: a tree walker finds text nodes
matching an address pattern and wraps each match in a span with
`filter: blur(5px)`. No OCR, and the blur lands exactly on the
address rather than on a guessed rectangle.

Crop or blur anything that still shows a real address before
adding a new image here.
