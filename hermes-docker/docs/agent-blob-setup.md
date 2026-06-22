# Give the studio agent its own Azure Blob Storage (rclone + service principal)

The studio agent reaches **its own** Azure Blob container through `rclone` (installed in
the image), authenticated with a **service principal** — fully headless, no user
sign-in, no OneDrive license. Credentials live in the volume `rclone.conf` and the
remote auto-acquires tokens; rebuilds don't require re-auth.

```
Studio agent (container)
  └─ rclone --config /opt/data/profiles/studio/rclone.conf  agent-blob:studio-outbox/...
        └─ Azure Blob (service principal: Storage Blob Data Contributor on the account)
```

## Step 1 — provision (Azure admin — yours)

Run in PowerShell with the Azure CLI (`az login` first):

```powershell
$RG    = "rg-hermes-studio"
$LOC   = "westus2"                                   # your region
$ACCT  = "evohermesstudio$(Get-Random -Max 99999)"  # globally unique, lowercase, 3-24 chars
$CT    = "studio-outbox"
$SPN   = "sp-hermes-studio-blob"

az group create -n $RG -l $LOC
az storage account create -n $ACCT -g $RG -l $LOC --sku Standard_LRS --kind StorageV2 `
    --allow-blob-public-access false --min-tls-version TLS1_2
az storage container create --account-name $ACCT -n $CT            # private

$SCOPE = az storage account show -n $ACCT -g $RG --query id -o tsv
az ad sp create-for-rbac -n $SPN --role "Storage Blob Data Contributor" --scopes $SCOPE
# prints: appId (client_id), password (client_secret), tenant
```

Record: **account** (`$ACCT`), **container** (`studio-outbox`), **tenant**, **client_id**
(appId), **client_secret** (password).

## Step 2 — create the rclone remote (in the container, non-interactive)

No browser needed — service-principal creds go straight into the config:

```powershell
docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf `
  config create agent-blob azureblob `
    account <ACCT> `
    tenant <TENANT> `
    client_id <APPID> `
    client_secret <PASSWORD>
```

(rclone's `azureblob` backend uses the service principal automatically when
`tenant` + `client_id` + `client_secret` are set.)

## Step 3 — verify from inside the agent

```powershell
docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf lsd agent-blob:
docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf ls  agent-blob:studio-outbox
```

`lsd` listing the container (and `ls` succeeding, even if empty) = the agent can
read/write its blob storage. The `agent-blob` skill documents day-to-day commands; the
studio pipeline pushes PIM-ready packages to `agent-blob:studio-outbox/<date>/` on
**live** runs.

## Notes

- **Token refresh:** rclone acquires/renews bearer tokens from the service principal
  automatically. Re-do Step 2 only if the SP secret is rotated/expired
  (`az ad sp credential reset`).
- **Least privilege:** the role is scoped to this one storage account. Scope it to just
  the container instead by using the container's resource id as `--scopes`.
- **Security:** the SP `client_secret` in `rclone.conf` is a credential. It lives only
  in the volume (`~/.hermes/profiles/studio/`), which is gitignored and never in the
  repo. Rotate with `az ad sp credential reset` and re-run Step 2.
- **Dry-run:** the agent skips the blob push while `DRY_RUN` is set (it cascades to a
  Teams channel post). Read/list is always allowed.
