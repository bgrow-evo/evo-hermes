<#
.SYNOPSIS
  One-time provisioning: create Entra app for publishing Hermes Teams apps to the org catalog.

.DESCRIPTION
  Idempotent script. Creates (or finds) the Entera app "Hermes Teams App Publisher" with
  AppCatalog.ReadWrite.All Application permission (app-only), then grants admin consent.
  Writes client_id, client_secret, tenant_id to ~/.hermes/.env for use by
  Publish-HermesTeamsApps.ps1.

.EXAMPLE
  .\provision-teams-app-publisher.ps1
#>
param(
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

Step "Checking Azure CLI login"
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login
    $account = az account show | ConvertFrom-Json
}
Ok "Logged in as $($account.user.name)"

$TenantId = "1c2caf71-5666-4b98-bffc-ae0da8c4a4db"
$DisplayName = "Hermes Teams App Publisher"

# Look up the exact AppCatalog.ReadWrite.All app role ID from Microsoft Graph SP
Step "Looking up Graph AppCatalog.ReadWrite.All role ID"
$graphSp = az ad sp show --id 00000003-0000-0000-c000-000000000000 --query "appRoles[?value=='AppCatalog.ReadWrite.All'].id" -o tsv
if (-not $graphSp) {
    throw "Could not find AppCatalog.ReadWrite.All role in Microsoft Graph"
}
Ok "Found role ID: $graphSp"

# Application permission (type: Role, not Scope)
$ResourceAccess = @(
    @{
        resourceAppId = "00000003-0000-0000-c000-000000000000"
        resourceAccess = @(
            @{
                id   = $graphSp
                type = "Role"
            }
        )
    }
)

Step "Finding or creating Entra app: $DisplayName"
$existing = az ad app list --display-name "$DisplayName" --query "[0].appId" -o tsv 2>$null
if ($existing) {
    $ClientId = $existing
    Ok "Found existing app: $ClientId"
} else {
    Ok "Creating new app..."
    $manifest = $ResourceAccess | ConvertTo-Json -Depth 10
    $tmpManifest = Join-Path $env:TEMP "manifest-$(Get-Random).json"
    [System.IO.File]::WriteAllText($tmpManifest, $manifest, [System.Text.UTF8Encoding]::new($false))

    $app = az ad app create `
      --display-name "$DisplayName" `
      --sign-in-audience AzureADMyOrg `
      --required-resource-accesses "@$tmpManifest" | ConvertFrom-Json

    $ClientId = $app.appId
    Remove-Item $tmpManifest -ErrorAction SilentlyContinue
    Ok "Created: $ClientId"
}

# Create service principal and grant admin consent
Step "Creating service principal"
az ad sp create --id $ClientId 2>$null
Ok "Service principal ready"

Step "Granting admin consent for AppCatalog.ReadWrite.All"
az ad app permission admin-consent --id $ClientId
Ok "Admin consent granted"

# Create client secret
Step "Creating client secret"
$secret = az ad app credential reset --id $ClientId --years 1 --query password -o tsv
Ok "Client secret created (1-year validity)"

# Resolve hermes data dir and write to ~/.hermes/.env
$HermesHome = if (Test-Path "$env:USERPROFILE\.hermes") { "$env:USERPROFILE\.hermes" } else { "/opt/data" }
$HermesEnv = "$HermesHome\.env"

if (-not (Test-Path $HermesEnv)) {
    Warn "Hermes .env not found at $HermesEnv"
    Warn "Creating it..."
    New-Item -ItemType File -Path $HermesEnv -Force | Out-Null
}

Step "Updating ~/.hermes/.env with publisher credentials"
$envContent = Get-Content $HermesEnv -Raw -ErrorAction SilentlyContinue
$newEnv = $envContent

# Add or update the variables
$newEnv = if ($newEnv -match "TEAMS_APP_PUBLISHER_CLIENT_ID=") {
    $newEnv -replace "TEAMS_APP_PUBLISHER_CLIENT_ID=.+", "TEAMS_APP_PUBLISHER_CLIENT_ID=$ClientId"
} else {
    "$newEnv`nTEAMS_APP_PUBLISHER_CLIENT_ID=$ClientId"
}

$newEnv = if ($newEnv -match "TEAMS_APP_PUBLISHER_CLIENT_SECRET=") {
    $newEnv -replace "TEAMS_APP_PUBLISHER_CLIENT_SECRET=.+", "TEAMS_APP_PUBLISHER_CLIENT_SECRET=$secret"
} else {
    "$newEnv`nTEAMS_APP_PUBLISHER_CLIENT_SECRET=$secret"
}

$newEnv = if ($newEnv -match "TEAMS_APP_PUBLISHER_TENANT_ID=") {
    $newEnv -replace "TEAMS_APP_PUBLISHER_TENANT_ID=.+", "TEAMS_APP_PUBLISHER_TENANT_ID=$TenantId"
} else {
    "$newEnv`nTEAMS_APP_PUBLISHER_TENANT_ID=$TenantId"
}

[System.IO.File]::WriteAllText($HermesEnv, $newEnv.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))
Ok "Updated: $HermesEnv"

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Teams app publisher ready for org-catalog uploads" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Client ID  : $ClientId" -ForegroundColor Gray
Write-Host "  Tenant     : $TenantId" -ForegroundColor Gray
Write-Host "  Permission : AppCatalog.ReadWrite.All (Application)" -ForegroundColor Gray
Write-Host ""
Write-Host "  NEXT: Run .\Publish-HermesTeamsApps.ps1" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
