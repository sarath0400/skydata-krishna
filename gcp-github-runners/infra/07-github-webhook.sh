#!/usr/bin/env bash
# 7. Point the GitHub org (or repo) webhook at the Cloud Run URL.
#    Sends only workflow_job events, JSON, signed with github-webhook-secret.
#    Requires: gh CLI authenticated (gh auth login), and GITHUB_WEBHOOK_SECRET set
#    to the SAME value stored in Secret Manager (infra/01-secrets.sh).
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

URL=$(cat .webhook_url)
: "${GITHUB_WEBHOOK_SECRET:?set GITHUB_WEBHOOK_SECRET to the same value as the secret}"

gh api -X POST "/${GITHUB_WEBHOOK_TARGET_LEVEL}/hooks" \
  -f name=web \
  -F active=true \
  -f events[]=workflow_job \
  -f config[url]="$URL" \
  -f config[content_type]=json \
  -f config[secret]="$GITHUB_WEBHOOK_SECRET"

echo "Webhook created on ${GITHUB_WEBHOOK_TARGET_LEVEL} -> $URL (workflow_job only)"
