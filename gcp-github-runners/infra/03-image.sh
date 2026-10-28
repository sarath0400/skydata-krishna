#!/usr/bin/env bash
# 3. Build the golden image: spin a builder VM, install docker+az+node+runner,
#    snapshot its disk into a reusable custom image, then delete the builder.
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

BUILDER="golden-runner-builder"
IMAGE_NAME="${IMAGE_FAMILY}-$(date -u +%Y%m%d-%H%M%S)"

# 1. builder VM (Ubuntu 22.04)
gcloud compute instances create "$BUILDER" \
  --zone="$ZONE" --machine-type=e2-medium \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud

# 2. wait for SSH, then run the install script as root
sleep 30
gcloud compute ssh "$BUILDER" --zone="$ZONE" --command="sudo bash -s" < ../image/install-runner-tools.sh

# 3. stop the VM (required before imaging), create the image, tag the family
gcloud compute instances stop "$BUILDER" --zone="$ZONE"
gcloud compute images create "$IMAGE_NAME" \
  --source-disk="$BUILDER" --source-disk-zone="$ZONE" \
  --family="$IMAGE_FAMILY"

# 4. cleanup builder
gcloud compute instances delete "$BUILDER" --zone="$ZONE" --quiet
echo "Golden image created: $IMAGE_NAME (family=$IMAGE_FAMILY)"
