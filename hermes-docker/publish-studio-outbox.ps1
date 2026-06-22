#Requires -Version 5.1
<#
.SYNOPSIS
    Publish studio outbox artifacts into a OneDrive-synced folder so a Power
    Automate "When a file is created" (OneDrive) trigger can pick them up and
    post them to Teams. See docs/power-automate-studio-outbox.md (Option A).

.DESCRIPTION
    Mirrors ~/.hermes/outbox/studio -> <OneDrive>/HermesStudioOutbox using robocopy
    /XO (copies only newer/complete files, so Power Automate never sees a partial
    upload). Run on a schedule (Task Scheduler, every ~5 min) or ad hoc.

.PARAMETER Source
    Studio outbox dir. Default %USERPROFILE%\.hermes\outbox\studio.

.PARAMETER Dest
    OneDrive-synced destination. Default %OneDrive%\HermesStudioOutbox.

.EXAMPLE
    .\publish-studio-outbox.ps1
.EXAMPLE
    # register a 5-minute scheduled task
    schtasks /Create /SC MINUTE /MO 5 /TN "PublishStudioOutbox" `
      /TR "powershell -NoProfile -File `"$PWD\publish-studio-outbox.ps1`""
#>
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $env:USERPROFILE ".hermes\outbox\studio"),
    [string]$Dest   = (Join-Path $env:OneDrive "HermesStudioOutbox")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) { Write-Host "Source not found: $Source (nothing to publish)"; return }
if (-not $env:OneDrive)       { throw "OneDrive is not configured on this account (`$env:OneDrive is empty)." }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

# /E recurse incl. empty, /XO skip older (only push complete/newer files),
# /R:2 /W:5 modest retries, quiet listing.
robocopy $Source $Dest /E /XO /R:2 /W:5 /NJH /NJS /NDL /NP | Out-Null

# robocopy exit codes 0-7 are success (8+ = error).
if ($LASTEXITCODE -ge 8) { throw "robocopy failed (exit $LASTEXITCODE)." }
Write-Host "Published $Source -> $Dest (robocopy exit $LASTEXITCODE)."
