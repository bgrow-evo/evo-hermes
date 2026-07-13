<#
.SYNOPSIS
  Verify Hermes ACA deployment health and revision status.
#>
param(
    [string]$SubscriptionName = "Playground",
    [string]$ResourceGroup    = "rg-hermes-sbx",
    [string]$AppName          = "aca-hermes",
    [string]$Fqdn             = "",
    [string]$HealthPath       = "/health",
    [int]$MaxAttempts         = 12,
    [int]$RetrySeconds        = 15
)

$ErrorActionPreference = "Stop"

if ($SubscriptionName) {
    az account set --subscription $SubscriptionName | Out-Null
}

if (-not $Fqdn) {
    $Fqdn = az containerapp show `
      --name $AppName `
      --resource-group $ResourceGroup `
      --query "properties.configuration.ingress.fqdn" --output tsv
    if ($LASTEXITCODE -ne 0 -or -not $Fqdn) { throw "Could not resolve FQDN for '$AppName'." }
}

Write-Host ""
Write-Host "Revision status" -ForegroundColor Cyan
az containerapp revision list `
  --name $AppName `
  --resource-group $ResourceGroup `
  --query "[].{Revision:name, Health:properties.healthState, Active:properties.active, Image:properties.template.containers[0].image}" `
  --output table

Write-Host ""
Write-Host "Health check: https://$Fqdn$HealthPath" -ForegroundColor Cyan
Write-Host "  (ACA external ingress port 443 -> hermes-aca-proxy :8080)" -ForegroundColor DarkGray

$attempt = 0
$success = $false
while ($attempt -lt $MaxAttempts -and -not $success) {
    $attempt++
    try {
        $resp = Invoke-WebRequest -Uri "https://$Fqdn$HealthPath" -UseBasicParsing -TimeoutSec 20 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -lt 400) {
            Write-Host "  [OK] HTTP $($resp.StatusCode) - $($resp.Content.Trim().Substring(0, [Math]::Min(100, $resp.Content.Length)))" -ForegroundColor Green
            $success = $true
        } else {
            Write-Host "  Attempt $attempt/$MaxAttempts - HTTP $($resp.StatusCode), retrying in $RetrySeconds s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetrySeconds
        }
    } catch {
        Write-Host "  Attempt $attempt/$MaxAttempts - $($_.Exception.Message)" -ForegroundColor Yellow
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $RetrySeconds }
    }
}

if (-not $success) {
    Write-Host ""
    Write-Host "  Health check did not pass after $MaxAttempts attempts." -ForegroundColor Red
    Write-Host "  Note: Hermes image is large - allow 3-5 minutes for cold start." -ForegroundColor Yellow
    Write-Host "  Check logs:" -ForegroundColor Yellow
    Write-Host "    az containerapp logs show -n $AppName -g $ResourceGroup --tail 50" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Deployment verified." -ForegroundColor Green
Write-Host "  Default bot : https://$Fqdn/default/api/messages" -ForegroundColor Green
Write-Host "  Studio bot  : https://$Fqdn/studio/api/messages" -ForegroundColor Green
