#!/usr/bin/env bash
# ============================================================
# bootstrap.sh — enroll an ephemeral server into monitoring
# ============================================================
# PUSH model: this host SENDS its metrics outward. No port is
# opened, no firewall rule is needed, no SSH key is left behind,
# and nothing registers with the hub. That is why it works at any
# provider, including behind NAT.
#
# Two containers are started:
#   node_exporter     reads the machine, listens on 127.0.0.1 only
#   prometheus-agent  scrapes localhost and pushes to the hub
#
# Agent mode is Prometheus without query storage: it fetches and
# forwards. It keeps a disk-backed queue, so if the network drops,
# samples are held and resent rather than lost.
#
# The host's identity is detected automatically. The only thing
# you must supply is the push token.
#
# Usage:
#   bash bootstrap.sh --push-pass 'TOKEN'
#   bash bootstrap.sh --push-pass 'TOKEN' --dry-run   # detection only
#   bash bootstrap.sh --push-pass 'TOKEN' --city tokyo
#   bash bootstrap.sh --uninstall
set -euo pipefail

NODE_EXPORTER_VERSION=v1.12.1
PROMETHEUS_VERSION=v3.14.0
PUSH_URL="https://push.example.com/api/v1/write"
PUSH_USER="push"
DIR=/opt/monitoring-ephemeral
