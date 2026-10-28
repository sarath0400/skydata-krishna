#!/usr/bin/env bash
# 2. Create the Firestore database in native mode.
#    Collections (runner_pool_state / runner_job_state / processed_deliveries)
#    are created on first write by the webhook — no schema step needed.
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

if ! gcloud firestore databases describe --database="(default)" >/dev/null 2>&1; then
  gcloud firestore databases create --location="$REGION" --type=firestore-native
fi
echo "Firestore native DB ready in $REGION."
