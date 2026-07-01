<#
.SYNOPSIS
  Deploy Hermes to Azure Container Apps (Playground/Sandbox).

.DESCRIPTION
  Two modes:
    -Setup  First-time: provisions ACA environment, registers Azure Files storage,
            creates the container app with volume mount, updates Teams bot endpoint.
    -Push   Routine redeploy: updates container image to new tag, updates Teams endpoint.

  The Azure Files volume replaces the local ~/.hermes bind mount. Run
  Migrate-HermesVolume.ps1 before the first -Setup to upload local data.

  After every deploy the Hermes Studio Teams bot is updated:
    teams app update 521aaadb-ab96-4275-be9e-37bdb285ffc8 --endpoint https://<fqdn>/api/messages

.EXAMPLE
  .\Deploy-HermesAzure.ps1 -Setup
  .\Deploy-HermesAzure.ps1 -Push
  .\Deploy-HermesAzure.ps1 -Push -ImageTag abc1234 -SkipBuild
#>
param(
    [switch]$Setup,
    [switch]$Push,
    [string]$SubscriptionName  = "Playground",
    [string]$ResourceGroup     = "rg-hermes-sbx",
    [string]$Location          = "westus2",
    [string]$AcrName           = "acrhermessbx",
    [string]$StorageAccount    = "sthermessbxwu2",
    [string]$FileShareName     = "hermes-data",
    [string]$AcaEnvName        = "aca-env-hermes-sbx-wu2",
    [string]$ContainerAppName  = "aca-hermes",
    [string]$ImageRepository   = "hermes",
    [string]$ImageTag          = "",
    [switch]$SkipBuild,
    [switch]$SkipTeamsUpdate,
    [switch]$SkipVerify,
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

# Known Teams bot IDs
$StudioBotAppId = "521aaadb-ab96-4275-be9e-37bdb285ffc8"
$StudioBotPort  = 3979

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

if (-not $Setup -and -not $Push) {
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\Deploy-HermesAzure.ps1 -Setup         # First-time: provision + deploy"
    Write-Host "  .\Deploy-HermesAzure.ps1 -Push          # Routine: update image + Teams URL"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -ImageTag <tag>      (default: git short SHA)"
    Write-Host "  -SkipBuild           skip image rebuild"
    Write-Host "  -SkipTeamsUpdate     skip Teams bot endpoint update"
    Write-Host "  -SkipVerify          skip health check"
    Write-Host ""
    exit 0
}

# -- Read dashboard env vars from local .env --------------------------------
Step "Loading local .env"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path (Resolve-Path (Join-Path $scriptRoot "..\..")).Path ".env"

$envVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            $envVars[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    Ok "Loaded .env from $envFile"
} else {
    Warn ".env not found at $envFile - dashboard auth env vars will be empty."
}

$dashUser   = $envVars["HERMES_DASHBOARD_BASIC_AUTH_USERNAME"]
$dashPass   = $envVars["HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"]
$dashSecret = $envVars["HERMES_DASHBOARD_BASIC_AUTH_SECRET"]

if (-not $dashUser)   { $dashUser   = "admin" }
if (-not $dashPass)   { Warn "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD is empty - dashboard auth will not work." }
if (-not $dashSecret) { Warn "HERMES_DASHBOARD_BASIC_AUTH_SECRET is empty." }

# -- Azure CLI login / subscription -----------------------------------------
Step "Checking Azure CLI login"
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Running az login..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Ok "Logged in as $($account.user.name)"

Write-Host ""
Write-Host "  Current subscription : $($account.name)" -ForegroundColor White
Write-Host "  Script default       : $SubscriptionName" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Playground    (dev/test)" -ForegroundColor DarkGray
Write-Host "  [2] ProductionCSP (production)" -ForegroundColor DarkGray
Write-Host ""
if ($SkipPrompt) {
    Write-Host "  Using (SkipPrompt): $SubscriptionName" -ForegroundColor Gray
} else {
    $subChoice = Read-Host "  Press Enter to use default '$SubscriptionName', or type 1/2/custom name"
    switch ($subChoice.Trim()) {
        "1"     { $SubscriptionName = "Playground" }
        "2"     { $SubscriptionName = "ProductionCSP" }
        { $_ -ne "" -and $_ -ne "1" -and $_ -ne "2" } { $SubscriptionName = $subChoice.Trim() }
        default { Write-Host "  Using: $SubscriptionName" -ForegroundColor Gray }
    }
}

az account set --subscription $SubscriptionName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription '$SubscriptionName'." }
$account = az account show | ConvertFrom-Json
Ok "Subscription: $($account.name)"

# -- Image tag ---------------------------------------------------------------
if (-not $ImageTag) {
    $gitTag = git -C $scriptRoot rev-parse --short HEAD 2>$null
    $ImageTag = if ($gitTag) { $gitTag.Trim() } else { Get-Date -Format "yyyy-MM-dd-1" }
    Write-Host "  Image tag: $ImageTag" -ForegroundColor Gray
}
$image = "$AcrName.azurecr.io/$ImageRepository`:$ImageTag"

# -- Build image -------------------------------------------------------------
if (-not $SkipBuild) {
    Step "Building and pushing image..."
    & "$scriptRoot\Build-HermesImage.ps1" `
      -SubscriptionName $SubscriptionName `
      -AcrName $AcrName `
      -ImageTag $ImageTag
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
    Ok "Pushed: $image"
} else {
    Write-Host "  Skipping build. Target image: $image" -ForegroundColor Gray
}

# -- Get storage key ---------------------------------------------------------
Step "Getting Azure Files storage key"
$storageKey = az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $ResourceGroup `
  --query "[0].value" --output tsv
if ($LASTEXITCODE -ne 0 -or -not $storageKey) { throw "Could not get storage key for '$StorageAccount'. Run Initialize-HermesPlatform.ps1 first." }
Ok "Storage key retrieved."

# -- Get ACR admin password --------------------------------------------------
Step "Getting ACR credentials"
$acrPassword = az acr credential show --name $AcrName --query "passwords[0].value" --output tsv
if ($LASTEXITCODE -ne 0 -or -not $acrPassword) { throw "Could not get ACR credentials. Run Initialize-HermesPlatform.ps1 first." }
Ok "ACR credentials retrieved."

# ===========================================================================
# SETUP MODE: provision ACA environment + create container app with volume
# ===========================================================================
if ($Setup) {

    Step "Creating ACA Environment (if needed): $AcaEnvName"
    $envExists = $false
    try { az containerapp env show --name $AcaEnvName --resource-group $ResourceGroup --output none 2>$null; $envExists = $true } catch {}
    if (-not $envExists) {
        az containerapp env create `
          --name $AcaEnvName `
          --resource-group $ResourceGroup `
          --location $Location `
          --output none
        if ($LASTEXITCODE -ne 0) { throw "az containerapp env create failed." }
        Ok "Created."
    } else { Warn "Already exists." }

    Step "Registering Azure Files storage with ACA environment"
    az containerapp env storage set `
      --name $AcaEnvName `
      --resource-group $ResourceGroup `
      --storage-name hermes-data `
      --azure-file-account-name $StorageAccount `
      --azure-file-account-key $storageKey `
      --azure-file-share-name $FileShareName `
      --access-mode ReadWrite `
      --output none
    if ($LASTEXITCODE -ne 0) { throw "az containerapp env storage set failed." }
    Ok "Azure Files storage registered as 'hermes-data'."

    Step "Creating Container App (phase 1 - no volume): $ContainerAppName"
    $appExists = $false
    try { az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --output none 2>$null; $appExists = $true } catch {}
    if (-not $appExists) {
        az containerapp create `
          --name $ContainerAppName `
          --resource-group $ResourceGroup `
          --environment $AcaEnvName `
          --image $image `
          --target-port $StudioBotPort `
          --ingress external `
          --transport http `
          --cpu 2.0 `
          --memory "4Gi" `
          --min-replicas 1 `
          --max-replicas 1 `
          --registry-server "$AcrName.azurecr.io" `
          --registry-username $AcrName `
          --registry-password $acrPassword `
          --env-vars "HERMES_DASHBOARD=1" "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$dashUser" "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$dashPass" "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$dashSecret" `
          --output none
        if ($LASTEXITCODE -ne 0) { throw "az containerapp create failed." }
        Ok "Container App created (no volume yet)."
    } else {
        Ok "Container App already exists - skipping create."
    }

    Step "Patching volume mount onto Container App (phase 2)"
    $subId = (az account show --query id --output tsv).Trim()
    $patchUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/$($ContainerAppName)?api-version=2024-03-01"

    $patch = [ordered]@{
        properties = [ordered]@{
            template = [ordered]@{
                containers = @(
                    [ordered]@{
                        name         = "hermes"
                        image        = $image
                        resources    = [ordered]@{ cpu = 2.0; memory = "4Gi" }
                        env          = @(
                            [ordered]@{ name = "HERMES_DASHBOARD"; value = "1" }
                            [ordered]@{ name = "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"; value = $dashUser }
                            [ordered]@{ name = "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"; value = $dashPass }
                            [ordered]@{ name = "HERMES_DASHBOARD_BASIC_AUTH_SECRET"; value = $dashSecret }
                        )
                        volumeMounts = @(
                            [ordered]@{ volumeName = "hermes-data"; mountPath = "/opt/data" }
                        )
                    }
                )
                volumes = @(
                    [ordered]@{ name = "hermes-data"; storageType = "AzureFile"; storageName = "hermes-data" }
                )
            }
        }
    }
    $patchJson = $patch | ConvertTo-Json -Depth 20
    $patchFile = Join-Path $env:TEMP "hermes-patch.json"
    [System.IO.File]::WriteAllText($patchFile, $patchJson, [System.Text.UTF8Encoding]::new($false))
    az rest --method PATCH --uri $patchUrl --body "@$patchFile" --headers "Content-Type=application/json" --output none
    Remove-Item $patchFile -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) { throw "az rest PATCH volume mount failed." }
    Ok "Azure Files volume mount patched in."
}

# ===========================================================================
# PUSH MODE: update image only (volume config persists from setup)
# ===========================================================================
if ($Push) {
    Step "Updating container app image (new revision)"
    $revSuffix = "r$(Get-Date -Format 'yyMMddHHmm')"
    az containerapp update `
      --name $ContainerAppName `
      --resource-group $ResourceGroup `
      --image $image `
      --revision-suffix $revSuffix `
      --output none
    if ($LASTEXITCODE -ne 0) { throw "az containerapp update failed." }
    Ok "New revision: $revSuffix - image: $image"
}

# -- Get FQDN ----------------------------------------------------------------
Step "Retrieving app FQDN (waiting for provisioning)"
$fqdn = $null
for ($i = 1; $i -le 12; $i++) {
    $fqdn = az containerapp show `
      --name $ContainerAppName `
      --resource-group $ResourceGroup `
      --query "properties.configuration.ingress.fqdn" --output tsv 2>$null
    if ($fqdn -and $fqdn.Trim()) { $fqdn = $fqdn.Trim(); break }
    Write-Host "  Waiting for FQDN (attempt $i/12)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 15
}
if (-not $fqdn) { throw "Could not retrieve container app FQDN after 3 minutes." }
Ok "FQDN: $fqdn"

# -- Teams bot endpoint update -----------------------------------------------
if (-not $SkipTeamsUpdate) {
    Step "Updating Hermes Studio Teams bot endpoint"
    $teamsEndpoint = "https://$fqdn/api/messages"
    Write-Host "  Bot ID  : $StudioBotAppId" -ForegroundColor Gray
    Write-Host "  Endpoint: $teamsEndpoint" -ForegroundColor Gray
    Write-Host ""

    if (-not (Get-Command teams -ErrorAction SilentlyContinue)) {
        Warn "Teams CLI not found. Install with: npm install -g '@microsoft/teams.cli@preview'"
        Warn "Then run manually: teams app update $StudioBotAppId --endpoint $teamsEndpoint"
    } else {
        teams app update $StudioBotAppId --endpoint $teamsEndpoint
        if ($LASTEXITCODE -ne 0) {
            Warn "teams app update returned non-zero. Check above output."
            Warn "Manual command: teams app update $StudioBotAppId --endpoint $teamsEndpoint"
        } else {
            Ok "Teams Studio bot endpoint updated."
        }
    }
}

# -- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Hermes deployed to Azure Container Apps" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Teams bot URL : https://$fqdn/api/messages" -ForegroundColor Green
Write-Host "  Dashboard URL : https://$fqdn:9119  (internal only)" -ForegroundColor Gray
Write-Host "  Image         : $image" -ForegroundColor Gray
Write-Host "  Volume        : /opt/data <- Azure Files ($StorageAccount/$FileShareName)" -ForegroundColor Gray
Write-Host "=========================================================" -ForegroundColor Green

# -- Verify ------------------------------------------------------------------
if (-not $SkipVerify) {
    Step "Verifying deployment..."
    $sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
    & "$sdir\Verify-HermesDeploy.ps1" `
      -SubscriptionName $SubscriptionName `
      -ResourceGroup $ResourceGroup `
      -AppName $ContainerAppName `
      -Fqdn $fqdn
}
