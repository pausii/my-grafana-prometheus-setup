#!/usr/bin/env bash
# Assemble bootstrap.sh from three parts into ONE file.
#
# Why split while writing but joined while using: ephemeral servers
# are often created through cloud-init or a single command, and
# shipping three files there only adds ways to fail. The sources
# stay separate so they remain readable.
set -euo pipefail
cd "$(dirname "$0")"
cat _header.sh detect.sh bootstrap-main.sh > bootstrap.sh
chmod +x bootstrap.sh
bash -n bootstrap.sh
echo "bootstrap.sh assembled — $(wc -l < bootstrap.sh) lines"
