"""
github-runner-webhook — Cloud Run receiver (Python 3.12), entrypoint: webhook_handler

Two responsibilities (same as SkyStudio's live service):

  1. POST /            GitHub `workflow_job` webhook.
                       - verify X-Hub-Signature-256 (HMAC-SHA256, github-webhook-secret)
                       - dedupe by X-GitHub-Delivery  (processed_deliveries)
                       - drive the per-job state machine (runner_job_state)
                       - update per-pool counters (runner_pool_state)

  2. POST /metrics     Cloud Scheduler tick (every minute).
                       - read every runner_pool_state doc
                       - publish 3 custom metrics:
                           custom.googleapis.com/github/queued_jobs
                           custom.googleapis.com/github/in_progress_jobs
                           custom.googleapis.com/github/active_jobs   <- autoscaler signal

Firestore doc-ID for a pool: "<runner_group>|<sorted,comma,labels>"  (labels lowercased + sorted)
e.g. workflow declares [self-hosted, Linux, X64, gcp]  ->  "Default|gcp,linux,mig,self-hosted,x64"
"""

import hashlib
import hmac
import os
import time

import functions_framework
from google.cloud import firestore, monitoring_v3
from google.cloud import secretmanager

PROJECT_ID = os.environ["GCP_PROJECT"]

_db = firestore.Client(project=PROJECT_ID)
_sm = secretmanager.SecretManagerServiceClient()
_mon = monitoring_v3.MetricServiceClient()

_secret_cache: dict[str, str] = {}


def _secret(name: str) -> str:
    """Read latest version of a Secret Manager secret (cached per instance)."""
    if name not in _secret_cache:
        path = f"projects/{PROJECT_ID}/secrets/{name}/versions/latest"
        _secret_cache[name] = _sm.access_secret_version(name=path).payload.data.decode()
    return _secret_cache[name]


# ----------------------------------------------------------------------------
# Signature verification
# ----------------------------------------------------------------------------
def _verify_signature(body: bytes, header_sig: str | None) -> bool:
    if not header_sig:
        return False
    secret = _secret("github-webhook-secret").encode()
    expected = "sha256=" + hmac.new(secret, body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header_sig)


# ----------------------------------------------------------------------------
# Pool doc-ID: "<group>|<sorted,labels>"
# ----------------------------------------------------------------------------
def _pool_id(job: dict) -> str:
    group = job.get("runner_group_name") or "Default"
    labels = sorted(lbl.lower() for lbl in job.get("labels", []))
    return f"{group}|{','.join(labels)}"


# ----------------------------------------------------------------------------
# State machine: queued -> in_progress -> completed
# Deltas are applied to runner_pool_state inside a transaction so redelivery /
# out-of-order events can't corrupt the counters.
# ----------------------------------------------------------------------------
@firestore.transactional
def _apply(txn, job_id: str, pool_id: str, new_state: str):
    job_ref = _db.collection("runner_job_state").document(str(job_id))
    pool_ref = _db.collection("runner_pool_state").document(pool_id)

    snap = job_ref.get(transaction=txn)
    prev_state = snap.get("state") if snap.exists else None
    if prev_state == new_state:
        return  # duplicate / no-op

    pool_snap = pool_ref.get(transaction=txn)
    queued = (pool_snap.get("queued_count") or 0) if pool_snap.exists else 0
    running = (pool_snap.get("in_progress_count") or 0) if pool_snap.exists else 0

    # remove effect of previous state
    if prev_state == "queued":
        queued -= 1
    elif prev_state == "in_progress":
        running -= 1
    # add effect of new state
    if new_state == "queued":
        queued += 1
    elif new_state == "in_progress":
        running += 1
    # completed contributes nothing

    txn.set(
        pool_ref,
        {
            "queued_count": max(0, queued),
            "in_progress_count": max(0, running),
            "updated_at": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    if new_state == "completed":
        txn.delete(job_ref)
    else:
        txn.set(job_ref, {"state": new_state, "pool_id": pool_id,
                          "updated_at": firestore.SERVER_TIMESTAMP})


def _handle_workflow_job(payload: dict, delivery_id: str) -> str:
    # idempotency: existence of the delivery doc means "already processed"
    del_ref = _db.collection("processed_deliveries").document(delivery_id)
    if del_ref.get().exists:
        return f"Duplicate delivery {delivery_id}"
    del_ref.set({"seen_at": firestore.SERVER_TIMESTAMP})

    action = payload.get("action")            # queued | in_progress | completed
    job = payload.get("workflow_job", {})
    job_id = job.get("id")
    if action not in ("queued", "in_progress", "completed") or job_id is None:
        return "Ignored (not a job state change)"

    pool_id = _pool_id(job)
    _apply(_db.transaction(), job_id, pool_id, action)

    pool = _db.collection("runner_pool_state").document(pool_id).get()
    q = pool.get("queued_count") or 0
    r = pool.get("in_progress_count") or 0
    return f"Pool {pool_id}: queued={q}, in_progress={r}"


# ----------------------------------------------------------------------------
# Metrics publishing (Cloud Scheduler -> /metrics)
# ----------------------------------------------------------------------------
def _publish_metric(metric_type: str, value: int, now_s: int):
    series = monitoring_v3.TimeSeries()
    series.metric.type = f"custom.googleapis.com/github/{metric_type}"
    series.resource.type = "global"
    series.resource.labels["project_id"] = PROJECT_ID
    point = monitoring_v3.Point(
        {"interval": {"end_time": {"seconds": now_s}}, "value": {"int64_value": value}}
    )
    series.points = [point]
    _mon.create_time_series(
        name=f"projects/{PROJECT_ID}", time_series=[series]
    )


def _publish_all_metrics() -> str:
    queued = in_progress = 0
    for doc in _db.collection("runner_pool_state").stream():
        d = doc.to_dict()
        queued += d.get("queued_count", 0)
        in_progress += d.get("in_progress_count", 0)
    active = queued + in_progress

    now_s = int(time.time())
    _publish_metric("queued_jobs", queued, now_s)
    _publish_metric("in_progress_jobs", in_progress, now_s)
    _publish_metric("active_jobs", active, now_s)
    return f"metrics: queued={queued} in_progress={in_progress} active={active}"


# ----------------------------------------------------------------------------
# Entrypoint
# ----------------------------------------------------------------------------
@functions_framework.http
def webhook_handler(request):
    # Cloud Scheduler tick
    if request.path.rstrip("/").endswith("metrics"):
        return _publish_all_metrics(), 200

    body = request.get_data()
    if not _verify_signature(body, request.headers.get("X-Hub-Signature-256")):
        return "Signature mismatch", 401

    event = request.headers.get("X-GitHub-Event", "")
    delivery = request.headers.get("X-GitHub-Delivery", "")
    if event != "workflow_job":
        return f"Ignored event: {event}", 200

    return _handle_workflow_job(request.get_json(silent=True) or {}, delivery), 200
