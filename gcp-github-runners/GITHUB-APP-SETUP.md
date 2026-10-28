# GitHub side — App + PAT + webhook secret

Exact-replica default is **org scope** (a free GitHub Organization), matching Studio:
org webhook, org-level self-hosted runners, runner group `Default`, and a GitHub App.

## A. Create a free GitHub Organization (once)

1. https://github.com/account/organizations/new → pick the **Free** plan.
2. Name it (e.g. `skydata-org`) — this is your `GITHUB_ORG` in `infra/config.env`.
3. Move/transfer the `skydata-demo` repo into this org
   (repo → Settings → General → **Transfer ownership**), or recreate it there.

> Set `SCOPE=repo` in `config.env` to skip the org and register repo-level runners on
> your personal account. The autoscaler mechanics are identical; only runner *groups*
> and the GitHub App below are org-only.

## B. Classic PAT — `github-pat` (runner registration)

The VM startup-script exchanges this for a one-time registration token.

1. https://github.com/settings/tokens → **Generate new token (classic)**.
2. Scope:
   - **org scope** → check **`admin:org`**  (NOT `manage_runners:org` — it 403s despite the name)
   - **repo scope** → check **`repo`**
3. Copy the token → this is `GITHUB_PAT` for `infra/01-secrets.sh`.
4. Calendar reminder ~80 days out — classic PATs expire in 90 days and fail silently.

## C. Webhook secret — `github-webhook-secret`

Any long random string. Generate one and keep it identical on both ends:

```bash
export GITHUB_WEBHOOK_SECRET=$(head -c 32 /dev/urandom | base64)
echo "$GITHUB_WEBHOOK_SECRET"   # save it; used by 01-secrets.sh AND 07-github-webhook.sh
```

## D. GitHub App — `github-app-id` + `github-app-private-key` (org scope only)

1. Org → Settings → Developer settings → **GitHub Apps** → **New GitHub App**.
2. Permissions:
   - Organization → **Self-hosted runners: Read and write**
   - Repository → **Actions: Read**
3. Subscribe to events: **Workflow job**.
4. Create → note the numeric **App ID** (`GITHUB_APP_ID`).
5. **Generate a private key** → downloads a `.pem` → its path is
   `GITHUB_APP_PRIVATE_KEY_FILE`.
6. **Install** the App on your org (select the `skydata-demo` repo).

## E. Now run the secrets script

```bash
export GITHUB_PAT=...                       # from B
export GITHUB_WEBHOOK_SECRET=...            # from C
export GITHUB_APP_ID=...                    # from D
export GITHUB_APP_PRIVATE_KEY_FILE=~/Downloads/skydata-app.private-key.pem
bash infra/01-secrets.sh
```
