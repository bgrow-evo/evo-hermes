<#
.SYNOPSIS
  One-time provisioning: create Entra app for Hermes Studio Teams delegation, wire env vars.

.DESCRIPTION
  Idempotent script. Creates (or finds) the Entra app "Hermes Studio Teams Post" with
  delegated Microsoft Graph ChannelMessage.Send scope. Writes client_id, tenant_id,
  team_id, channel_id to the studio profile's .env.

  The interactive device-code sign-in is NOT done here (that requires hermes-ai@evo.com
  and a browser). This script only sets up the app registration and env vars.

.EXAMPLE
  .\provision-studio-teams-post.ps1
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
$DisplayName = "Hermes Studio Teams Post (delegated)"

# Graph permission: ChannelMessage.Send (delegated)
# Resource ID: 00000003-0000-0000-c000-000000000000 (Microsoft Graph)
# Permission ID: ebf0f66e-9fb1-49e4-a278-222f76911cf4 (ChannelMessage.Send)
# Permission Type: Scope (delegated)
$ResourceAccess = @(
    @{
        resourceAppId = "00000003-0000-0000-c000-000000000000"
        resourceAccess = @(
            @{
                id   = "ebf0f66e-9fb1-49e4-a278-222f76911cf4"
                type = "Scope"
            },
            @{
                id   = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"
                type = "Scope"
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
      --is-fallback-public-client true `
      --required-resource-accesses "@$tmpManifest" | ConvertFrom-Json

    $ClientId = $app.appId
    Remove-Item $tmpManifest -ErrorAction SilentlyContinue
    Ok "Created: $ClientId"
}

# Resolve hermes data dir
$HermesHome = if (Test-Path "$env:USERPROFILE\.hermes") { "$env:USERPROFILE\.hermes" } else { "/opt/data" }
$StudioEnv = "$HermesHome\profiles\studio\.env"

if (-not (Test-Path $StudioEnv)) {
    Warn "Studio profile .env not found at $StudioEnv"
    Warn "Create it first or specify HERMES_DATA environment variable"
    exit 1
}

Step "Updating studio profile .env"
$envContent = Get-Content $StudioEnv -Raw
$newEnv = $envContent

# Add or update the variables
$newEnv = if ($newEnv -match "TEAMS_GRAPH_CLIENT_ID=") {
    $newEnv -replace "TEAMS_GRAPH_CLIENT_ID=.+", "TEAMS_GRAPH_CLIENT_ID=$ClientId"
} else {
    "$newEnv`nTEAMS_GRAPH_CLIENT_ID=$ClientId"
}

$newEnv = if ($newEnv -match "TEAMS_GRAPH_TENANT_ID=") {
    $newEnv -replace "TEAMS_GRAPH_TENANT_ID=.+", "TEAMS_GRAPH_TENANT_ID=$TenantId"
} else {
    "$newEnv`nTEAMS_GRAPH_TENANT_ID=$TenantId"
}

# Hermes POC team & channel IDs
$newEnv = if ($newEnv -match "TEAMS_GRAPH_TEAM_ID=") {
    $newEnv -replace "TEAMS_GRAPH_TEAM_ID=.+", "TEAMS_GRAPH_TEAM_ID=b2bf59a4-0aaa-47b3-a985-a3a17668b29e"
} else {
    "$newEnv`nTEAMS_GRAPH_TEAM_ID=b2bf59a4-0aaa-47b3-a985-a3a17668b29e"
}

$newEnv = if ($newEnv -match "TEAMS_GRAPH_CHANNEL_ID=") {
    $newEnv -replace "TEAMS_GRAPH_CHANNEL_ID=.+", "TEAMS_GRAPH_CHANNEL_ID=19:3_P4d9-3DQ2MAcVxhPs9nBo_IPRsvdFbkOSpHqZ-Sqc1@thread.tacv2"
} else {
    "$newEnv`nTEAMS_GRAPH_CHANNEL_ID=19:3_P4d9-3DQ2MAcVxhPs9nBo_IPRsvdFbkOSpHqZ-Sqc1@thread.tacv2"
}

[System.IO.File]::WriteAllText($StudioEnv, $newEnv.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))
Ok "Updated: $StudioEnv"

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Entra app ready for delegated Graph auth" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Client ID  : $ClientId" -ForegroundColor Gray
Write-Host "  Tenant     : $TenantId" -ForegroundColor Gray
Write-Host "  Scope      : ChannelMessage.Send (delegated)" -ForegroundColor Gray
Write-Host ""
Write-Host "  NEXT: Read docs/agent-teams-post-setup.md for the one-time device-code sign-in" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
