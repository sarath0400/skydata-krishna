#!/usr/bin/env bash
# 6. Instance template (from golden image) + MIG + Compute Autoscaler.
#    Autoscaler numbers match SkyStudio exactly:
#      min=2  max=10  singleInstanceAssignment=1.0  coolDown=300s  scaleIn=1 per 900s
#    Signal: custom.googleapis.com/github/active_jobs
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

TEMPLATE="github-runner-$(date -u +%Y%m%d%H%M)"

# instance SA needs to read github-pat + write logs
SA_NAME="mig-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
gcloud iam service-accounts create "$SA_NAME" --display-name="mig github runner" 2>/dev/null || true
for role in roles/secretmanager.secretAccessor roles/logging.logWriter; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$role" >/dev/null
done

# 1. instance template from the golden image, startup-script + GitHub metadata baked in
gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --image-family="$IMAGE_FAMILY" --image-project="$PROJECT_ID" \
  --service-account="$SA_EMAIL" \
  --scopes=cloud-platform \
  --metadata="github-url=${GITHUB_URL},github-api-scope=${GITHUB_API_SCOPE}" \
  --metadata-from-file=startup-script=../instance-template/startup-script.sh

# 2. managed instance group, initial size = min
gcloud compute instance-groups managed create "$MIG_NAME" \
  --zone="$ZONE" --template="$TEMPLATE" --size=2

# 3. autoscaling on the active_jobs custom metric, 1 VM per active job
gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
  --zone="$ZONE" \
  --min-num-replicas=2 --max-num-replicas=10 \
  --cool-down-period=300 \
  --update-stackdriver-metric=custom.googleapis.com/github/active_jobs \
  --stackdriver-metric-single-instance-assignment=1.0 \
  --scale-in-control=max-scaled-in-replicas=1,time-window=900

echo "MIG '$MIG_NAME' live: min=2 max=10, scaling on active_jobs."
