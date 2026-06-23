#Requires -Version 5.1
<#
.SYNOPSIS
    Setup for a SECOND Microsoft Teams bot dedicated to the Hermes `studio`
    profile, plus its own ngrok tunnel, and wiring the studio gateway to it.

.DESCRIPTION
    A near-copy of teams-bot-setup.ps1, defaulted for the studio profile:
      - BotName  "Hermes Studio"
      - Port     3979  (the default profile's bot owns 3978)

    Idempotent. On first run it creates a NEW Azure bot (printing CLIENT_ID /
    CLIENT_SECRET / TENANT_ID); later runs update that bot's messaging endpoint to
    the current tunnel URL.

    "Connecting the profile" is a separate step: pass -WireStudio with the three
    credentials (or run that block manually). It writes the creds into the studio
    profile and enables Teams on the studio gateway, on port 3979.

    IMPORTANT -- two bots means two tunnels:
      The default bot already uses ngrok on 3978. ngrok's FREE tier allows only one
      online agent, so you cannot run a second `ngrok http 3979` at the same time.
      Use ONE ngrok agent with a multi-tunnel config (see -PrintNgrokConfig), or a
      paid plan. This script reuses an existing tunnel that already forwards to
      $Port; it only starts a fresh agent if none is found.

.PARAMETER BotName
    Display name for the studio Teams app/bot. Default "Hermes Studio".

.PARAMETER Port
    Local port the studio Teams listener uses. Default 3979.

.PARAMETER AppId
    Teams app id to update. If omitted, found by -BotName.

.PARAMETER NgrokAuthToken
    ngrok authtoken. Only needed once.

.PARAMETER SkipLogin
    Skip the `teams login` check.

.PARAMETER ForceCreate
    Always create a new Teams app even if one named -BotName exists.

.PARAMETER WireStudio
    After (or instead of) creating the bot, connect the studio profile: write the
    Teams creds into ~/.hermes/profiles/studio/.env and enable Teams on the studio
    gateway (port 3979), then restart it. Requires -TeamsClientId / -TeamsClientSecret
    / -TeamsTenantId.

.PARAMETER TeamsClientId
.PARAMETER TeamsClientSecret
.PARAMETER TeamsTenantId
    The new bot's credentials (printed by `teams app create`). Used by -WireStudio.

.PARAMETER Container
    Name of the running Hermes container. Default "hermes".

.PARAMETER DataDir
    Host Hermes data dir (bind-mounted to /opt/data). Default %USERPROFILE%\.hermes.

.PARAMETER PrintNgrokConfig
    Print a ready-to-use ngrok config (one agent, two tunnels: 3978 + 3979) and exit.

.EXAMPLE
    # 1) create the bot (prints CLIENT_ID/SECRET/TENANT_ID)
    .\teams-bot-setup-studio.ps1

.EXAMPLE
    # 2) connect the studio profile to it
    .\teams-bot-setup-studio.ps1 -WireStudio `
        -TeamsClientId <id> -TeamsClientSecret <secret> -TeamsTenantId <tenant>
#>
[CmdletBinding()]
param(
    [string]$BotName = "Hermes Studio",
    [int]$Port = 3979,
    [string]$AppId,
    [string]$NgrokAuthToken,
    [switch]$SkipLogin,
    [switch]$ForceCreate,
    [switch]$WireStudio,
    [string]$TeamsClientId,
    [string]$TeamsClientSecret,
    [string]$TeamsTenantId,
    [string]$Container = "hermes",
    [string]$DataDir = (Join-Path $env:USERPROFILE ".hermes"),
    [switch]$PrintNgrokConfig
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "    $msg" -ForegroundColor Yellow }

# --- ngrok multi-tunnel config helper ---------------------------------------
if ($PrintNgrokConfig) {
    Write-Host @"
# One ngrok agent, two tunnels (default bot 3978 + studio bot 3979).
# Save as ngrok.yml, then run:  ngrok start --all --config ngrok.yml
version: "3"
agent:
  authtoken: <YOUR_NGROK_AUTHTOKEN>
tunnels:
  hermes-default:
    proto: http
    addr: 3978
  hermes-studio:
    proto: http
    addr: 3979
"@
    return
}

# --- studio wiring (connect the profile to the bot) --------------------------
function Connect-StudioProfile {
    param([string]$ClientId, [string]$ClientSecret, [string]$TenantId, [int]$Port, [string]$Container, [string]$DataDir)

    if (-not ($ClientId -and $ClientSecret -and $TenantId)) {
        throw "-WireStudio requires -TeamsClientId, -TeamsClientSecret, and -TeamsTenantId."
    }

    Write-Step "Wiring studio profile -> Teams bot (port $Port)"

    # 1. Persist creds in the studio profile .env (volume copy; not the repo scaffold).
    $studioEnv = Join-Path $DataDir "profiles\studio\.env"
    if (-not (Test-Path $studioEnv)) { New-Item -ItemType File -Path $studioEnv -Force | Out-Null }
    $lines = @(Get-Content $studioEnv -ErrorAction SilentlyContinue)
    $set = @{
        "TEAMS_CLIENT_ID"     = $ClientId
        "TEAMS_CLIENT_SECRET" = $ClientSecret
        "TEAMS_TENANT_ID"     = $TenantId
    }
    foreach ($k in $set.Keys) {
        $lines = $lines | Where-Object { $_ -notmatch "^\s*$k=" }
    }
    $lines += "`n# Studio Teams bot (added by teams-bot-setup-studio.ps1)"
    foreach ($k in $set.Keys) { $lines += "$k=$($set[$k])" }
    Set-Content -Path $studioEnv -Value $lines -Encoding ascii
    Write-Ok "Wrote Teams creds to $studioEnv"

    # 2. Enable Teams on the studio gateway (writes to the volume config.yaml).
    $cfg = @(
        @("platforms.teams.enabled", "true"),
        @("platforms.teams.extra.port", "$Port"),
        @("platforms.teams.extra.client_id", $ClientId),
        @("platforms.teams.extra.client_secret", $ClientSecret),
        @("platforms.teams.extra.tenant_id", $TenantId)
    )
    foreach ($kv in $cfg) {
        docker exec $Container hermes -p studio config set $kv[0] $kv[1] | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn2 "config set $($kv[0]) failed (continuing)." }
    }
    Write-Ok "Enabled platforms.teams on the studio profile (port $Port)."

    # 3. Restart the studio gateway to pick up the platform.
    docker exec $Container hermes -p studio gateway restart | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "studio gateway restart returned non-zero." }
    else { Write-Ok "Studio gateway restarted." }

    Write-Warn2 "Studio bot listens on container:$Port. Ensure docker-compose publishes $Port and a tunnel forwards to host:$Port."
}

# If the caller only wants to wire an already-created bot, do it and exit.
if ($WireStudio -and -not $ForceCreate -and $TeamsClientId) {
    Connect-StudioProfile -ClientId $TeamsClientId -ClientSecret $TeamsClientSecret -TenantId $TeamsTenantId -Port $Port -Container $Container -DataDir $DataDir
    return
}

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

# Find a tunnel already forwarding to THIS port (so we don't clash with the
# default bot's 3978 tunnel running in the same agent).
function Get-NgrokHttpsUrlForPort {
    param([int]$Port)
    try {
        $resp = Invoke-RestMethod -Uri $ngrokApi -TimeoutSec 3 -ErrorAction Stop
        $t = $resp.tunnels | Where-Object {
            $_.public_url -like "https://*" -and $_.config.addr -match "(:|/)$Port$"
        } | Select-Object -First 1
        if ($t) { return $t.public_url }
    } catch { }
    return $null
}

$publicUrl = Get-NgrokHttpsUrlForPort -Port $Port
if ($publicUrl) {
    Write-Ok "Found an existing ngrok tunnel for port $Port : $publicUrl"
} else {
    # Check if an ngrok agent is already running (default bot likely started it).
    $agentRunning = $false
    try { Invoke-RestMethod -Uri $ngrokApi -TimeoutSec 3 -ErrorAction Stop | Out-Null; $agentRunning = $true } catch { }

    if ($agentRunning) {
        # Agent is up — inject a new tunnel via the ngrok agent REST API.
        # This works on free tier (one agent session, multiple tunnels within it).
        Write-Warn2 "ngrok agent is running; adding a tunnel to port $Port via agent API..."
        try {
            $body = @{ proto = "http"; addr = "localhost:$Port"; name = "hermes-studio-$Port" } | ConvertTo-Json -Compress
            $t = Invoke-RestMethod -Uri $ngrokApi -Method Post `
                -ContentType "application/json" -Body $body -TimeoutSec 10 -ErrorAction Stop
            $publicUrl = $t.public_url
        } catch { }

        if (-not $publicUrl) {
            Write-Warn2 "Agent API tunnel add failed. Trying -PrintNgrokConfig workaround..."
            Write-Warn2 "Run:  .\teams-bot-setup-studio.ps1 -PrintNgrokConfig"
            Write-Warn2 "      Then restart ngrok with both tunnels in one config file."
            throw "Could not add tunnel for port $Port to the running ngrok agent."
        }
        Write-Ok "Tunnel injected into existing agent: $publicUrl"
    } else {
        # No agent running — start ngrok normally targeting our port.
        Write-Warn2 "Starting ngrok on port $Port (minimized window)..."
        Start-Process $ngrok -ArgumentList "http", "$Port" -WindowStyle Minimized | Out-Null
        for ($i = 0; $i -lt 20 -and -not $publicUrl; $i++) {
            Start-Sleep -Seconds 1
            $publicUrl = Get-NgrokHttpsUrlForPort -Port $Port
        }
        if (-not $publicUrl) {
            throw "Could not read an ngrok public URL forwarding to $Port from $ngrokApi after 20s. Check the ngrok window."
        }
        Write-Ok "ngrok tunnel is up: $publicUrl"
    }
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
    Write-Host ' New STUDIO bot created. Copy the CLIENT_ID / CLIENT_SECRET / TENANT_ID' -ForegroundColor Green
    Write-Host ' printed above, then connect the studio profile:' -ForegroundColor Green
    Write-Host '   .\teams-bot-setup-studio.ps1 -WireStudio -TeamsClientId <id> -TeamsClientSecret <secret> -TeamsTenantId <tenant>' -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor White
}

# --- 5. Optionally wire the studio profile now -------------------------------
if ($WireStudio) {
    Connect-StudioProfile -ClientId $TeamsClientId -ClientSecret $TeamsClientSecret -TenantId $TeamsTenantId -Port $Port -Container $Container -DataDir $DataDir
}

# --- 6. Verify the tunnel reaches the local bot -----------------------------
Write-Step "Verifying tunnel -> bot health"
try {
    $h = Invoke-RestMethod -Uri "$publicUrl/health" -Headers @{ "ngrok-skip-browser-warning" = "1" } -TimeoutSec 10
    if ("$h".Trim() -eq "ok") { Write-Ok "Health check via public URL: ok" }
    else { Write-Warn2 "Unexpected health response: $h" }
} catch {
    Write-Warn2 "Health check failed ($_). Is the studio gateway running on port $Port (and is $Port published by docker-compose)?"
}

# --- 7. Done -----------------------------------------------------------------
Write-Host "`n----------------------------------------------------------------" -ForegroundColor White
Write-Host " Studio messaging endpoint: $endpoint" -ForegroundColor Green
Write-Host " Inspect traffic:           http://127.0.0.1:4040" -ForegroundColor Green
Write-Host "----------------------------------------------------------------" -ForegroundColor White
Write-Warn2 "Keep ngrok running. Re-run this script whenever the tunnel URL changes."
