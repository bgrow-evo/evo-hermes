<#
.SYNOPSIS
  Deploy Hermes to Azure Container Apps using Standard Azure Files as a backing store.

.DESCRIPTION
  The Standard Azure Files share is mounted at /mnt/hermes-persist. Hermes runs on
  /opt/data backed by ACA EmptyDir so s6/Hermes can use normal Linux permissions.
  The image wrapper syncs data between the two paths.

.EXAMPLE
  .\Deploy-HermesStandardStorage.ps1 -Setup -SkipPrompt
  .\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$Push,
    [string]$SubscriptionName  = "Playground",
    [string]$ResourceGroup     = "rg-hermes-sbx",
    [string]$Location          = "westus2",
    [string]$AcrName           = "acrhermessbx",
    [string]$StorageAccount    = "sthermessbxwu2",
    [string]$FileShareName     = "hermes-data",
    [string]$AcaEnvName        = "aca-env-hermes-nfs-sbx-wu2",
    [string]$ContainerAppName  = "aca-hermes-nfs",
    [string]$ImageRepository   = "hermes",
    [string]$ImageTag          = "",
    [string]$DefaultBotAppId   = "3146b701-6559-4671-b9d9-91e7508884b1",
    [string]$StudioBotAppId    = "521aaadb-ab96-4275-be9e-37bdb285ffc8",
    [int]$ProxyPort            = 8080,
    [int]$DefaultBotPort       = 3978,
    [int]$StudioBotPort        = 3979,
    [ValidateSet("studio", "default")]
    [string]$ProxyDefaultProfile = "studio",
    [bool]$SharedTeamsApp      = $true,
    [switch]$SkipBuild,
    [switch]$SkipTeamsUpdate,
    [switch]$SkipVerify,
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Read-DotEnv($path) {
    $values = @{}
    if (-not (Test-Path $path)) { return $values }
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#' -or $line -notmatch '^\s*([^#=\s]+)\s*=\s*(.*)\s*$') { continue }
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}
function Add-EnvValue([System.Collections.ArrayList]$target, [hashtable]$source, [string]$name) {
    if ($source.ContainsKey($name) -and $source[$name]) {
        [void]$target.Add([ordered]@{ name = $name; value = $source[$name] })
    }
}
function Add-SecretEnv([System.Collections.ArrayList]$envTarget, [System.Collections.ArrayList]$secretTarget, [hashtable]$source, [string]$envName, [string]$secretName) {
    if ($source.ContainsKey($envName) -and $source[$envName]) {
        [void]$secretTarget.Add([ordered]@{ name = $secretName; value = $source[$envName] })
        [void]$envTarget.Add([ordered]@{ name = $envName; secretRef = $secretName })
    }
}

if (-not $Setup -and -not $Push) {
    Write-Host "Usage:"
    Write-Host "  .\Deploy-HermesStandardStorage.ps1 -Setup -SkipPrompt"
    Write-Host "  .\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt"
    exit 0
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path

Step "Checking Azure CLI login"
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login
    $account = az account show | ConvertFrom-Json
}
Ok "Logged in as $($account.user.name)"

if (-not $SkipPrompt) {
    Write-Host ""
    Write-Host "  Current subscription : $($account.name)" -ForegroundColor White
    Write-Host "  Script default       : $SubscriptionName" -ForegroundColor White
    $subChoice = Read-Host "  Press Enter to use default '$SubscriptionName', or type 1/2/custom name"
    switch ($subChoice.Trim()) {
        "1"     { $SubscriptionName = "Playground" }
        "2"     { $SubscriptionName = "ProductionCSP" }
        { $_ -ne "" -and $_ -ne "1" -and $_ -ne "2" } { $SubscriptionName = $subChoice.Trim() }
    }
}

az account set --subscription $SubscriptionName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription '$SubscriptionName'." }

if (-not $ImageTag) {
    $gitTag = git -C $repoRoot rev-parse --short HEAD 2>$null
    $ImageTag = if ($gitTag) { $gitTag.Trim() } else { Get-Date -Format "yyyyMMddHHmm" }
}
$image = "$AcrName.azurecr.io/$ImageRepository`:$ImageTag"

if (-not $SkipBuild) {
    Step "Building and pushing image"
    & "$scriptRoot\Build-HermesImage.ps1" `
      -SubscriptionName $SubscriptionName `
      -AcrName $AcrName `
      -ImageTag $ImageTag
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
    Ok "Pushed: $image"
} else {
    Warn "Skipping build. Target image: $image"
}

Step "Getting storage and registry credentials"
$storageKey = az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $ResourceGroup `
  --query "[0].value" --output tsv
if ($LASTEXITCODE -ne 0 -or -not $storageKey) { throw "Could not get storage key for '$StorageAccount'." }

$acrPassword = az acr credential show --name $AcrName --query "passwords[0].value" --output tsv
if ($LASTEXITCODE -ne 0 -or -not $acrPassword) { throw "Could not get ACR credentials." }
Ok "Credentials resolved."

$hermesEnvPath = Join-Path $env:USERPROFILE ".hermes\.env"
$hermesEnv = Read-DotEnv $hermesEnvPath
if ($hermesEnv.Count -gt 0) {
    Ok "Loaded Hermes runtime env keys from $hermesEnvPath (values redacted)."
} else {
    Warn "No Hermes runtime env found at $hermesEnvPath; Teams credentials must already be in config/env."
}

$studioEnvPath = Join-Path $env:USERPROFILE ".hermes\profiles\studio\.env"
$studioEnv = Read-DotEnv $studioEnvPath
if ($studioEnv.Count -gt 0) {
    Ok "Loaded Studio profile env keys from $studioEnvPath (values redacted)."
    $studioMap = @{
        "TEAMS_CLIENT_ID" = "STUDIO_TEAMS_CLIENT_ID"
        "TEAMS_CLIENT_SECRET" = "STUDIO_TEAMS_CLIENT_SECRET"
        "TEAMS_TENANT_ID" = "STUDIO_TEAMS_TENANT_ID"
        "TEAMS_HOME_CHANNEL" = "STUDIO_TEAMS_HOME_CHANNEL"
        "TEAMS_HOME_CHANNEL_NAME" = "STUDIO_TEAMS_HOME_CHANNEL_NAME"
    }
    foreach ($key in $studioMap.Keys) {
        if ($studioEnv.ContainsKey($key) -and $studioEnv[$key] -and -not $hermesEnv.ContainsKey($studioMap[$key])) {
            $hermesEnv[$studioMap[$key]] = $studioEnv[$key]
        }
    }
}

if ($SharedTeamsApp) {
    foreach ($pair in @(
        @("TEAMS_CLIENT_ID", "STUDIO_TEAMS_CLIENT_ID"),
        @("TEAMS_CLIENT_SECRET", "STUDIO_TEAMS_CLIENT_SECRET"),
        @("TEAMS_TENANT_ID", "STUDIO_TEAMS_TENANT_ID")
    )) {
        if ($hermesEnv.ContainsKey($pair[0]) -and $hermesEnv[$pair[0]]) {
            $hermesEnv[$pair[1]] = $hermesEnv[$pair[0]]
        }
    }
    Ok "Shared Teams app mode enabled: studio gateway will validate the same bot identity as default."
}

$acaSecrets = [System.Collections.ArrayList]@(
    [ordered]@{ name = "acr-password"; value = $acrPassword }
)
$sharedTeamsAppValue = if ($SharedTeamsApp) { "1" } else { "0" }
$acaEnv = [System.Collections.ArrayList]@(
    [ordered]@{ name = "HERMES_DASHBOARD"; value = "0" }
    [ordered]@{ name = "HERMES_PROFILE"; value = "studio" }
    [ordered]@{ name = "HERMES_SYNC_INTERVAL_SECONDS"; value = "60" }
    [ordered]@{ name = "HERMES_PROXY_PORT"; value = "$ProxyPort" }
    [ordered]@{ name = "HERMES_DEFAULT_TEAMS_PORT"; value = "$DefaultBotPort" }
    [ordered]@{ name = "HERMES_STUDIO_TEAMS_PORT"; value = "$StudioBotPort" }
    [ordered]@{ name = "HERMES_PROXY_DEFAULT_PROFILE"; value = $ProxyDefaultProfile }
    [ordered]@{ name = "HERMES_TEAMS_SHARED_APP"; value = $sharedTeamsAppValue }
    [ordered]@{ name = "HERMES_TEAMS_PROFILE_ROUTES"; value = "/opt/data/teams-profile-routes.yaml" }
    [ordered]@{ name = "HERMES_TEAMS_ROUTE_UNKNOWN_POLICY"; value = "deny" }
)
foreach ($name in @(
    "TEAMS_CLIENT_ID",
    "TEAMS_TENANT_ID",
    "TEAMS_ALLOWED_USERS",
    "TEAMS_ALLOW_ALL_USERS",
    "TEAMS_HOME_CHANNEL",
    "TEAMS_HOME_CHANNEL_NAME",
    "STUDIO_TEAMS_CLIENT_ID",
    "STUDIO_TEAMS_TENANT_ID",
    "STUDIO_TEAMS_HOME_CHANNEL",
    "STUDIO_TEAMS_HOME_CHANNEL_NAME",
    # teams_graph (hermes-ai user chat adapter): shared identity + per-profile
    # chat IDs consumed by hermes-aca-configure-profiles.sh at cont-init.
    "TEAMS_GRAPH_CLIENT_ID",
    "TEAMS_GRAPH_TENANT_ID",
    "HERMES_ADMIN_CHAT_ID",
    "STUDIO_CHAT_ID",
    "DISCO_CHAT_ID",
    # Azure Key Vault for agent secrets (read via system-assigned managed identity)
    "HERMES_KEYVAULT_URI"
)) {
    Add-EnvValue $acaEnv $hermesEnv $name
}
Add-SecretEnv $acaEnv $acaSecrets $hermesEnv "TEAMS_CLIENT_SECRET" "teams-client-secret"
Add-SecretEnv $acaEnv $acaSecrets $hermesEnv "STUDIO_TEAMS_CLIENT_SECRET" "studio-teams-client-secret"

if ($Setup) {
    Step "Ensuring ACA environment: $AcaEnvName"
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
    } else {
        Ok "Environment exists."
    }

    Step "Registering Standard Azure Files backing store"
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
    Ok "Registered Standard Azure Files storage as 'hermes-data'."

    Step "Ensuring Container App shell exists: $ContainerAppName"
    $appExists = $false
    try { az containerapp show --name $ContainerAppName --resource-group $ResourceGroup --output none 2>$null; $appExists = $true } catch {}
    if (-not $appExists) {
        az containerapp create `
          --name $ContainerAppName `
          --resource-group $ResourceGroup `
          --environment $AcaEnvName `
          --image $image `
          --target-port $ProxyPort `
          --ingress external `
          --transport http `
          --cpu 2.0 `
          --memory "4Gi" `
          --min-replicas 1 `
          --max-replicas 1 `
          --registry-server "$AcrName.azurecr.io" `
          --registry-username $AcrName `
          --registry-password $acrPassword `
          --args "/bin/sleep" "infinity" `
          --env-vars "HERMES_DASHBOARD=0" "HERMES_PROFILE=studio" "HERMES_SYNC_INTERVAL_SECONDS=60" "HERMES_PROXY_PORT=$ProxyPort" "HERMES_DEFAULT_TEAMS_PORT=$DefaultBotPort" "HERMES_STUDIO_TEAMS_PORT=$StudioBotPort" "HERMES_PROXY_DEFAULT_PROFILE=$ProxyDefaultProfile" `
          --output none
        if ($LASTEXITCODE -ne 0) { throw "az containerapp create failed." }
        Ok "Container App created."
    } else {
        Ok "Container App exists."
    }
}

Step "Patching app with EmptyDir live storage + Standard Azure Files backing store"
$subId = (az account show --query id --output tsv).Trim()
$patchUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.App/containerApps/$($ContainerAppName)?api-version=2024-03-01"
$revSuffix = "std$(Get-Date -Format 'yyMMddHHmm')"

$patch = [ordered]@{
    properties = [ordered]@{
        configuration = [ordered]@{
            ingress = [ordered]@{
                external = $true
                targetPort = $ProxyPort
                transport = "http"
                allowInsecure = $false
            }
            registries = @(
                [ordered]@{
                    server = "$AcrName.azurecr.io"
                    username = $AcrName
                    passwordSecretRef = "acr-password"
                }
            )
            secrets = @($acaSecrets)
        }
        template = [ordered]@{
            revisionSuffix = $revSuffix
            containers = @(
                [ordered]@{
                    name = $ContainerAppName
                    image = $image
                    args = @("/bin/sleep", "infinity")
                    resources = [ordered]@{ cpu = 2.0; memory = "4Gi" }
                    # Boot restore copies the full data share (incl. the disco
                    # profile's ~7k-file Projects tree) over SMB before s6 starts
                    # the proxy; ACA's default startup window is too short and
                    # kills the container mid-restore. 10 minutes still wasn't
                    # enough once the disco tree landed - allow up to 20 minutes
                    # (240 x 5s; ACA caps failureThreshold at 240).
                    probes = @(
                        [ordered]@{
                            type = "Startup"
                            tcpSocket = [ordered]@{ port = $ProxyPort }
                            periodSeconds = 5
                            failureThreshold = 240
                            timeoutSeconds = 3
                        },
                        [ordered]@{
                            type = "Liveness"
                            tcpSocket = [ordered]@{ port = $ProxyPort }
                            periodSeconds = 10
                            failureThreshold = 6
                            timeoutSeconds = 3
                        }
                    )
                    env = @($acaEnv)
                    volumeMounts = @(
                        [ordered]@{ volumeName = "hermes-live"; mountPath = "/opt/data" }
                        [ordered]@{ volumeName = "hermes-persist"; mountPath = "/mnt/hermes-persist" }
                    )
                }
            )
            volumes = @(
                [ordered]@{ name = "hermes-live"; storageType = "EmptyDir" }
                [ordered]@{ name = "hermes-persist"; storageType = "AzureFile"; storageName = "hermes-data" }
            )
            scale = [ordered]@{ minReplicas = 1; maxReplicas = 1 }
        }
    }
}

$patchJson = $patch | ConvertTo-Json -Depth 30
$patchFile = Join-Path $env:TEMP "hermes-standard-storage-patch.json"
[System.IO.File]::WriteAllText($patchFile, $patchJson, [System.Text.UTF8Encoding]::new($false))
az rest --method PATCH --uri $patchUrl --body "@$patchFile" --headers "Content-Type=application/json" --output none
Remove-Item $patchFile -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "az rest PATCH failed." }
Ok "Revision requested: $revSuffix"

Step "Retrieving app FQDN"
$fqdn = az containerapp show `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --query "properties.configuration.ingress.fqdn" --output tsv
if (-not $fqdn) { throw "Could not retrieve FQDN." }
Ok "FQDN: $fqdn"

if (-not $SkipTeamsUpdate) {
    $sharedEndpoint = "https://$fqdn/api/messages"
    $defaultEndpoint = if ($SharedTeamsApp) { $sharedEndpoint } else { "https://$fqdn/default/api/messages" }
    $studioEndpoint = "https://$fqdn/studio/api/messages"

    if (-not (Get-Command teams -ErrorAction SilentlyContinue)) {
        Warn "Teams CLI not found. Manual commands:"
        Warn "  teams app update $DefaultBotAppId --endpoint $defaultEndpoint"
        if (-not $SharedTeamsApp) { Warn "  teams app update $StudioBotAppId --endpoint $studioEndpoint" }
    } else {
        Step "Updating Hermes Teams bot endpoint"
        teams app update $DefaultBotAppId --endpoint $defaultEndpoint
        if ($LASTEXITCODE -ne 0) {
            Warn "Hermes bot update failed. Manual: teams app update $DefaultBotAppId --endpoint $defaultEndpoint"
        } else {
            Ok "Hermes bot endpoint updated."
        }

        if ($SharedTeamsApp) {
            Warn "Shared Teams app mode: leave old Hermes Studio app disabled/unused; install Hermes app in each routed channel."
        } else {
            Step "Updating Hermes Studio Teams bot endpoint"
            teams app update $StudioBotAppId --endpoint $studioEndpoint
            if ($LASTEXITCODE -ne 0) {
                Warn "Studio bot update failed. Manual: teams app update $StudioBotAppId --endpoint $studioEndpoint"
            } else {
                Ok "Studio bot endpoint updated."
            }
        }
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Hermes standard-storage deployment requested" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Shared Teams URL  : https://$fqdn/api/messages" -ForegroundColor Green
Write-Host "  Studio Teams URL  : https://$fqdn/studio/api/messages (legacy/debug)" -ForegroundColor Green
Write-Host "  Default Teams URL : https://$fqdn/default/api/messages (legacy/debug)" -ForegroundColor Green
Write-Host "  ACA ingress       : 443 -> container $ProxyPort -> profile ports $DefaultBotPort/$StudioBotPort" -ForegroundColor Gray
Write-Host "  Image         : $image" -ForegroundColor Gray
Write-Host "  Live data     : /opt/data <- EmptyDir" -ForegroundColor Gray
Write-Host "  Durable data  : /mnt/hermes-persist <- Azure Files SMB ($StorageAccount/$FileShareName)" -ForegroundColor Gray
Write-Host "=========================================================" -ForegroundColor Green

if (-not $SkipVerify) {
    Step "Revision status"
    az containerapp revision list `
      --name $ContainerAppName `
      --resource-group $ResourceGroup `
      --query "[].{Revision:name,Health:properties.healthState,Active:properties.active,Replicas:properties.replicas,Provisioning:properties.provisioningState}" `
      --output table
}
