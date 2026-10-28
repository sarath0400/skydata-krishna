#!/usr/bin/env bash
# Golden-image provisioning — runs ONCE on a builder VM, then we snapshot its disk
# into a custom image. Every MIG runner VM boots from this image with EVERYTHING
# already installed, so the per-boot startup-script only has to register the runner.
#
# Installs: docker, Azure CLI, Node.js 20, jq, and the GitHub Actions runner tarball
# unpacked at /opt/actions-runner (owned by the 'runner' user).
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
RUNNER_VERSION="2.338.0"

# --- base packages ---
apt-get update
apt-get install -y curl tar jq git ca-certificates gnupg lsb-release

# --- Docker (build-image job runs `docker build`/`push`) ---
apt-get install -y docker.io
systemctl enable docker

# --- Azure CLI (deploy job runs `az webapp ...`) ---
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# --- Node.js 20 (quality job; also lets setup-node use the preinstalled runtime) ---
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# --- dedicated non-root user to run the agent ---
id -u runner &>/dev/null || useradd -m -s /bin/bash runner
usermod -aG docker runner

# --- GitHub Actions runner tarball (unpacked, NOT yet configured) ---
mkdir -p /opt/actions-runner
cd /opt/actions-runner
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
tar xzf runner.tar.gz && rm runner.tar.gz
./bin/installdependencies.sh
chown -R runner:runner /opt/actions-runner

echo "Golden image tooling installed: docker + az + node20 + runner ${RUNNER_VERSION}"
