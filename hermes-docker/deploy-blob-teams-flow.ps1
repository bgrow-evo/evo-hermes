#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy the "blob -> Teams" Azure Logic App (scriptable equivalent of the Power
    Automate flow): when a PIM-ready ZIP lands in the studio blob container, mint a
    read SAS link and post it to a Teams channel Incoming Webhook.

.DESCRIPTION
    Deploys flows/blob-to-teams.logicapp.json. The script:
      - fetches the storage account key (for the Logic App's blob connection + SAS),
      - computes the blob connector folderId for the container,
      - deploys the connection + Logic App via `az deployment group create`.

    Why a Logic App and not a Power Automate cloud flow: cloud flows can't be created
    non-interactively (connector consent), whereas a Logic App is ARM-deployable.
    Delivery uses a Teams Incoming Webhook (an HTTP POST), so there is NO Teams OAuth
    connection to authorize. The blob connection uses the account key, so the agent
    never needs it.

    ONE manual prerequisite: create an Incoming Webhook in the target Teams channel
    (channel ... -> Manage channel -> Connectors -> Incoming Webhook -> Create), copy
    its URL, and pass it as -TeamsWebhookUrl.

    Requires Azure CLI logged in (`az login`).

.PARAMETER ResourceGroup   Default "rg-hermes-studio".
.PARAMETER StorageAccount  The studio storage account (e.g. evohermesstudio98255).
.PARAMETER Container       Default "studio-outbox".
.PARAMETER TeamsWebhookUrl The Teams channel Incoming Webhook URL.
.PARAMETER LogicAppName    Default "studio-blob-to-teams".
.PARAMETER Location        Default = the resource group's location.
.PARAMETER SasValidDays    SAS link lifetime in days. Default 7.

.EXAMPLE
    .\deploy-blob-teams-flow.ps1 -StorageAccount evohermesstudio98255 `
        -TeamsWebhookUrl "https://evo.webhook.office.com/webhookb2/...."
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup  = "rg-hermes-studio",
    [Parameter(Mandatory)] [string]$StorageAccount,
    [string]$Container      = "studio-outbox",
    [Parameter(Mandatory)] [string]$TeamsWebhookUrl,
    [string]$LogicAppName   = "studio-blob-to-teams",
    [string]$Location,
    [int]$SasValidDays      = 7
)

$ErrorActionPreference = "Stop"
function Step($m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m){   Write-Host "    $m" -ForegroundColor Green }
function Warn($m){ Write-Host "    $m" -ForegroundColor Yellow }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Template  = Join-Path $ScriptDir "flows\blob-to-teams.logicapp.json"
if (-not (Test-Path $Template)) { throw "Template not found: $Template" }
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI (az) not found on PATH." }

Step "Preflight"
$raw = az account show -o json
if ($LASTEXITCODE -ne 0 -or -not $raw) { throw "Not logged in to Azure. Run 'az login' first." }
Ok "Azure session OK."
if (-not $Location) {
    $Location = az group show -n $ResourceGroup --query location -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $Location) { throw "Could not read location of resource group '$ResourceGroup'." }
}
Ok "Resource group '$ResourceGroup' ($Location)."

Step "Fetching storage account key"
$key = az storage account keys list -g $ResourceGroup -n $StorageAccount --query "[0].value" -o tsv
if ($LASTEXITCODE -ne 0 -or -not $key) { throw "Could not read storage key (account '$StorageAccount' in '$ResourceGroup')." }
Ok "Got account key."

# Azure Blob connector folderId for a container = base64 of the URL-encoded path
# ('%2f' + container), e.g. studio-outbox -> JTJmc3R1ZGlvLW91dGJveA==
$folderId = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('%2f' + $Container))
Ok "Computed folderId for '/$Container': $folderId"

Step "Deploying Logic App '$LogicAppName'"
$dep = "studio-blob-to-teams-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
az deployment group create `
    -g $ResourceGroup `
    -n $dep `
    --template-file $Template `
    --parameters `
        logicAppName=$LogicAppName `
        location=$Location `
        storageAccount=$StorageAccount `
        storageKey=$key `
        container=$Container `
        folderId=$folderId `
        teamsWebhookUrl=$TeamsWebhookUrl `
        sasValidDays=$SasValidDays `
    -o none
if ($LASTEXITCODE -ne 0) { throw "Deployment failed (see az output above)." }
Ok "Logic App deployed and enabled."

Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " '$LogicAppName' is live: watches '$Container' (every 5 min) for *_pim-ready.zip," -ForegroundColor Green
Write-Host " mints a $SasValidDays-day read SAS link, and posts it to your Teams webhook." -ForegroundColor Green
Write-Host " Verify / tweak in the portal:" -ForegroundColor White
Write-Host "   Resource groups -> $ResourceGroup -> $LogicAppName -> Logic app designer" -ForegroundColor White
Write-Host " If the trigger shows no runs after a test upload, open the trigger once and" -ForegroundColor Yellow
Write-Host " re-select container '$Container' (confirms the folderId), then Save." -ForegroundColor Yellow
Write-Host " Test now:" -ForegroundColor White
Write-Host "   docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf copy <a.zip> agent-blob:$Container/test/ " -ForegroundColor White
Write-Host "----------------------------------------------------------------" -ForegroundColor White
