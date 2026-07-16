<#
.SYNOPSIS
  Create the "Hermes App Users" Entra security group for app access control.

.DESCRIPTION
  Idempotent script. Creates (or finds) the Entra security group "Hermes App Users",
  adds the current user as the initial member. Additional members can be added later
  via Entra admin center or by group owners.

  Once this group exists and is populated, a Teams admin can use the MicrosoftTeams
  PowerShell module to create a custom Teams app permission policy scoped to this
  group, restricting who can install the Hermes apps.

.EXAMPLE
  .\Create-HermesAppUsersGroup.ps1
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

$GroupDisplayName = "Hermes App Users"
$GroupMailNickname = "HermesAppUsers"

Step "Finding or creating Entra security group: $GroupDisplayName"
$existing = az ad group list --display-name "$GroupDisplayName" --query "[0].id" -o tsv 2>$null
if ($existing) {
    $GroupId = $existing
    Ok "Found existing group: $GroupId"
} else {
    Ok "Creating new group..."
    $group = az ad group create --display-name "$GroupDisplayName" --mail-nickname "$GroupMailNickname" | ConvertFrom-Json
    $GroupId = $group.id
    Ok "Created: $GroupId"
}

Step "Getting current user's object ID"
$userId = az ad signed-in-user show --query id -o tsv
Ok "User ID: $userId"

Step "Adding current user to the group (if not already a member)"
$isMember = az ad group member check --group $GroupId --member-id $userId --query value -o tsv 2>$null
if ($isMember -eq "true") {
    Ok "User is already a member of the group"
} else {
    az ad group member add --group $GroupId --member-id $userId
    Ok "User added to group"
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Hermes App Users group ready" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "  Group ID  : $GroupId" -ForegroundColor Gray
Write-Host "  Display   : $GroupDisplayName" -ForegroundColor Gray
Write-Host "  Mail nick : $GroupMailNickname" -ForegroundColor Gray
Write-Host ""
Write-Host "  Additional members can be added via:" -ForegroundColor Cyan
Write-Host "    - Entra admin center (Groups > Hermes App Users > Members)" -ForegroundColor Cyan
Write-Host "    - Command: az ad group member add --group $GroupId --member-id <userId>" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NEXT: A Teams admin should create a custom Teams app permission policy" -ForegroundColor Cyan
Write-Host "        scoped to this group (requires MicrosoftTeams PowerShell module)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Green
