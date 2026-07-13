---
description: Deploy Hermes to Azure Container Apps (ACA) with both default and studio Teams bots via a shared proxy, using Standard Azure Files as a backing store
---

# Deploy Hermes to Azure Container Apps (Standard Storage)

Scripts location: `scripts/azure/`

## Architecture

Two Hermes profiles (default + studio) run in one ACA container. A Python proxy on port 8080
routes `/default/*` and `/studio/*` to each profile's gateway (3978 and 3979 respectively).
Live application data runs on ACA `EmptyDir` at `/opt/data` (POSIX-compatible for Linux
permissions). Durable state syncs to Standard Azure Files SMB at `/mnt/hermes-persist`.

| Resource | Name |
|---|---|
| Subscription | `Playground` |
| Resource Group | `rg-hermes-sbx` |
| ACR | `acrhermessbx` |
| Storage Account (Standard LRS) | `sthermessbxwu2` |
| Azure Files share | `hermes-data` → `/mnt/hermes-persist` (durable store) |
| ACA Environment | `aca-env-hermes-nfs-sbx-wu2` |
| Container App | `aca-hermes-nfs` |
| Proxy port | `8080` → externally 443 (ingress) |
| Location | `westus2` |

## Routine redeploy

```powershell
.\scripts\azure\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt
```

The script will:
1. Build and push a new image (tagged with git SHA)
2. Update both gateway Services config, Azure Files volumes, and revision
3. Call `teams app update` for both default and studio bots
4. Verify health at `/health` via the proxy

To deploy a specific tag without rebuilding:
```powershell
.\scripts\azure\Deploy-HermesStandardStorage.ps1 -Push -ImageTag abc1234 -SkipBuild -SkipPrompt
```

---

## First-time setup

### 1. Bootstrap Azure resources

```powershell
.\scripts\azure\Initialize-HermesPlatform.ps1 -SkipPrompt
```

Creates: Resource Group, ACR, Storage Account (Standard_LRS), Azure File Share (`hermes-data`).
Grants current user: `AcrPush`, `Container Registry Tasks Contributor`, `Storage File Data SMB Share Contributor`.

### 2. Migrate local volume to Azure Files

Move `~/.hermes` (auth tokens, profile configs, rclone.conf, etc.) to the Azure Files share:

```powershell
.\scripts\azure\Migrate-HermesVolume.ps1 -SkipPrompt
```

### 3. Build the image

```powershell
.\scripts\azure\Build-HermesImage.ps1 -SkipPrompt
```

### 4. First deploy (sets up ACA environment + container app)

```powershell
.\scripts\azure\Deploy-HermesStandardStorage.ps1 -Setup -SkipPrompt
```

This creates the ACA environment, registers Azure Files storage, and creates the container app
with both EmptyDir (live) and Azure Files (durable) volume mounts. Takes ~5 minutes.

### 5. Verify both Teams bots are reachable

```powershell
.\scripts\azure\Verify-HermesDeploy.ps1
```

Test by sending messages to both bots in Teams.

---

## Teams bots

| Bot | App ID | Endpoint |
|---|---|---|
| Hermes (default) | `3146b701-6559-4671-b9d9-91e7508884b1` | `/default/api/messages` |
| Hermes Studio | `521aaadb-ab96-4275-be9e-37bdb285ffc8` | `/studio/api/messages` |

The Deploy script updates both automatically. Manual update if needed:
```powershell
$fqdn = az containerapp show -n aca-hermes-nfs -g rg-hermes-sbx --query "properties.configuration.ingress.fqdn" -o tsv
teams app update 3146b701-6559-4671-b9d9-91e7508884b1 --endpoint "https://$fqdn/default/api/messages"
teams app update 521aaadb-ab96-4275-be9e-37bdb285ffc8  --endpoint "https://$fqdn/studio/api/messages"
```

---

## Re-auth (LLM tokens expire)

OpenAI Codex OAuth tokens live in the Azure Files volume (`/opt/data/auth.json`).
When they expire, run the PKCE re-auth from inside the running ACA container:

```powershell
az containerapp exec -n aca-hermes-nfs -g rg-hermes-sbx --command /bin/bash
# Then inside the container, follow the hermes-docker README "Re-auth steps" section
```

Or: update locally and re-migrate:
```powershell
# Edit ~/.hermes/auth.json locally
.\scripts\azure\Migrate-HermesVolume.ps1

# Restart to pick up the new token
$rev = az containerapp show -n aca-hermes-nfs -g rg-hermes-sbx --query properties.latestRevisionName -o tsv
az containerapp revision restart -n aca-hermes-nfs -g rg-hermes-sbx --revision $rev
```

---

## Useful commands

```powershell
# Tail live logs
az containerapp logs show -n aca-hermes-nfs -g rg-hermes-sbx --follow

# Revision status
az containerapp revision list -n aca-hermes-nfs -g rg-hermes-sbx `
  --query "[].{Revision:name, Health:properties.healthState, Active:properties.active}" `
  --output table

# Get the container app FQDN
$fqdn = az containerapp show -n aca-hermes-nfs -g rg-hermes-sbx --query "properties.configuration.ingress.fqdn" -o tsv
Write-Host "Proxy (ingress):  https://$fqdn/"
Write-Host "Default bot:      https://$fqdn/default/api/messages"
Write-Host "Studio bot:       https://$fqdn/studio/api/messages"
Write-Host "Health check:     https://$fqdn/health"

# Restart the active revision
$rev = az containerapp show -n aca-hermes-nfs -g rg-hermes-sbx --query properties.latestRevisionName -o tsv
az containerapp revision restart -n aca-hermes-nfs -g rg-hermes-sbx --revision $rev
```

---

## Troubleshooting

- **Health check fails / bots not responding**: Check logs with `az containerapp logs show`. Most common: missing auth tokens or profile config in Azure Files — re-run `Migrate-HermesVolume.ps1` and restart.
- **Snapshot sync warnings in logs**: Expected if Azure Files is under load. The sync includes a retry loop and should eventually succeed. If failures persist after 10+ cycles, contact support.
- **Teams endpoint update fails**: Ensure `teams` CLI is installed (`npm install -g '@microsoft/teams.cli@preview'`). Check subscription with `az account show --query name`.
- **Container cold-start timeout**: Hermes image is large (~4-5 min first boot). Wait and retry health check.
- **ACR pull fails on first setup**: Managed identity is auto-created during ACA deployment. Re-run `-Setup` if it fails on first try (idempotent).
