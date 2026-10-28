#!/usr/bin/env bash
# Per-VM startup-script (runs on EVERY MIG runner boot). Everything is already
# installed in the golden image, so this only registers the agent and starts it.
#
# Contract matches SkyStudio's MIG startup-script:
#   1. pull github-pat from Secret Manager
#   2. exchange it for a one-time runner registration token
#   3. ./config.sh with labels self-hosted,Linux,X64,gcp,mig  (runnergroup Default)
#   4. install + start the systemd service  -> actions.runner.*
#
# GITHUB_SCOPE is baked in via instance-template metadata (org "orgs/<org>" or
# repo "repos/<owner>/<repo>"). This demo registers at repo scope.
set -euxo pipefail

# metadata set on the instance template (see infra/06-mig-autoscaler.sh)
META="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
GITHUB_URL=$(curl -s -H "Metadata-Flavor: Google" "$META/github-url")     # https://github.com/<owner>/<repo>
GITHUB_API_SCOPE=$(curl -s -H "Metadata-Flavor: Google" "$META/github-api-scope")  # repos/<owner>/<repo>

cd /opt/actions-runner

# 1. registration PAT from Secret Manager
PAT=$(gcloud secrets versions access latest --secret=github-pat)

# 2. exchange PAT for a one-time registration token
REG_TOKEN=$(curl -fsSL -X POST \
  -H "Authorization: token ${PAT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/${GITHUB_API_SCOPE}/actions/runners/registration-token" \
  | jq -r .token)

if [ -z "${REG_TOKEN}" ] || [ "${REG_TOKEN}" = "null" ]; then
  echo "ERROR: Could not get runner registration token from GitHub API"
  exit 1
fi

# 3. configure (unique name per VM via hostname)
sudo -u runner ./config.sh \
  --url "${GITHUB_URL}" \
  --token "${REG_TOKEN}" \
  --name "$(hostname)" \
  --labels self-hosted,Linux,X64,gcp,mig \
  --runnergroup Default \
  --unattended \
  --replace

# 4. install + start as a systemd service that survives reboots
./svc.sh install runner
./svc.sh start
echo "Listening for Jobs"
