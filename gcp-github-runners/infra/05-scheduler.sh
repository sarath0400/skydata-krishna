#!/usr/bin/env bash
# 5. Cloud Scheduler tick every minute -> POST <webhook_url>/metrics
#    (publishes queued_jobs / in_progress_jobs / active_jobs custom metrics).
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

URL=$(cat .webhook_url)

# dedicated SA to mint the OIDC token Scheduler sends
SA_NAME="scheduler-metrics"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts create "$SA_NAME" --display-name="runner metrics scheduler" 2>/dev/null || true

gcloud scheduler jobs create http "$SCHEDULER_JOB" \
  --location="$REGION" --schedule="* * * * *" \
  --uri="${URL}/metrics" --http-method=POST \
  --oidc-service-account-email="$SA_EMAIL" \
  2>/dev/null || \
gcloud scheduler jobs update http "$SCHEDULER_JOB" \
  --location="$REGION" --schedule="* * * * *" \
  --uri="${URL}/metrics" --http-method=POST \
  --oidc-service-account-email="$SA_EMAIL"

echo "Scheduler '$SCHEDULER_JOB' posting to ${URL}/metrics every minute."
