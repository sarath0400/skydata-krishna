# skydata Runner Autoscaler — exact replica of SkyStudio's GCP self-hosted runner pool

This reproduces SkyStudio's CI runner infrastructure 1:1 on a personal GCP project:

```
GitHub workflow_job webhook  (HMAC-SHA256, secret = github-webhook-secret)
   │
   ▼
Cloud Run: github-runner-webhook   (Python 3.12, entrypoint webhook_handler)
   │   reads secrets: github-app-id, github-app-private-key, github-pat, github-webhook-secret
   │   auth to GitHub: GitHub App (primary); github-pat used for cross-checks
   ▼
Firestore (native mode)
   runner_pool_state / "<group>|<sorted,labels>"   { queued_count, in_progress_count, updated_at }
   runner_job_state        (one doc per workflow_job id — state machine)
   processed_deliveries    (one doc per X-GitHub-Delivery — idempotency)
   │
   ▼
Cloud Scheduler: github-runner-metrics  (* * * * *)  → POST /metrics
   publishes 3 custom metrics:
     custom.googleapis.com/github/queued_jobs
     custom.googleapis.com/github/in_progress_jobs
     custom.googleapis.com/github/active_jobs      ← AUTOSCALER SIGNAL
   │
   ▼
Compute Autoscaler: autoscaler-github-runners
   min=2, max=10, singleInstanceAssignment=1.0, coolDown=300s, scaleIn=1 per 900s
   │
   ▼
MIG: mig-github-runners   (instance template built from a golden image)
   golden image has docker + az CLI + node + the runner tarball preinstalled
   each VM startup-script:
     1. pull github-pat from Secret Manager
     2. POST /orgs|repos/.../actions/runners/registration-token
     3. ./config.sh --labels self-hosted,Linux,X64,gcp,mig --runnergroup Default
     4. ./svc.sh install && ./svc.sh start   → systemd actions.runner.*
     5. agent long-polls GitHub, picks up jobs whose labels ⊆ {self-hosted,Linux,X64,gcp,mig}
```

## Exact deploy order (run the numbered scripts under infra/)

| # | Step | Script |
|---|---|---|
| 0 | Set project + enable APIs | `infra/00-apis.sh` |
| 1 | GitHub App + PAT + webhook secret → Secret Manager | `infra/01-secrets.sh` (after GITHUB-APP-SETUP.md) |
| 2 | Firestore native + indexes | `infra/02-firestore.sh` |
| 3 | Build the golden image (docker+az+node+runner) | `infra/03-image.sh` |
| 4 | Deploy Cloud Run webhook receiver | `infra/04-webhook.sh` |
| 5 | Cloud Scheduler → /metrics every minute | `infra/05-scheduler.sh` |
| 6 | Instance template + MIG + autoscaler | `infra/06-mig-autoscaler.sh` |
| 7 | Point the GitHub org/repo webhook at the Cloud Run URL | `infra/07-github-webhook.sh` |

## Layout

```
skydata-runner-autoscaler/
├── webhook/                     Cloud Run webhook receiver (Python 3.12)
│   ├── main.py                  entrypoint: webhook_handler
│   └── requirements.txt
├── image/
│   └── install-runner-tools.sh  golden-image provisioning (docker+az+node+runner)
├── instance-template/
│   └── startup-script.sh        per-VM boot: register runner + start systemd service
├── infra/                       numbered gcloud provisioning scripts (deploy order above)
└── GITHUB-APP-SETUP.md          how to create the GitHub App + PAT + webhook secret
```

All resource names, labels, Firestore field names, metric names, and autoscaler
numbers match the SkyStudio architecture exactly.
