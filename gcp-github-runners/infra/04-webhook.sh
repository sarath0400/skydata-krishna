#!/usr/bin/env bash
# 4. Deploy the Cloud Run webhook receiver (gen2 function, entrypoint webhook_handler)
#    and grant its runtime service account the roles it needs.
#
# NOTE: GitHub must be able to POST to this endpoint, so it is deployed with public
# ingress (GitHub signs every request with github-webhook-secret; the receiver
# rejects any request whose HMAC signature does not match).
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

gcloud functions deploy "$WEBHOOK_SERVICE" \
  --gen2 --region="$REGION" --runtime=python312 \
  --source=../webhook --entry-point=webhook_handler \
  --trigger-http --allow-unauthenticated \
  --set-env-vars="GCP_PROJECT=${PROJECT_ID}" \
  --memory=256Mi --timeout=60s

# runtime service account (gen2 default = compute SA) needs Firestore + metrics + secrets
SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"
for role in roles/datastore.user roles/monitoring.metricWriter roles/secretmanager.secretAccessor; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA}" --role="$role" >/dev/null
done

URL=$(gcloud functions describe "$WEBHOOK_SERVICE" --gen2 --region="$REGION" --format='value(serviceConfig.uri)')
echo "Webhook deployed at: $URL"
echo "$URL" > .webhook_url
