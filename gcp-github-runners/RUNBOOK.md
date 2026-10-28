# GCP GitHub Runners — Runbook v1

What to check when self-hosted runner jobs are stuck or failing.
Modelled on SkyPoint's L1 runbook (`l1-runbook/applications/github-actions/CLAUDE.md`).

## Where things live

| Thing | Value |
|---|---|
| GCP project | `krishna-504204` (region `us-central1`, zone `us-central1-a`) |
| Repo (runner scope) | `sarath0400/skydata-krishna` — repo-level runners |
| Webhook receiver (Cloud Run) | `github-runner-webhook` → `https://github-runner-webhook-804360298904.us-central1.run.app` |
| Metrics trigger | Cloud Scheduler `github-runner-metrics` (every minute → `POST /metrics`) |
| State | Firestore: `processed_deliveries`, `runner_job_state`, `runner_pool_state` (doc `Default\|gcp,linux,self-hosted,x64`) |
| Secrets | Secret Manager: `github-pat` (VM registration), `github-webhook-secret` (signature check) |
| Runner VMs | MIG `mig-github-runners` (min 2, max 10), template `github-runner-202610161`, image `golden-runner-20261016` (runner 2.338.0) |
| Scaling signal | `custom.googleapis.com/github/active_jobs` (1 VM per active job, scale-in 1 VM / 15 min) |
| Runner labels | `self-hosted, Linux, X64, gcp, mig` |
| Alerts (email channel `RadhaKrishna`) | `Radhakrishna` = job queued > 10 min · `krishna krishna` = `active_jobs` missing 5 min · `Ram krishna` = receiver non-2xx |
| Code | `gcp-github-runners/` in this repo (`infra/00…07`, `webhook/main.py`, `instance-template/startup-script.sh`) |

## The 4 stops (check in order, stop at the first one that looks wrong)

| # | Where | Healthy looks like | If wrong |
|---|---|---|---|
| 1 | GitHub → repo **Settings → Webhooks → Recent Deliveries** | `workflow_job` deliveries with 200 | Not sent / failing → webhook URL or secret (see table below) |
| 2 | GCP **Logs Explorer**: `resource.type="cloud_run_revision" resource.labels.service_name="github-runner-webhook"` | `POST 200` from `GitHub-Hookshot` + Scheduler `POST /metrics` every minute | 401 → secret mismatch · 5xx → receiver bug/crash |
| 3 | GCP **Firestore** | delivery IDs in `processed_deliveries` match Stop 1; pool doc counts move | Missing → receiver answers but does not save |
| 4 | GCP **Metrics Explorer** → `active_jobs` | rises when jobs queue, MIG target follows | Flat/absent → Scheduler or `/metrics` broken |

Tip: Logs Explorer is flooded by Ops Agent noise — always filter by `resource.type` + service name.

## Triage by symptom

| Symptom | Check first | Likely cause → fix |
|---|---|---|
| Job **Queued < ~5 min** while other jobs are running | MIG target size vs VMs | **Normal** — new VM takes ~2–3 min to boot and register. Wait. |
| Job **Queued > 10 min** (Alert `Radhakrishna`) | Stops 1→4, then GitHub **Settings → Actions → Runners** | See rows below |
| Deliveries show **401** | Stop 2 log `Signature mismatch` | `github-webhook-secret` differs from the GitHub webhook secret → set both to the same value |
| Deliveries **failing / not sent** | Stop 1 | Webhook URL wrong or webhook disabled → fix URL in repo Settings → Webhooks |
| New VMs boot but **never appear** in GitHub runners list | VM **serial port output** (see commands) | `curl: (22) ... 401/403` on `registration-token` → `github-pat` expired or lacks scope → rotate PAT. Runner version older than GitHub minimum → rebuild image (Oct 16 incident). |
| Runners **Idle** in GitHub but job still Queued | Compare runner labels with workflow `runs-on:` | Label mismatch → fix `runs-on:` or the `--labels` in `startup-script.sh` |
| MIG **not growing** while jobs queue | Stop 4 (`active_jobs`) | Scheduler paused/failing or `/metrics` erroring → check Cloud Scheduler run history + Stop 2 |
| MIG at **10 VMs**, jobs still queue | Firestore pool counts | Real capacity limit (max 10) → raise max, or wait |
| Job **runs then fails** | The job's own log (`Error:` line) | Not a runner problem — workflow/code issue (e.g. missing `package-lock.json`, missing secret) |

## First commands (Cloud Shell, read-only)

```bash
# MIG size and stability
gcloud compute instance-groups managed describe mig-github-runners \
  --zone=us-central1-a --project=krishna-504204 \
  --format='value(targetSize,status.isStable)'

# Which VMs exist right now
gcloud compute instance-groups managed list-instances mig-github-runners \
  --zone=us-central1-a --project=krishna-504204

# Did a VM register? (look for "Listening for Jobs" or a curl 401/403)
gcloud compute instances get-serial-port-output <vm-name> \
  --zone=us-central1-a --project=krishna-504204 \
  | grep -E 'Listening for Jobs|registration|curl: \(22\)'

# Recent receiver logs
gcloud logging read \
  'resource.type=cloud_run_revision AND resource.labels.service_name=github-runner-webhook' \
  --project=krishna-504204 --limit=30 --freshness=30m \
  --format='value(timestamp,httpRequest.status,httpRequest.requestUrl)'
```

Note: `startup-script.sh` uses `curl -f` with `set -e`, so on a bad PAT the script stops at the curl error and the
`ERROR: Could not get runner registration token` line may never print — grep for `curl: (22)` too.

## Known issues

| # | Issue | Detect | Action |
|---|---|---|---|
| 1 | Runner version below GitHub minimum stops registration (Oct 16) | VMs boot, no runners in GitHub | Rebuild golden image with a current runner, new template, rolling replace. Keep `RUNNER_VERSION` in `image/install-runner-tools.sh` equal to the live image. |
| 2 | PAT expiry is silent (SkyPoint incident 2026-05-05) | Only new VMs fail; existing runners keep working | Alert `Radhakrishna` (queued > 10 min) catches it. Set a calendar reminder before PAT expiry. |
| 3 | Build Docker Image job fails `Login to ACR: Username and password required` | Deploy Demo run | No registry credentials — planned fix with OIDC (D14–D15). Not a runner problem. |
| 4 | Scaling signal is a 1-minute snapshot | Very short jobs never show in `active_jobs` | Expected — not a fault. |

## Change rules

- Every change to this platform goes through a branch + PR into `develop`.
- After changing the live system by hand, update the code here in the same week (avoid drift).
- Rollback: revert the PR; for image/template changes, roll the MIG back to the previous template.
