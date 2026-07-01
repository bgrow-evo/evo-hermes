<#
.SYNOPSIS
  One-time migration: upload local ~/.hermes data to Azure Files.

.DESCRIPTION
  Uploads the local Hermes data directory (HERMES_DATA from .env, or
  ~/.hermes by default) to the Azure Files share that backs /opt/data
  in the container.

  Run this BEFORE Deploy-HermesAzure.ps1 -Setup to ensure all auth tokens,
  profiles, config.yaml, rclone.conf etc. are available in the cloud container.

  The upload is non-destructive: local files are NOT deleted. Re-running is
  safe — existing files are overwritten, nothing is removed on the share.

.EXAMPLE
  .\Migrate-HermesVolume.ps1
  .\Migrate-HermesVolume.ps1 -DryRun         # preview only, no upload
  .\Migrate-HermesVolume.ps1 -LocalPath C:\custom\.hermes
#>
[CmdletBinding()]
param(
    [string]$SubscriptionName = "Playground",
    [string]$ResourceGroup    = "rg-hermes-sbx",
    [string]$StorageAccount   = "sthermessbxwu2",
    [string]$FileShareName    = "hermes-data",
    [string]$LocalPath        = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

# ── Resolve local source path ─────────────────────────────────────────────────
if (-not $LocalPath) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $envFile = Join-Path (Resolve-Path (Join-Path $scriptRoot "..\..")).Path ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile | Where-Object { $_ -match '^\s*HERMES_DATA=' }
        if ($envContent -match '=(.+)$') {
            $LocalPath = $Matches[1].Trim()
        }
    }
    if (-not $LocalPath) {
        $LocalPath = Join-Path $env:USERPROFILE ".hermes"
    }
}

if (-not (Test-Path $LocalPath)) {
    throw "Local Hermes data directory not found: $LocalPath"
}

$fileCount = (Get-ChildItem -Path $LocalPath -Recurse -File).Count
Step "Source: $LocalPath ($fileCount files)"

if ($DryRun) {
    Write-Host ""
    Write-Host "  DRY RUN - no files will be uploaded." -ForegroundColor Yellow
    Write-Host "  Would upload $fileCount files to: $StorageAccount/$FileShareName/" -ForegroundColor Yellow
    Write-Host ""
    $preview = Get-ChildItem -Path $LocalPath -Recurse -File | Select-Object -First 20
    foreach ($f in $preview) {
        $rel = $f.FullName.Replace($LocalPath, "")
        Write-Host "    $rel" -ForegroundColor Gray
    }
    if ($fileCount -gt 20) {
        $more = $fileCount - 20
        Write-Host "    ... and $more more" -ForegroundColor DarkGray
    }
    return
}

# ── Set subscription ──────────────────────────────────────────────────────────
Step "Setting subscription: $SubscriptionName"
az account set --subscription $SubscriptionName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "az account set failed." }
Ok "Subscription set."

# ── Get storage key ───────────────────────────────────────────────────────────
Step "Getting storage account key"
$storageKey = az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $ResourceGroup `
  --query "[0].value" --output tsv
if ($LASTEXITCODE -ne 0 -or -not $storageKey) { throw "Could not get storage key for '$StorageAccount'." }
Ok "Key retrieved."

# ── Verify file share exists ──────────────────────────────────────────────────
Step "Verifying file share: $FileShareName"
$shareExists = az storage share exists `
  --name $FileShareName `
  --account-name $StorageAccount `
  --account-key $storageKey `
  --query "exists" --output tsv
if ($shareExists -ne "true") {
    throw "File share '$FileShareName' does not exist in '$StorageAccount'. Run Initialize-HermesPlatform.ps1 first."
}
Ok "Share exists."

# ── Upload ────────────────────────────────────────────────────────────────────
Step "Uploading local Hermes data to Azure Files..."
Write-Host ""
Write-Host "  Source : $LocalPath" -ForegroundColor Gray
Write-Host "  Dest   : $StorageAccount/$FileShareName/" -ForegroundColor Gray
Write-Host "  Files  : $fileCount" -ForegroundColor Gray
Write-Host ""
Write-Host "  This will take a few minutes depending on volume size." -ForegroundColor DarkGray
Write-Host ""

$tempSource = Join-Path $env:TEMP "hermes-migrate-$(Get-Date -Format 'yyMMddHHmm')"
Write-Host "  Copying to temp dir (excluding .venv/.cache/__pycache__)..." -ForegroundColor DarkGray
robocopy $LocalPath $tempSource /E /XD ".venv" ".cache" "__pycache__" ".git" /NP /NJH /NJS /NFL | Out-Null
Write-Host "  Temp dir: $tempSource" -ForegroundColor DarkGray
$filteredCount = (Get-ChildItem -Path $tempSource -Recurse -File).Count
Write-Host "  Files after exclusions: $filteredCount (excluded venv/cache/pyc)" -ForegroundColor DarkGray
Write-Host ""

az storage file upload-batch `
  --destination $FileShareName `
  --source $tempSource `
  --account-name $StorageAccount `
  --account-key $storageKey

$uploadExit = $LASTEXITCODE
Remove-Item -Path $tempSource -Recurse -Force -ErrorAction SilentlyContinue
if ($uploadExit -ne 0) { throw "az storage file upload-batch failed." }

# ── Verify upload ─────────────────────────────────────────────────────────────
Step "Verifying upload"
$uploadedCount = az storage file list `
  --share-name $FileShareName `
  --account-name $StorageAccount `
  --account-key $storageKey `
  --query "length([])" --output tsv
Ok "Root items visible in share: $uploadedCount"

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Volume migration complete." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Local: $LocalPath" -ForegroundColor Gray
Write-Host "  Azure: $StorageAccount/$FileShareName" -ForegroundColor Gray
Write-Host ""
Write-Host "  IMPORTANT: Auth tokens and profile configs are now in Azure." -ForegroundColor Cyan
Write-Host "  If LLM tokens expire, re-run the Codex OAuth flow inside the" -ForegroundColor Cyan
Write-Host "  ACA container (see README 'Re-auth steps')." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next: .\Deploy-HermesAzure.ps1 -Setup" -ForegroundColor White
