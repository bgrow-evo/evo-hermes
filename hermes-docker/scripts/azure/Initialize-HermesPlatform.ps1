<#
.SYNOPSIS
  Bootstrap Azure resources for Hermes (one-time, idempotent).

.DESCRIPTION
  Creates: Resource Group, ACR (admin-enabled), Storage Account,
  Azure File Share (hermes-data). Grants current user the required
  Azure RBAC roles for ACR and Storage.

.EXAMPLE
  .\Initialize-HermesPlatform.ps1
  .\Initialize-HermesPlatform.ps1 -SubscriptionName AzureSandbox
#>
[CmdletBinding()]
param(
    [string]$SubscriptionName  = "Playground",
    [string]$ResourceGroupName = "rg-hermes-sbx",
    [string]$Location          = "westus2",
    [string]$AcrName           = "acrhermessbx",
    [string]$StorageAccount    = "sthermessbxwu2",
    [string]$FileShareName     = "hermes-data"
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

function Test-AzResource([scriptblock]$Cmd) {
    try { & $Cmd 2>&1 | Out-Null } catch {}
    return ($LASTEXITCODE -eq 0)
}

function Set-AzRoleIfAbsent {
    param([string]$Assignee, [string]$Role, [string]$Scope)
    $existing = az role assignment list --assignee $Assignee --role $Role --scope $Scope `
        --query "[0].id" --output tsv 2>$null
    if ($existing) { Warn "Role '$Role' already assigned."; return }
    Write-Host "    Assigning '$Role'..." -ForegroundColor Cyan
    az role assignment create --assignee $Assignee --role $Role --scope $Scope | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az role assignment create failed for '$Role'." }
    Ok "Assigned."
}

Step "Setting subscription: $SubscriptionName"
az account set --subscription $SubscriptionName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "az account set failed." }

$me = az account show --query user.name --output tsv
if ($LASTEXITCODE -ne 0 -or -not $me) { throw "Cannot determine signed-in user." }
Ok "Signed in as: $me"

Step "Resource Group: $ResourceGroupName"
az group create --name $ResourceGroupName --location $Location | Out-Null
if ($LASTEXITCODE -ne 0) { throw "az group create failed." }
Ok "Ready."

Step "ACR: $AcrName"
$acrExists = Test-AzResource { az acr show --name $AcrName --resource-group $ResourceGroupName --output none }
if (-not $acrExists) {
    az acr create `
      --name $AcrName `
      --resource-group $ResourceGroupName `
      --location $Location `
      --sku Basic `
      --admin-enabled true | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az acr create failed." }
    Ok "Created."
} else { Warn "Already exists." }

Step "Storage Account: $StorageAccount"
$saExists = Test-AzResource { az storage account show --name $StorageAccount --resource-group $ResourceGroupName --output none }
if (-not $saExists) {
    az storage account create `
      --name $StorageAccount `
      --resource-group $ResourceGroupName `
      --location $Location `
      --sku Standard_LRS `
      --kind StorageV2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az storage account create failed." }
    Ok "Created."
} else { Warn "Already exists." }

Step "File Share: $FileShareName"
$storageKey = az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $ResourceGroupName `
  --query "[0].value" --output tsv
if ($LASTEXITCODE -ne 0) { throw "Could not retrieve storage account key." }

$shareExists = az storage share exists `
  --name $FileShareName `
  --account-name $StorageAccount `
  --account-key $storageKey `
  --query "exists" --output tsv
if ($shareExists -ne "true") {
    az storage share create `
      --name $FileShareName `
      --account-name $StorageAccount `
      --account-key $storageKey | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az storage share create failed." }
    Ok "Created share '$FileShareName'."
} else { Warn "Share '$FileShareName' already exists." }

Step "RBAC role assignments"
$acrId = az acr show --name $AcrName --resource-group $ResourceGroupName --query id --output tsv
$saId  = az storage account show --name $StorageAccount --resource-group $ResourceGroupName --query id --output tsv
if (-not $acrId) { throw "Could not resolve ACR resource ID." }
if (-not $saId)  { throw "Could not resolve Storage Account resource ID." }

Set-AzRoleIfAbsent -Assignee $me -Role "AcrPush" -Scope $acrId
Set-AzRoleIfAbsent -Assignee $me -Role "Container Registry Tasks Contributor" -Scope $acrId
Set-AzRoleIfAbsent -Assignee $me -Role "Storage File Data SMB Share Contributor" -Scope $saId

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Bootstrap complete." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Storage key (save this for Migrate-HermesVolume.ps1):" -ForegroundColor Cyan
Write-Host "  $storageKey" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Migrate volume:  .\Migrate-HermesVolume.ps1"
Write-Host "  2. Build image:     .\Build-HermesImage.ps1"
Write-Host "  3. Deploy:          .\Deploy-HermesAzure.ps1 -Setup"
