#!/usr/bin/env bash
# 1. Create the 4 secrets in Secret Manager (same names as SkyStudio).
#    Prereq: follow ../GITHUB-APP-SETUP.md first to obtain the values below.
#
#    Set these env vars (or edit inline) before running:
#      GITHUB_PAT               classic PAT (admin:org for org scope / repo for repo scope)
#      GITHUB_WEBHOOK_SECRET    any long random string (also used on the GitHub webhook)
#      GITHUB_APP_ID            numeric App ID
#      GITHUB_APP_PRIVATE_KEY_FILE   path to the App's downloaded .pem
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

create_or_add () {  # name, value-from-stdin
  local name="$1"
  if ! gcloud secrets describe "$name" >/dev/null 2>&1; then
    gcloud secrets create "$name" --replication-policy=automatic
  fi
  gcloud secrets versions add "$name" --data-file=-
}

printf '%s' "${GITHUB_PAT:?set GITHUB_PAT}"                       | create_or_add github-pat
printf '%s' "${GITHUB_WEBHOOK_SECRET:?set GITHUB_WEBHOOK_SECRET}" | create_or_add github-webhook-secret

# App secrets are ORG-scope only. In repo scope they are not needed; store them
# only if you actually created a GitHub App (SCOPE=org).
if [ "$SCOPE" = "org" ]; then
  printf '%s' "${GITHUB_APP_ID:?set GITHUB_APP_ID}" | create_or_add github-app-id
  gcloud secrets create github-app-private-key --replication-policy=automatic 2>/dev/null || true
  gcloud secrets versions add github-app-private-key \
    --data-file="${GITHUB_APP_PRIVATE_KEY_FILE:?set GITHUB_APP_PRIVATE_KEY_FILE}"
  echo "Secrets stored: github-pat, github-webhook-secret, github-app-id, github-app-private-key"
else
  echo "Secrets stored: github-pat, github-webhook-secret  (repo scope — App secrets skipped)"
fi
