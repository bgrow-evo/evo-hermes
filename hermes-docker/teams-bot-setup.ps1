#Requires -Version 5.1
<#
.SYNOPSIS
    Standalone helper to register a Microsoft Teams bot for Hermes and print the
    CLIENT_ID / CLIENT_SECRET / TENANT_ID to paste into the running install wizard.

.DESCRIPTION
    Run this in a SEPARATE terminal while install.ps1 is paused at the Teams prompt.
    It is intentionally NOT wired into install.ps1.

    Steps performed:
      1. Verifies npm is available; installs @microsoft/teams.cli@preview if missing.
      2. Runs `teams login` (unless -SkipLogin) so the CLI can register the app.
      3. Starts an ngrok tunnel to the bot port (default 3978) in a new window.
      4. Reads the public HTTPS URL from ngrok's local API (127.0.0.1:4040).
      5. Runs `teams app create` against <tunnel>/api/messages.
      6. Prints the CLI output containing the credentials.

    Leave the ngrok window running for as long as the bot needs to receive
    messages. If ngrok restarts with a new URL, re-run this script (or update the
    bot's messaging endpoint) so the registered endpoint matches.

.PARAMETER BotName
    Display name for the Teams app/bot. Default "Hermes".

.PARAMETER Port
    Local port the Hermes Teams listener uses. Default 3978.

.PARAMETER NgrokAuthToken
    ngrok authtoken. Only needed once; if you've already run
    `ngrok config add-authtoken ...` you can omit this.

.PARAMETER SkipLogin
    Skip `teams login` (use if you're already authenticated).

.EXAMPLE
    .\teams-bot-setup.ps1 -NgrokAuthToken 2abcXYZ...
#>
[CmdletBinding()]
param(
    [string]$BotName = "Hermes",
    [int]$Port = 3978,
    [string]$NgrokAuthToken,
    [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    $msg" -ForegroundColor Yellow }

# --- 1. Teams CLI ------------------------------------------------------------
Write-Step "Checking Teams CLI"
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm is not on PATH. Activate a Node version (you use NVM) and retry: e.g. 'nvm use <version>'."
}
if (-not (Get-Command teams -ErrorAction SilentlyContinue)) {
    Write-Warn2 "Teams CLI not found - installing @microsoft/teams.cli@preview ..."
    npm install -g "@microsoft/teams.cli@preview"
    if ($LASTEXITCODE -ne 0) { throw "Failed to install the Teams CLI." }
}
Write-Ok "Teams CLI is available."

if (-not $SkipLogin) {
    Write-Step "Signing in to Microsoft 365 (a browser window will open)"
    Write-Warn2 "Use an account that can register apps in your Entra/M365 tenant."
    teams login
    if ($LASTEXITCODE -ne 0) { throw "teams login failed. Re-run with a valid M365 account, or use -SkipLogin if already authenticated." }
} else {
    Write-Step "Skipping teams login (-SkipLogin)"
}

# --- 2. ngrok ----------------------------------------------------------------
Write-Step "Preparing ngrok tunnel on port $Port"
if (-not (Get-Command ngrok -ErrorAction SilentlyContinue)) {
    throw "ngrok is not installed. Install it (e.g. 'winget install ngrok.ngrok'), then retry."
}
if ($NgrokAuthToken) {
    ngrok config add-authtoken $NgrokAuthToken | Out-Null
    Write-Ok "Configured ngrok authtoken."
}

$ngrokApi = "http://127.0.0.1:4040/api/tunnels"

function Get-NgrokHttpsUrl {
    try {
        $resp = Invoke-RestMethod -Uri $ngrokApi -TimeoutSec 3 -ErrorAction Stop
        $t = $resp.tunnels | Where-Object { $_.public_url -like "https://*" } | Select-Object -First 1
        if ($t) { return $t.public_url }
    } catch { }
    return $null
}

# Reuse an already-running ngrok if it's forwarding; otherwise start one.
$publicUrl = Get-NgrokHttpsUrl
if ($publicUrl) {
    Write-Ok "Found an existing ngrok tunnel: $publicUrl"
} else {
    Write-Warn2 "Starting ngrok in a new window (keep it open)..."
    Start-Process ngrok -ArgumentList "http", "$Port" -WindowStyle Normal | Out-Null
    for ($i = 0; $i -lt 20 -and -not $publicUrl; $i++) {
        Start-Sleep -Seconds 1
        $publicUrl = Get-NgrokHttpsUrl
    }
    if (-not $publicUrl) {
        throw "Could not read the ngrok public URL from $ngrokApi. Check the ngrok window for errors (e.g. missing authtoken)."
    }
    Write-Ok "ngrok tunnel is up: $publicUrl"
}

$endpoint = "$publicUrl/api/messages"

# --- 3. Create the bot -------------------------------------------------------
Write-Step "Creating Teams app/bot '$BotName'"
Write-Ok  "Endpoint: $endpoint"
teams app create --name "$BotName" --endpoint "$endpoint"
if ($LASTEXITCODE -ne 0) { throw "teams app create failed. See output above." }

# --- 4. Done -----------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " Copy the CLIENT_ID, CLIENT_SECRET, and TENANT_ID printed above" -ForegroundColor Green
Write-Host " and paste them into the Hermes install wizard prompt." -ForegroundColor Green
Write-Host "----------------------------------------------------------------" -ForegroundColor White
Write-Warn2 "Keep the ngrok window running. If its URL changes, re-run this script"
Write-Warn2 "so the bot's messaging endpoint matches the new tunnel."
Write-Warn2 "Port $Port is published in docker-compose.yml, so the gateway will"
Write-Warn2 "receive Teams messages once you run the install and it starts."
