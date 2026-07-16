<#
.SYNOPSIS
  Build and push the Hermes Docker image to ACR via az acr build.

.EXAMPLE
  .\Build-HermesImage.ps1
  .\Build-HermesImage.ps1 -ImageTag abc1234
#>
[CmdletBinding()]
param(
    [string]$AcrName          = "acrhermessbx",
    [string]$SubscriptionName = "",
    [string]$ImageRepository  = "hermes",
    [string]$ImageTag         = "latest",
    [string]$SourcePath       = "",
    [string]$DockerfilePath   = "Dockerfile"
)

$ErrorActionPreference = "Stop"

if (-not $SourcePath) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourcePath = (Resolve-Path (Join-Path $scriptRoot "..\..")).Path
}

if ($SubscriptionName) {
    Write-Host "Setting subscription: $SubscriptionName" -ForegroundColor Cyan
    az account set --subscription $SubscriptionName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "az account set failed." }
}

Write-Host ""
Write-Host "Building Hermes image in ACR..." -ForegroundColor Cyan
Write-Host "  ACR:    $AcrName"
Write-Host "  Image:  $ImageRepository`:$ImageTag"
Write-Host "  Source: $SourcePath"
Write-Host ""
Write-Host "  Note: the base image pinned in Dockerfile (BASE_IMAGE," -ForegroundColor Gray
Write-Host "  currently nousresearch/hermes-agent:v2026.7.7.2) is pulled" -ForegroundColor Gray
Write-Host "  from Docker Hub during the cloud build." -ForegroundColor Gray
Write-Host ""

$imageTags = if ($ImageTag -ne "latest") { "$ImageRepository`:$ImageTag", "$ImageRepository`:latest" } else { @("$ImageRepository`:latest") }
$imageArgs = $imageTags | ForEach-Object { "--image"; $_ }

az acr build `
  --registry $AcrName `
  @imageArgs `
  --file (Join-Path $SourcePath $DockerfilePath) `
  $SourcePath

if ($LASTEXITCODE -ne 0) { throw "az acr build failed." }

Write-Host ""
Write-Host "Build complete: $AcrName.azurecr.io/$ImageRepository`:$ImageTag" -ForegroundColor Green
