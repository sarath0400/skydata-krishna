#!/usr/bin/env bash
# 0. Select project + enable every API the stack needs.
set -euxo pipefail
cd "$(dirname "$0")" && source ./config.env

gcloud config set project "$PROJECT_ID"

gcloud services enable \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudscheduler.googleapis.com \
  compute.googleapis.com \
  firestore.googleapis.com \
  secretmanager.googleapis.com \
  monitoring.googleapis.com
echo "APIs enabled."
