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
    [switch]$SkipBuild,
    [switch]$SkipTeamsUpdate,
    [switch]$SkipVerify,
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

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
            secrets = @(
                [ordered]@{ name = "acr-password"; value = $acrPassword }
            )
        }
        template = [ordered]@{
            revisionSuffix = $revSuffix
            containers = @(
                [ordered]@{
                    name = $ContainerAppName
                    image = $image
                    args = @("/bin/sleep", "infinity")
                    resources = [ordered]@{ cpu = 2.0; memory = "4Gi" }
                    env = @(
                        [ordered]@{ name = "HERMES_DASHBOARD"; value = "0" }
                        [ordered]@{ name = "HERMES_PROFILE"; value = "studio" }
                        [ordered]@{ name = "HERMES_SYNC_INTERVAL_SECONDS"; value = "60" }
                        [ordered]@{ name = "HERMES_PROXY_PORT"; value = "$ProxyPort" }
                        [ordered]@{ name = "HERMES_DEFAULT_TEAMS_PORT"; value = "$DefaultBotPort" }
                        [ordered]@{ name = "HERMES_STUDIO_TEAMS_PORT"; value = "$StudioBotPort" }
                        [ordered]@{ name = "HERMES_PROXY_DEFAULT_PROFILE"; value = $ProxyDefaultProfile }
                    )
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
    $defaultEndpoint = "https://$fqdn/default/api/messages"
    $studioEndpoint = "https://$fqdn/studio/api/messages"

    if (-not (Get-Command teams -ErrorAction SilentlyContinue)) {
        Warn "Teams CLI not found. Manual commands:"
        Warn "  teams app update $DefaultBotAppId --endpoint $defaultEndpoint"
        Warn "  teams app update $StudioBotAppId --endpoint $studioEndpoint"
    } else {
        Step "Updating Hermes (default) Teams bot endpoint"
        teams app update $DefaultBotAppId --endpoint $defaultEndpoint
        if ($LASTEXITCODE -ne 0) {
            Warn "Default bot update failed. Manual: teams app update $DefaultBotAppId --endpoint $defaultEndpoint"
        } else {
            Ok "Default bot endpoint updated."
        }

        Step "Updating Hermes Studio Teams bot endpoint"
        teams app update $StudioBotAppId --endpoint $studioEndpoint
        if ($LASTEXITCODE -ne 0) {
            Warn "Studio bot update failed. Manual: teams app update $StudioBotAppId --endpoint $studioEndpoint"
        } else {
            Ok "Studio bot endpoint updated."
        }
    }
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Hermes standard-storage deployment requested" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Studio Teams URL  : https://$fqdn/studio/api/messages" -ForegroundColor Green
Write-Host "  Default Teams URL : https://$fqdn/default/api/messages" -ForegroundColor Green
Write-Host "  Bare URL routes to studio: https://$fqdn/api/messages" -ForegroundColor Green
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
