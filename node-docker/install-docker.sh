#!/usr/bin/env bash
# ============================================================
# Install Docker Engine + Compose plugin (Ubuntu)
# ============================================================
set -euo pipefail

if command -v docker >/dev/null 2>&1; then
  echo "Docker already installed:"; docker --version; exit 0
fi

echo "== 1/4 Prerequisites =="
sudo apt-get update
sudo apt-get install -y ca-certificates curl

echo
echo "== 2/4 Docker's official GPG key =="
# apt uses this to verify that packages really come from Docker,
# and not from a mirror that has been tampered with.
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
     -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo
echo "== 3/4 Add the repository =="
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

echo
echo "== 4/4 Install =="
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
     docker-buildx-plugin docker-compose-plugin

echo
docker --version
docker compose version
echo
echo "Done. Next: docker compose up -d"
