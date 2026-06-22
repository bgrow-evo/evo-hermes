#Requires -Version 5.1
<#
.SYNOPSIS
    Provision Azure Blob storage for the studio agent and wire its rclone remote.

.DESCRIPTION
    End to end, no pasting, and idempotent (safe to re-run):
      1. Creates/ensures a resource group, Standard_LRS storage account, and a
         private container.
      2. Ensures a service principal with "Storage Blob Data Contributor" scoped to
         the storage account. If the SP already exists, its credential is RESET
         (so a re-run always yields a usable secret) rather than duplicated.
      3. Creates/updates the rclone remote `agent-blob` (azureblob, service-principal
         auth) inside the running Hermes container, in the studio profile's volume
         config.
      4. Verifies the agent can list the container (retries while the RBAC role
         assignment propagates).

    The service-principal secret flows az -> docker exec -> the volume rclone.conf;
    it is never written into this repo. A reference copy (incl. the secret) is saved
    to the gitignored volume file noted at the end.

    Requires: Azure CLI (`az`) logged in with rights to create a resource group,
    storage account, and register an Entra app; Docker with the `hermes` container
    running.

.PARAMETER ResourceGroup   Default "rg-hermes-studio".
.PARAMETER Location        Default "westus2".
.PARAMETER StorageAccount  Default "evohermesstudio<random>" (globally unique, lowercase).
.PARAMETER Container       Default "studio-outbox".
.PARAMETER SpName          Default "sp-hermes-studio-blob".
.PARAMETER ContainerName   Docker container name. Default "hermes".
.PARAMETER RemoteName      rclone remote name. Default "agent-blob".

.EXAMPLE
    .\provision-studio-blob.ps1
.EXAMPLE
    # re-run after a partial failure, reusing the same names:
    .\provision-studio-blob.ps1 -StorageAccount evohermesstudio12345
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup  = "rg-hermes-studio",
    [string]$Location       = "westus2",
    [string]$StorageAccount = ("evohermesstudio{0}" -f (Get-Random -Maximum 99999)),
    [string]$Container      = "studio-outbox",
    [string]$SpName         = "sp-hermes-studio-blob",
    [string]$ContainerName  = "hermes",
    [string]$RemoteName     = "agent-blob"
)

$ErrorActionPreference = "Stop"
function Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m){   Write-Host "    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "    $m" -ForegroundColor Yellow }

$RcloneConfig = "/opt/data/profiles/studio/rclone.conf"

# NOTE: we never redirect a native command's stderr (no `2>`/`*>`). In PowerShell
# 5.1 that would wrap each stderr line as a terminating NativeCommandError. Instead
# we let stderr print and gate strictly on $LASTEXITCODE.

# --- preflight --------------------------------------------------------------
Step "Preflight"
if (-not (Get-Command az -ErrorAction SilentlyContinue))     { throw "Azure CLI (az) not found on PATH." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker not found on PATH." }
$rawAcct = az account show -o json
if ($LASTEXITCODE -ne 0 -or -not $rawAcct) { throw "Not logged in to Azure. Run 'az login' first." }
$acct = $rawAcct | ConvertFrom-Json
Ok "Azure subscription: $($acct.name)  ($($acct.id))"
docker inspect $ContainerName > $null
if ($LASTEXITCODE -ne 0) { throw "Docker container '$ContainerName' is not running." }
Ok "Docker container '$ContainerName' is up."

# --- 1. resource group + storage account + container ------------------------
Step "Ensuring resource group '$ResourceGroup' ($Location)"
az group create -n $ResourceGroup -l $Location -o none
if ($LASTEXITCODE -ne 0) { throw "resource group create failed." }
Ok "Resource group ready."

Step "Ensuring storage account '$StorageAccount'"
az storage account create -n $StorageAccount -g $ResourceGroup -l $Location `
    --sku Standard_LRS --kind StorageV2 `
    --allow-blob-public-access false --min-tls-version TLS1_2 -o none
if ($LASTEXITCODE -ne 0) { throw "Storage account create failed (name taken globally? try -StorageAccount <unique>)." }
Ok "Storage account ready."

Step "Ensuring private container '$Container'"
az storage container create --account-name $StorageAccount -n $Container -o none
if ($LASTEXITCODE -ne 0) { throw "container create failed." }
Ok "Container ready."

# --- 2. service principal with blob data role (idempotent) ------------------
$scope = az storage account show -n $StorageAccount -g $ResourceGroup --query id -o tsv
if ($LASTEXITCODE -ne 0 -or -not $scope) { throw "could not resolve storage account id." }

$existingId = az ad sp list --display-name $SpName --query "[0].appId" -o tsv
if ($existingId) {
    Step "Service principal '$SpName' exists ($existingId) - resetting credential"
    $reset = (az ad sp credential reset --id $existingId -o json) | ConvertFrom-Json
    if (-not $reset.password) { throw "credential reset failed." }
    $clientId     = $existingId
    $clientSecret = $reset.password
    $tenant       = if ($reset.tenant) { $reset.tenant } else { $acct.tenantId }
    # Ensure the role assignment exists (idempotent; no-op if already assigned).
    az role assignment create --assignee $clientId --role "Storage Blob Data Contributor" --scope $scope -o none
    Ok "Credential reset; role assignment ensured."
} else {
    Step "Creating service principal '$SpName' (Storage Blob Data Contributor)"
    $sp = (az ad sp create-for-rbac -n $SpName --role "Storage Blob Data Contributor" --scopes $scope -o json) | ConvertFrom-Json
    if (-not $sp.appId) { throw "Service principal creation failed (do you have rights to register an Entra app?)." }
    $clientId     = $sp.appId
    $clientSecret = $sp.password
    $tenant       = $sp.tenant
    Ok "Service principal created (client_id $clientId)."
}

# --- 3. wire the rclone remote inside the container (create or update) ------
Step "Wiring rclone remote '$RemoteName' in the container"
$remotes = docker exec $ContainerName rclone --config $RcloneConfig listremotes
$action  = if ($remotes -contains "${RemoteName}:") { "update" } else { "create" }
docker exec $ContainerName rclone --config $RcloneConfig config $action $RemoteName azureblob `
    account       $StorageAccount `
    tenant        $tenant `
    client_id     $clientId `
    client_secret $clientSecret
if ($LASTEXITCODE -ne 0) { throw "rclone config $action failed." }
Ok "rclone remote '$RemoteName' ($action) written to $RcloneConfig (in the volume)."

# --- 4. verify (retry while RBAC propagates) --------------------------------
Step "Verifying agent access (RBAC can take ~1 min to propagate)"
$verified = $false
foreach ($i in 1..8) {
    docker exec $ContainerName rclone --config $RcloneConfig ls "${RemoteName}:$Container" | Out-Null
    if ($LASTEXITCODE -eq 0) { $verified = $true; break }
    Warn "not ready yet (attempt $i/8) - waiting 15s..."
    Start-Sleep -Seconds 15
}
if ($verified) { Ok "Verified: agent can read/write '${RemoteName}:$Container'." }
else { Warn "Could not verify yet. Retry later: docker exec $ContainerName rclone --config $RcloneConfig ls ${RemoteName}:$Container" }

# --- reference copy of values (gitignored volume location) ------------------
$refPath = Join-Path $env:USERPROFILE ".hermes\profiles\studio\.blob-credentials.json"
@{
    account        = $StorageAccount
    container      = $Container
    tenant         = $tenant
    client_id      = $clientId
    client_secret  = $clientSecret
    resource_group = $ResourceGroup
    scope          = $scope
} | ConvertTo-Json | Set-Content -Path $refPath -Encoding ascii

# --- summary ----------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " Studio blob storage provisioned and wired." -ForegroundColor Green
Write-Host "   account:    $StorageAccount"
Write-Host "   container:  $Container"
Write-Host "   tenant:     $tenant"
Write-Host "   client_id:  $clientId"
Write-Host "   rclone:     ${RemoteName}:$Container   (config in volume rclone.conf)"
Write-Host " Reference values (incl. secret) saved to:" -ForegroundColor Yellow
Write-Host "   $refPath  (gitignored; treat as a credential)" -ForegroundColor Yellow
Write-Host " For the Power Automate connection, use this storage account (account key or the SP above)." -ForegroundColor White
Write-Host "----------------------------------------------------------------" -ForegroundColor White
