---
description: Deploy or redeploy Hermes agent to Azure Container Apps (Playground), migrate local volume to Azure Files, and update the Hermes Studio Teams bot endpoint
---

# Deploy Hermes to Azure Container Apps

Scripts location: `scripts/azure/`

| Resource | Name |
|---|---|
| Subscription (default) | `Playground` |
| Resource Group | `rg-hermes-sbx` |
| ACR | `acrhermessbx` |
| Storage Account | `sthermessbxwu2` |
| Azure Files share | `hermes-data` → mounted at `/opt/data` |
| ACA Environment | `aca-env-hermes-sbx-wu2` |
| Container App | `aca-hermes` |
| External port | `3979` (studio Teams bot + `/health`) |
| Location | `westus2` |

**Architecture note**: ACA external ingress (HTTPS 443) forwards to container port `3979`
(the Hermes studio gateway that serves both `/api/messages` for Teams and `/health`).
The main gateway API (8642) and dashboard (9119) are internal-only.

---

## Routine redeploy

```powershell
.\scripts\azure\Deploy-HermesAzure.ps1 -Push
```

The script will:
1. Prompt to confirm Azure subscription (default `AzureSandbox`)
2. Build and push a new image (tagged with git SHA)
3. Update the container app to a new revision
4. Call `teams app update 521aaadb-ab96-4275-be9e-37bdb285ffc8 --endpoint https://<fqdn>/api/messages`
5. Verify health at `https://<fqdn>/health`

To deploy a specific tag without rebuilding:
```powershell
.\scripts\azure\Deploy-HermesAzure.ps1 -Push -ImageTag abc1234 -SkipBuild
```

---

## First-time setup

### 1. Bootstrap Azure resources

```powershell
.\scripts\azure\Initialize-HermesPlatform.ps1
```

Creates: Resource Group, ACR, Storage Account, Azure File Share (`hermes-data`).
Grants current user: `AcrPush`, `Container Registry Tasks Contributor`, `Storage File Data SMB Share Contributor`.

Verify:
```powershell
az resource list --resource-group rg-hermes-sbx --output table
```

### 2. Migrate local volume to Azure Files

This is the **critical step** — it moves your `~/.hermes` data (auth tokens,
profile configs, rclone.conf, etc.) to the Azure Files share that the container
will mount as `/opt/data`.

```powershell
# Preview what will be uploaded
.\scripts\azure\Migrate-HermesVolume.ps1 -DryRun

# Perform the upload
.\scripts\azure\Migrate-HermesVolume.ps1
```

What gets migrated from `C:\Users\bgrow\.hermes`:
- `auth.json` — LLM auth tokens (OpenAI Codex)
- `profiles/studio/.env` — Teams bot credentials, allowed users
- `profiles/studio/config.yaml` — model config
- `profiles/studio/rclone.conf` — Azure Blob storage config
- `.env` — global Hermes env (Codex account ID etc.)

### 3. Build the image

```powershell
.\scripts\azure\Build-HermesImage.ps1
```

### 4. First deploy

```powershell
.\scripts\azure\Deploy-HermesAzure.ps1 -Setup
```

This creates the ACA environment, registers Azure Files storage, and creates
the container app with the volume mounted at `/opt/data`. Takes ~5 minutes.

### 5. Verify Teams bot is reachable

```powershell
.\scripts\azure\Verify-HermesDeploy.ps1
```

The Hermes Studio bot in Teams should now respond. Test by sending it a message.

---

## Teams bot details

- **Bot name**: Hermes Studio
- **Teams App ID**: `521aaadb-ab96-4275-be9e-37bdb285ffc8`
- **Endpoint path**: `/api/messages` on port 3979 (mapped to `https://<fqdn>/api/messages`)
- **The Deploy script calls this automatically** after every deploy

Manual update command if needed:
```powershell
$fqdn = az containerapp show -n aca-hermes -g rg-hermes-sbx --query "properties.configuration.ingress.fqdn" -o tsv
teams app update 521aaadb-ab96-4275-be9e-37bdb285ffc8 --endpoint "https://$fqdn/api/messages"
```

---

## Re-auth (LLM tokens expire)

The OpenAI Codex OAuth tokens live in the Azure Files volume (`/opt/data/auth.json`).
When they expire, run the PKCE re-auth from **inside the running ACA container**:

```powershell
# Get a shell in the container
az containerapp exec --name aca-hermes --resource-group rg-hermes-sbx --command /bin/bash

# Then inside the container, follow the hermes-docker README "Re-auth steps" section
```

Or: update the token locally in `~/.hermes/auth.json` and re-run `Migrate-HermesVolume.ps1`,
then restart the container:
```powershell
$rev = az containerapp show -n aca-hermes -g rg-hermes-sbx --query properties.latestRevisionName -o tsv
az containerapp revision restart -n aca-hermes -g rg-hermes-sbx --revision $rev
```

---

## Useful commands

```powershell
# Tail live logs
az containerapp logs show -n aca-hermes -g rg-hermes-sbx --follow

# List revisions and their image tags
az containerapp revision list -n aca-hermes -g rg-hermes-sbx `
  --query "[].{Revision:name, Active:properties.active, Image:properties.template.containers[0].image}" `
  --output table

# Check Azure Files share contents
$key = az storage account keys list --account-name sthermessbxwu2 -g rg-hermes-sbx --query "[0].value" -o tsv
az storage file list --share-name hermes-data --account-name sthermessbxwu2 --account-key $key --output table

# Get the live Teams bot endpoint URL
$fqdn = az containerapp show -n aca-hermes -g rg-hermes-sbx --query "properties.configuration.ingress.fqdn" -o tsv
Write-Host "Teams endpoint: https://$fqdn/api/messages"
```

---

## Troubleshooting

- **Health check times out**: Hermes image is large and has a long cold start (~3-5 min). Wait and retry.
- **Teams bot not responding**: Check that the endpoint was updated. Run `teams app update` manually (see above).
- **Container exits immediately**: Check logs with `az containerapp logs show`. Most likely: missing auth.json or profile config in Azure Files volume — re-run `Migrate-HermesVolume.ps1`.
- **Volume not mounted**: Ensure `az containerapp env storage set` ran successfully during `-Setup`. Re-run `Deploy-HermesAzure.ps1 -Setup` — it is idempotent.
- **AcrPull fails on first setup**: Managed identity is created during ACA deployment. Run `-Setup` a second time.
- **Teams CLI not found**: `npm install -g '@microsoft/teams.cli@preview'` (needs Node via NVM).
- **Wrong subscription at prompt**: Type the exact subscription name at the selection prompt.
