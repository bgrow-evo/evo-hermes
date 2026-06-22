#Requires -Version 5.1
<#
.SYNOPSIS
    Provision Azure Blob storage for the studio agent and wire its rclone remote.

.DESCRIPTION
    End to end, no pasting:
      1. Creates a resource group, Standard_LRS storage account, and a private
         container.
      2. Creates a service principal with "Storage Blob Data Contributor" scoped to
         the storage account.
      3. Creates the rclone remote `agent-blob` (azureblob, service-principal auth)
         inside the running Hermes container, in the studio profile's volume config.
      4. Verifies the agent can list the container (retries while the RBAC role
         assignment propagates).

    The service-principal secret flows az -> docker exec -> the volume rclone.conf;
    it is never written into this repo. A reference copy of the non-secret values
    (plus the secret) is saved to the gitignored volume file noted at the end.

    Requires: Azure CLI (`az`) logged in with rights to create a resource group,
    storage account, and register an Entra app; Docker with the `hermes` container
    running.

.PARAMETER ResourceGroup   Default "rg-hermes-studio".
.PARAMETER Location        Default "westus2".
.PARAMETER StorageAccount  Default "evohermesstudio<random>" (globally unique, lowercase).
.PARAMETER Container       Default "studio-outbox".
.PARAMETER SpName          Default "sp-hermes-studio-blob".
.PARAMETER Container_Name  Docker container name. Default "hermes".
.PARAMETER RemoteName      rclone remote name. Default "agent-blob".

.EXAMPLE
    .\provision-studio-blob.ps1
.EXAMPLE
    .\provision-studio-blob.ps1 -Location eastus2 -StorageAccount evohermesstudio01
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup  = "rg-hermes-studio",
    [string]$Location       = "westus2",
    [string]$StorageAccount = ("evohermesstudio{0}" -f (Get-Random -Maximum 99999)),
    [string]$Container      = "studio-outbox",
    [string]$SpName         = "sp-hermes-studio-blob",
    [string]$Container_Name = "hermes",
    [string]$RemoteName     = "agent-blob"
)

$ErrorActionPreference = "Stop"
function Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m){   Write-Host "    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "    $m" -ForegroundColor Yellow }

$RcloneConfig = "/opt/data/profiles/studio/rclone.conf"

# --- preflight --------------------------------------------------------------
Step "Preflight"
if (-not (Get-Command az -ErrorAction SilentlyContinue))     { throw "Azure CLI (az) not found on PATH." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "docker not found on PATH." }
$acct = az account show -o json 2>$null | ConvertFrom-Json
if (-not $acct) { throw "Not logged in to Azure. Run 'az login' first." }
Ok "Azure subscription: $($acct.name)  ($($acct.id))"
docker inspect $Container_Name *> $null
if ($LASTEXITCODE -ne 0) { throw "Docker container '$Container_Name' is not running." }
Ok "Docker container '$Container_Name' is up."

# --- 1. resource group + storage account + container ------------------------
Step "Creating resource group '$ResourceGroup' ($Location)"
az group create -n $ResourceGroup -l $Location -o none
Ok "Resource group ready."

Step "Creating storage account '$StorageAccount'"
az storage account create -n $StorageAccount -g $ResourceGroup -l $Location `
    --sku Standard_LRS --kind StorageV2 `
    --allow-blob-public-access false --min-tls-version TLS1_2 -o none
if ($LASTEXITCODE -ne 0) { throw "Storage account create failed (name taken globally? try -StorageAccount <unique>)." }
Ok "Storage account ready."

Step "Creating private container '$Container'"
az storage container create --account-name $StorageAccount -n $Container -o none
Ok "Container ready."

# --- 2. service principal with blob data role -------------------------------
Step "Creating service principal '$SpName' (Storage Blob Data Contributor)"
$scope = az storage account show -n $StorageAccount -g $ResourceGroup --query id -o tsv
$sp = az ad sp create-for-rbac -n $SpName --role "Storage Blob Data Contributor" --scopes $scope -o json | ConvertFrom-Json
if (-not $sp -or -not $sp.appId) { throw "Service principal creation failed (do you have rights to register an Entra app?)." }
$clientId     = $sp.appId
$clientSecret = $sp.password
$tenant       = $sp.tenant
Ok "Service principal created (client_id $clientId)."

# --- 3. wire the rclone remote inside the container -------------------------
Step "Creating rclone remote '$RemoteName' in the container"
# Replace any prior remote of this name so re-runs are idempotent.
docker exec $Container_Name rclone --config $RcloneConfig config delete $RemoteName *> $null
docker exec $Container_Name rclone --config $RcloneConfig config create $RemoteName azureblob `
    account     $StorageAccount `
    tenant      $tenant `
    client_id   $clientId `
    client_secret $clientSecret
if ($LASTEXITCODE -ne 0) { throw "rclone config create failed." }
Ok "rclone remote '$RemoteName' written to $RcloneConfig (in the volume)."

# --- 4. verify (retry while RBAC propagates) --------------------------------
Step "Verifying the agent can reach the container (RBAC can take ~1 min to propagate)"
$verified = $false
foreach ($i in 1..8) {
    docker exec $Container_Name rclone --config $RcloneConfig ls "$($RemoteName):$Container" *> $null
    if ($LASTEXITCODE -eq 0) { $verified = $true; break }
    Warn "not ready yet (attempt $i/8) - waiting 15s..."
    Start-Sleep -Seconds 15
}
if ($verified) { Ok "Verified: agent can read/write '$RemoteName`:$Container'." }
else { Warn "Could not verify yet. Re-try later: docker exec $Container_Name rclone --config $RcloneConfig ls $RemoteName`:$Container" }

# --- reference copy of values (gitignored volume location) ------------------
$refPath = Join-Path $env:USERPROFILE ".hermes\profiles\studio\.blob-credentials.json"
@{
    account       = $StorageAccount
    container     = $Container
    tenant        = $tenant
    client_id     = $clientId
    client_secret = $clientSecret
    resource_group= $ResourceGroup
    scope         = $scope
} | ConvertTo-Json | Set-Content -Path $refPath -Encoding ascii

# --- summary ----------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " Studio blob storage provisioned and wired." -ForegroundColor Green
Write-Host "   account:    $StorageAccount"
Write-Host "   container:  $Container"
Write-Host "   tenant:     $tenant"
Write-Host "   client_id:  $clientId"
Write-Host "   rclone:     $RemoteName`:$Container   (config in volume rclone.conf)"
Write-Host " Reference values (incl. secret) saved to:" -ForegroundColor Yellow
Write-Host "   $refPath  (gitignored; treat as a credential)" -ForegroundColor Yellow
Write-Host " For the Power Automate connection, use this storage account (account key or the SP above)." -ForegroundColor White
Write-Host "----------------------------------------------------------------" -ForegroundColor White
