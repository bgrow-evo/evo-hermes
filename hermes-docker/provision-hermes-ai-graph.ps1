<#
.SYNOPSIS
  Provision the Entra public-client app for hermes-ai@evo.com delegated Graph chat access.

.DESCRIPTION
  Idempotent. Finds or creates the "Hermes Studio Teams Post (delegated)" public-client
  Entra app and grants the delegated Graph scopes the teams_graph chat adapter needs:

    - Chat.ReadWrite        read + send messages in chats hermes-ai is a member of
    - ChannelMessage.Send   post to channels (existing daily-summary skill)
    - User.Read             /me identity checks (graph_whoami)
    - offline_access        refresh token

  Permission IDs are resolved dynamically from the Microsoft Graph service principal,
  never hardcoded. After updating the app, grants tenant admin consent (the signed-in
  az user must hold a role able to consent, e.g. Global Admin).

  The interactive device-code sign-in as hermes-ai@evo.com is NOT done here - run
  plugins/teams_graph/scripts/graph_login.py afterwards (see docs/hermes-ai-chat-setup.md).

.EXAMPLE
  .\provision-hermes-ai-graph.ps1 -SkipPrompt
#>
param(
    [switch]$SkipPrompt,
    [string]$DisplayName = "Hermes Studio Teams Post (delegated)"
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

$TenantId = "1c2caf71-5666-4b98-bffc-ae0da8c4a4db"
$GraphAppId = "00000003-0000-0000-c000-000000000000"
$DelegatedScopes = @("Chat.ReadWrite", "ChannelMessage.Send", "User.Read", "offline_access")

Step "Checking Azure CLI login"
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login
    $account = az account show | ConvertFrom-Json
}
Ok "Logged in as $($account.user.name)"

Step "Resolving delegated permission IDs from the Microsoft Graph service principal"
$graphSp = az ad sp show --id $GraphAppId --query "{id:id, scopes:oauth2PermissionScopes[].{id:id, value:value}}" -o json | ConvertFrom-Json
$scopeIds = @{}
foreach ($name in $DelegatedScopes) {
    $match = $graphSp.scopes | Where-Object { $_.value -eq $name }
    if (-not $match) { throw "Delegated permission '$name' not found on the Graph service principal." }
    $scopeIds[$name] = $match.id
    Ok "$name = $($match.id)"
}

Step "Finding Entra app: $DisplayName"
$ClientId = az ad app list --display-name "$DisplayName" --query "[0].appId" -o tsv 2>$null
if (-not $ClientId) {
    Ok "Not found - creating public-client app..."
    $app = az ad app create `
      --display-name "$DisplayName" `
      --sign-in-audience AzureADMyOrg `
      --is-fallback-public-client true | ConvertFrom-Json
    $ClientId = $app.appId
}
Ok "App: $ClientId"

Step "Setting required delegated Graph permissions"
$resourceAccess = @(
    @{
        resourceAppId  = $GraphAppId
        resourceAccess = @($DelegatedScopes | ForEach-Object { @{ id = $scopeIds[$_]; type = "Scope" } })
    }
)
$tmpManifest = Join-Path $env:TEMP "hermes-graph-manifest-$(Get-Random).json"
[System.IO.File]::WriteAllText($tmpManifest, (ConvertTo-Json $resourceAccess -Depth 10), [System.Text.UTF8Encoding]::new($false))
az ad app update --id $ClientId --required-resource-accesses "@$tmpManifest"
Remove-Item $tmpManifest -ErrorAction SilentlyContinue
Ok "Scopes set: $($DelegatedScopes -join ', ')"

Step "Ensuring service principal exists"
$spId = az ad sp list --filter "appId eq '$ClientId'" --query "[0].id" -o tsv 2>$null
if (-not $spId) {
    az ad sp create --id $ClientId | Out-Null
    Ok "Service principal created."
} else {
    Ok "Service principal exists."
}

Step "Granting tenant admin consent"
az ad app permission admin-consent --id $ClientId
if ($LASTEXITCODE -ne 0) {
    Warn "Admin consent failed - the signed-in user may lack a consent-capable role."
    Warn "Grant manually: Entra admin center > App registrations > $DisplayName > API permissions > Grant admin consent"
} else {
    Ok "Admin consent granted for all requested delegated scopes."
}

# Write client/tenant IDs where both the local scripts and ACA deploy pick them up.
Step "Writing TEAMS_GRAPH_* env vars"
function Set-EnvVar([string]$path, [string]$name, [string]$value) {
    if (-not (Test-Path $path)) { Warn "Missing $path - skipped"; return }
    $content = Get-Content $path -Raw
    if ($content -match "(?m)^$name=") {
        $content = $content -replace "(?m)^$name=.*$", "$name=$value"
    } else {
        $content = $content.TrimEnd() + "`n$name=$value"
    }
    [System.IO.File]::WriteAllText($path, $content.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))
    Ok "$path : $name"
}
$rootEnv   = Join-Path $env:USERPROFILE ".hermes\.env"
$studioEnv = Join-Path $env:USERPROFILE ".hermes\profiles\studio\.env"
foreach ($envPath in @($rootEnv, $studioEnv)) {
    Set-EnvVar $envPath "TEAMS_GRAPH_CLIENT_ID" $ClientId
    Set-EnvVar $envPath "TEAMS_GRAPH_TENANT_ID" $TenantId
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Entra app ready for hermes-ai delegated Graph chat" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Client ID : $ClientId" -ForegroundColor Gray
Write-Host "  Tenant    : $TenantId" -ForegroundColor Gray
Write-Host "  Scopes    : $($DelegatedScopes -join ', ')" -ForegroundColor Gray
Write-Host ""
Write-Host "  NEXT: device-code sign-in as hermes-ai@evo.com:" -ForegroundColor Cyan
Write-Host "    python plugins\teams_graph\scripts\graph_login.py" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
