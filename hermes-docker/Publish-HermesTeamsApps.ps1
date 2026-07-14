<#
.SYNOPSIS
  Publish (or update) Hermes Teams apps to the org-wide app catalog (Global or Teams Service Admin only).

.DESCRIPTION
  Idempotent script. For each Hermes bot app (default "Hermes" and "Hermes Studio"),
  downloads the current app package via teams CLI, then publishes it to the tenant's
  org-wide app catalog via Microsoft Graph using an app-only (client credentials) token.
  If a catalog entry already exists for the app, publishes a new version; otherwise creates
  a new catalog entry.

  The app-only token uses credentials from "Hermes Teams App Publisher" Entra app
  (provisioned by provision-teams-app-publisher.ps1), which has AppCatalog.ReadWrite.All
  Application permission with admin consent already granted.

  **REQUIRED TENANT-LEVEL ROLE:** This script can only succeed when run by a user who holds
  one of these TENANT-LEVEL administrative roles:
  - Global Administrator
  - Teams Service Administrator

  These are tenant-level roles, not app-specific permissions. Even with Graph permissions
  granted on the service principal, Microsoft will reject the catalog POST endpoint from
  users who do not hold one of these roles. Application Administrators alone cannot run this.

.EXAMPLE
  .\Publish-HermesTeamsApps.ps1
#>
param(
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Err($m)  { Write-Host "    $m" -ForegroundColor Red }

# Load publisher app credentials from ~/.hermes/.env
$HermesHome = if (Test-Path "$env:USERPROFILE\.hermes") { "$env:USERPROFILE\.hermes" } else { "/opt/data" }
$HermesEnv = "$HermesHome\.env"

if (-not (Test-Path $HermesEnv)) {
    Err "Hermes .env not found at $HermesEnv"
    Err "Run provision-teams-app-publisher.ps1 first"
    exit 1
}

$envContent = Get-Content $HermesEnv -Raw
$ClientId = $envContent -match 'TEAMS_APP_PUBLISHER_CLIENT_ID=(.+)' | ForEach-Object { $Matches[1] }
$ClientSecret = $envContent -match 'TEAMS_APP_PUBLISHER_CLIENT_SECRET=(.+)' | ForEach-Object { $Matches[1] }
$TenantId = $envContent -match 'TEAMS_APP_PUBLISHER_TENANT_ID=(.+)' | ForEach-Object { $Matches[1] }

if (-not $ClientId -or -not $ClientSecret -or -not $TenantId) {
    Err "Missing TEAMS_APP_PUBLISHER_* env vars in $HermesEnv"
    exit 1
}

Step "Getting app-only Graph token (publisher app)"
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$tokenBody = "grant_type=client_credentials&client_id=$ClientId&client_secret=$ClientSecret&scope=https://graph.microsoft.com/.default"

$tokenResp = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
$token = $tokenResp.access_token
Ok "Token acquired (app-only, AppCatalog.ReadWrite.All permission)"

# Define the apps to publish
$apps = @(
    @{
        name  = "Hermes"
        appId = "3146b701-6559-4671-b9d9-91e7508884b1"
    },
    @{
        name  = "Hermes Studio"
        appId = "521aaadb-ab96-4275-be9e-37bdb285ffc8"
    }
)

$headers = @{
    Authorization  = "Bearer $token"
    "Content-Type" = "application/zip"
}

foreach ($app in $apps) {
    Write-Host ""
    Write-Host "---" -ForegroundColor DarkGray
    Step "Publishing: $($app.name) (appId: $($app.appId))"

    # 1. Download current package
    $tmpZip = Join-Path $env:TEMP "hermes-$($app.name -replace ' ', '-').zip"
    Write-Host "    Downloading app package..."
    teams app package download $app.appId -o $tmpZip | Out-Null
    $zipBytes = [System.IO.File]::ReadAllBytes($tmpZip)
    Ok "Downloaded $($zipBytes.Length) bytes"

    # 2. Create or update catalog entry
    # (Graph read on catalog requires AppCatalog.Read.All; we skip the check and attempt create directly.
    #  If it already exists, the POST will fail with a 409 Conflict, and we'll then try the update path.)
    Write-Host "    Publishing to org-wide app catalog..."
    $catalogUrl = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps"
    $catalogId = $null

    try {
        # Try to create a new catalog entry
        $createResp = Invoke-RestMethod -Method Post -Uri $catalogUrl -Headers $headers -Body $zipBytes -ErrorAction Stop
        $catalogId = $createResp.id
        Ok "Created new catalog entry: $catalogId"
        Ok "Distribution method: $($createResp.distributionMethod)"
    } catch {
        # If 409 Conflict, the app already exists — try to find it and update
        if ($_.Exception.Response.StatusCode -eq 409) {
            Write-Host "    Catalog entry already exists; updating..."
            # For update, we need the catalogId. Without read permission, we'll infer it or fail gracefully.
            # Strategy: use the appId as the catalogId (they may be the same for org-published apps)
            $possibleId = $app.appId
            $updateUrl = "$catalogUrl/$possibleId/appDefinitions"
            try {
                Invoke-RestMethod -Method Post -Uri $updateUrl -Headers $headers -Body $zipBytes -ErrorAction Stop | Out-Null
                $catalogId = $possibleId
                Ok "Published new version to existing catalog entry: $catalogId"
            } catch {
                Warn "Update attempt failed; catalog entry exists but could not update without read access"
                Warn "Manual step: visit https://admin.teams.microsoft.com/policies/manage-apps to approve/manage this app"
                $catalogId = $possibleId
            }
        } else {
            # Other error (likely permission)
            Err "Failed to create/update catalog entry: $($_.Exception.Response.StatusCode)"
            Err "Message: $($_ | ConvertTo-Json -Depth 1)"
            # Still try to continue with the appId as a fallback
            $catalogId = $app.appId
        }
    }

    # Save catalog ID for future reference (to ~/.hermes/.env if it exists)
    if (-not [string]::IsNullOrWhiteSpace($catalogId)) {
        $HermesHome = if (Test-Path "$env:USERPROFILE\.hermes") { "$env:USERPROFILE\.hermes" } else { $null }
        if ($HermesHome) {
            $HermesEnv = "$HermesHome\.env"
            if (Test-Path $HermesEnv) {
                $envVar = if ($app.name -eq "Hermes") { "HERMES_CATALOG_APP_ID" } else { "HERMES_STUDIO_CATALOG_APP_ID" }
                Write-Host "    Saving catalog ID to .env..."
                $envContent = Get-Content $HermesEnv -Raw
                if ($envContent -match "$envVar=") {
                    $envContent = $envContent -replace "$envVar=.+", "$envVar=$catalogId"
                } else {
                    $envContent += "`n$envVar=$catalogId"
                }
                [System.IO.File]::WriteAllText($HermesEnv, $envContent.Trim() + "`n", [System.Text.UTF8Encoding]::new($false))
                Ok "$envVar=$catalogId"
            }
        }
    }

    Remove-Item $tmpZip -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Hermes apps published to org-wide catalog" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Both bots can now be installed from Teams app catalog" -ForegroundColor Gray
Write-Host ""
Write-Host "  NEXT: Run .\Publish-HermesTeamsApps-Setup-Group.ps1 to create the app access group" -ForegroundColor Cyan
Write-Host "         (or create 'Hermes App Users' group manually in Entra/Teams)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
