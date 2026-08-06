# SkyData Demo — CI/CD replica on free accounts

A minimal **React/Vite + Express** app that reproduces the exact SkyStudio CI/CD flow:

```
push to main
  ├── quality   (npm ci -> lint -> typecheck -> test)   ┐ run in parallel
  ├── build     (docker build -> push to ACR)           ┘
  └── deploy    (az webapp config container set -> restart -> /health check -> Teams notify)
```

Runs on a **self-hosted GCP runner** (`runs-on: [self-hosted, Linux, X64, gcp]`), builds to
**Azure Container Registry**, deploys to an **Azure Web App for Containers** — same as Studio,
just one runner VM and free-tier resources.

---

## 0. Test it locally first (no cloud needed)

```bash
npm install
npm run lint:check
npm run typecheck
npm test
npm run build        # frontend -> dist/
npm start            # serves on http://localhost:8080 ; check /health
```

## 1. Create the GitHub repo (personal account)

```bash
git init
git add .
git commit -m "init skydata-demo"
git branch -M main
git remote add origin https://github.com/<your-user>/skydata-demo.git
git push -u origin main
```

## 2. Self-hosted runner on GCP (always-free e2-micro)

```bash
gcloud compute instances create skydata-runner \
  --machine-type=e2-micro --zone=us-central1-a \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud
gcloud compute ssh skydata-runner --zone=us-central1-a
sudo apt-get update && sudo apt-get install -y docker.io
sudo usermod -aG docker $USER && exit          # re-ssh so docker works
```

Get a **registration token**: repo -> Settings -> Actions -> Runners -> *New self-hosted runner*.
Then on the VM:

```bash
bash setup-gcp-runner.sh <your-user>/skydata-demo <REGISTRATION_TOKEN>
```

## 3. Azure resources (free trial — $200 credit)

```bash
az login
RG=rg-skydata-demo
ACR=acrskydatademo$RANDOM
WEBAPP=wapp-skydata-demo-$RANDOM
LOCATION=eastus

az group create -n $RG -l $LOCATION
az acr create -n $ACR -g $RG --sku Basic --admin-enabled true
az acr credential show -n $ACR
az appservice plan create -n plan-skydata-demo -g $RG --is-linux --sku B1
az webapp create -n $WEBAPP -g $RG --plan plan-skydata-demo \
  --deployment-container-image-name mcr.microsoft.com/azuredocs/aci-helloworld
az webapp config appsettings set -n $WEBAPP -g $RG --settings WEBSITES_PORT=8080
```

> Put your real `$WEBAPP` and `$RG` values into `.github/workflows/deploy.yml`.

## 4. Service principal for the deploy job

```bash
SUB=$(az account show --query id -o tsv)
az ad sp create-for-rbac --name sp-skydata-demo \
  --role contributor \
  --scopes /subscriptions/$SUB/resourceGroups/$RG \
  --sdk-auth
```

## 5. GitHub repo secrets

Repo -> Settings -> Secrets and variables -> Actions:

| Secret | Value |
|---|---|
| `ACR_REGISTRY` | the ACR name **without** `.azurecr.io` |
| `ACR_USERNAME` | from `az acr credential show` |
| `ACR_PASSWORD` | from `az acr credential show` |
| `AZURE_CREDENTIALS` | the full `--sdk-auth` JSON from step 4 |
| `TEAMS_WEBHOOK` | *(optional)* incoming webhook URL |

## 6. Deploy

```bash
git commit --allow-empty -m "trigger deploy"
git push
```

Watch it under the repo's **Actions** tab.

---

## Free-tier mapping vs real Studio

| Studio | This demo |
|---|---|
| GCP MIG autoscaler (2–10 runners) | one always-free e2-micro self-hosted runner |
| Azure Container Registry | ACR Basic (free-trial credit) |
| Azure Web App for Containers | Web App B1 (free-trial credit) |
| SonarQube quality gate | omitted (add SonarCloud later if you want) |
| Teams webhook | optional Teams/Discord/Slack webhook |
| `VITE_*` build-args | single `VITE_BUILD_NUMBER` build-arg, same mechanism |
