#Requires -Version 5.1
<#
.SYNOPSIS
    One-command setup for the Hermes Microsoft Teams bot + ngrok tunnel.

.DESCRIPTION
    Idempotent: run it any time. It brings the tunnel up and points the Teams
    bot's messaging endpoint at the current ngrok URL. The first run creates the
    bot (printing CLIENT_ID / CLIENT_SECRET / TENANT_ID); every later run just
    updates the existing bot's endpoint to the new tunnel URL.

    Steps performed:
      1. Verifies npm + Teams CLI (installs @microsoft/teams.cli@preview if missing).
      2. Runs `teams login` if not already authenticated (unless -SkipLogin).
      3. Resolves ngrok (PATH or winget install dir) and reuses/starts a tunnel.
      4. Reads the public HTTPS URL from ngrok's local API (127.0.0.1:4040).
      5. Looks up the existing Teams app by name:
           - found    -> `teams app update <appId> --endpoint <tunnel>/api/messages`
           - not found -> `teams app create --name <name> --endpoint <tunnel>/api/messages`
      6. Verifies the tunnel reaches the local bot health endpoint.

    Keep the ngrok window open while you use the bot. Re-run this script whenever
    ngrok restarts with a new URL.

.PARAMETER BotName
    Display name for the Teams app/bot. Default "Hermes".

.PARAMETER Port
    Local port the Hermes Teams listener uses. Default 3978.

.PARAMETER AppId
    Teams app id to update. If omitted, the script finds it by -BotName.

.PARAMETER NgrokAuthToken
    ngrok authtoken. Only needed once; if you've already run
    `ngrok config add-authtoken ...` you can omit this.

.PARAMETER SkipLogin
    Skip the `teams login` check (use if you're already authenticated).

.PARAMETER ForceCreate
    Always create a new Teams app even if one with -BotName already exists.

.EXAMPLE
    .\teams-bot-setup.ps1

.EXAMPLE
    .\teams-bot-setup.ps1 -NgrokAuthToken 2abcXYZ...
#>
[CmdletBinding()]
param(
    [string]$BotName = "Hermes",
    [int]$Port = 3978,
    [string]$AppId,
    [string]$NgrokAuthToken,
    [switch]$SkipLogin,
    [switch]$ForceCreate
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    $msg" -ForegroundColor Yellow }

# Resolve ngrok from PATH, or the winget install dir (it isn't added to PATH).
function Resolve-Ngrok {
    $cmd = Get-Command ngrok -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ngrok.Ngrok_*\ngrok.exe"
        "$env:LOCALAPPDATA\ngrok\ngrok.exe"
        "$env:USERPROFILE\scoop\shims\ngrok.exe"
    )
    foreach ($pattern in $candidates) {
        $hit = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# Extract the JSON payload from a teams CLI response (it prepends banners).
function ConvertFrom-TeamsJson($raw) {
    $text = ($raw | Out-String) -replace '\x1b\[[0-9;]*[mKJH]', ''
    $start = $text.IndexOf('[')
    $end   = $text.LastIndexOf(']')
    if ($start -lt 0 -or $end -lt $start) { return @() }
    return $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
}

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
    Write-Step "Checking Microsoft 365 sign-in"
    $loggedIn = $false
    try {
        teams whoami *> $null
        if ($LASTEXITCODE -eq 0) { $loggedIn = $true }
    } catch { }
    if ($loggedIn) {
        Write-Ok "Already signed in."
    } else {
        Write-Warn2 "Not signed in - launching `teams login` (a browser window will open)."
        Write-Warn2 "Use an account that can register apps in your Entra/M365 tenant."
        teams login
        if ($LASTEXITCODE -ne 0) { throw "teams login failed. Re-run with a valid M365 account, or use -SkipLogin if already authenticated." }
    }
} else {
    Write-Step "Skipping teams login (-SkipLogin)"
}

# --- 2. ngrok ----------------------------------------------------------------
Write-Step "Preparing ngrok tunnel on port $Port"
$ngrok = Resolve-Ngrok
if (-not $ngrok) {
    throw "ngrok is not installed. Install it ('winget install --id Ngrok.Ngrok -e'), then retry."
}
Write-Ok "Using ngrok: $ngrok"
if ($NgrokAuthToken) {
    & $ngrok config add-authtoken $NgrokAuthToken | Out-Null
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
    Start-Process $ngrok -ArgumentList "http", "$Port" -WindowStyle Minimized | Out-Null
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

# --- 3. Find the existing app (unless forcing a create) ----------------------
if (-not $AppId -and -not $ForceCreate) {
    Write-Step "Looking up existing Teams app '$BotName'"
    try {
        $apps = ConvertFrom-TeamsJson (teams app list --json 2>&1)
        $match = $apps | Where-Object { $_.appName -eq $BotName -or $_.shortName -eq $BotName } | Select-Object -First 1
        if ($match) {
            $AppId = $match.appId
            Write-Ok "Found app '$BotName' (appId: $AppId)"
        } else {
            Write-Warn2 "No existing app named '$BotName' - will create a new one."
        }
    } catch {
        Write-Warn2 "Could not list apps ($_). Will attempt to create a new one."
    }
}

# --- 4. Update existing endpoint, or create a new bot ------------------------
if ($AppId) {
    Write-Step "Updating endpoint for app $AppId"
    Write-Ok  "Endpoint: $endpoint"
    teams app update $AppId --endpoint "$endpoint"
    if ($LASTEXITCODE -ne 0) { throw "teams app update failed. See output above." }
    Write-Ok "Endpoint updated."
} else {
    Write-Step "Creating Teams app/bot '$BotName'"
    Write-Ok  "Endpoint: $endpoint"
    teams app create --name "$BotName" --endpoint "$endpoint"
    if ($LASTEXITCODE -ne 0) { throw "teams app create failed. See output above." }
    Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
    Write-Host " Copy the CLIENT_ID, CLIENT_SECRET, and TENANT_ID printed above" -ForegroundColor Green
    Write-Host " into ~/.hermes/.env (TEAMS_CLIENT_ID / _SECRET / _TENANT_ID)." -ForegroundColor Green
    Write-Host "----------------------------------------------------------------" -ForegroundColor White
}

# --- 5. Verify the tunnel reaches the local bot -----------------------------
Write-Step "Verifying tunnel -> bot health"
try {
    $h = Invoke-RestMethod -Uri "$publicUrl/health" -Headers @{ "ngrok-skip-browser-warning" = "1" } -TimeoutSec 10
    if ("$h".Trim() -eq "ok") { Write-Ok "Health check via public URL: ok" }
    else { Write-Warn2 "Unexpected health response: $h" }
} catch {
    Write-Warn2 "Health check failed ($_). Is the Hermes gateway running on port $Port?"
}

# --- 6. Done -----------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " Messaging endpoint: $endpoint" -ForegroundColor Green
Write-Host " Inspect traffic:    http://127.0.0.1:4040" -ForegroundColor Green
Write-Host "----------------------------------------------------------------" -ForegroundColor White
Write-Warn2 "Keep ngrok running. Re-run this script whenever the tunnel URL changes;"
Write-Warn2 "it will update the existing bot's endpoint automatically."
