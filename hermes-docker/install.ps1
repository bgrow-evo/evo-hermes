#Requires -Version 5.1
<#
.SYNOPSIS
    Install and run the Nous Research Hermes Agent in a Docker container.

.DESCRIPTION
    Follows https://hermes-agent.nousresearch.com/docs/user-guide/docker

    Steps performed:
      1. Verifies Docker is installed and the daemon is running.
      2. Creates the persistent data directory (default: %USERPROFILE%\.hermes).
      3. Builds the custom hermes-evo image from the local Dockerfile (which extends
         nousresearch/hermes-agent:latest and pre-installs the Microsoft Teams SDK).
      4. (First run) Launches the interactive setup wizard to capture API keys.
      5. Starts the gateway + dashboard in the background via docker compose.

.PARAMETER DataDir
    Host directory mounted into the container at /opt/data.
    Defaults to "$env:USERPROFILE\.hermes".

.PARAMETER BaseImage
    Upstream base image to build FROM. Defaults to "nousresearch/hermes-agent:latest".
    Override to pin a specific release, e.g. "nousresearch/hermes-agent:v1.2.3".

.PARAMETER SkipSetup
    Skip the interactive setup wizard (use when ~/.hermes/.env already exists).

.PARAMETER NoStart
    Run setup only; do not start the gateway afterwards.

.PARAMETER DashboardUser
    Username for the dashboard web UI (chat) HTTP basic auth. Defaults to "admin".

.PARAMETER DashboardPassword
    Password for the dashboard basic auth as a SecureString. If omitted, you are
    prompted securely. Reused from the existing local .env on subsequent runs.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -DataDir "D:\hermes-data" -SkipSetup
#>
[CmdletBinding()]
param(
    [string]$DataDir = (Join-Path $env:USERPROFILE ".hermes"),
    [string]$BaseImage = "nousresearch/hermes-agent:latest",
    [switch]$SkipSetup,
    [switch]$NoStart,
    [string]$DashboardUser = "admin",
    [System.Security.SecureString]$DashboardPassword,
    [string]$PlaybookSource,
    [switch]$SkipStudio
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source of the distilled photo-workflow playbook bundled into the studio profile.
if (-not $PlaybookSource) {
    $PlaybookSource = Join-Path (Split-Path $ScriptDir -Parent) "photo-workflow-cowork-playbook-distilled"
}

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- Studio profile deployment ----------------------------------------------
# Deploys the 'studio' Hermes profile (separate HERMES_HOME, own s6-supervised
# gateway in the SAME container) that runs the evo photo workflow on a daily cron.
# Idempotent: safe to re-run on every install/rebuild. The profile lives in the
# bind-mounted volume (~/.hermes/profiles/studio), so it persists across rebuilds.
function Deploy-StudioProfile {
    param(
        [Parameter(Mandatory)] [string]$DataDirAbs,
        [Parameter(Mandatory)] [string]$ScriptDir,
        [Parameter(Mandatory)] [string]$PlaybookSource,
        [string]$Container = "hermes"
    )

    $profileSrc = Join-Path $ScriptDir "profiles\studio"
    if (-not (Test-Path $profileSrc)) {
        Write-Warn2 "No profiles\studio scaffold found at $profileSrc - skipping studio deploy."
        return
    }

    Write-Step "Deploying 'studio' profile"

    # Wait until the container can exec the hermes CLI (gateway boot can lag).
    $ready = $false
    foreach ($i in 1..30) {
        docker exec $Container hermes profile list *> $null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw "Container '$Container' not responding to 'hermes' CLI; cannot deploy studio profile." }

    # 1. Create the profile if absent (registers the gateway-studio s6 slot).
    $profiles = docker exec $Container hermes profile list 2>$null
    if ($profiles -match '(?m)^\s*\*?\s*studio\b' -or $profiles -match '\bstudio\b') {
        Write-Ok "Profile 'studio' already exists."
    } else {
        docker exec $Container hermes profile create studio `
            --description "evo photo studio: runs the daily photo workflow (report refresh, vendor sourcing, image processing) and packages PIM-ready ZIPs." | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "hermes profile create studio failed." }
        Write-Ok "Created profile 'studio'."
    }

    $profileDir = Join-Path $DataDirAbs "profiles\studio"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    # 2. Overlay the version-controlled scaffold (SOUL.md, .env, skills/) into the
    #    volume copy. profile create already laid down config.yaml + bundled skills;
    #    we add ours alongside.
    Copy-Item (Join-Path $profileSrc "SOUL.md") $profileDir -Force
    $skillsDst = Join-Path $profileDir "skills"
    New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
    Copy-Item (Join-Path $profileSrc "skills\*") $skillsDst -Recurse -Force

    # .env: seed the volume copy from the scaffold .env if absent; otherwise add any
    # scaffold keys the volume copy is missing WITHOUT overwriting values already set
    # there (profile create writes a minimal .env first, so this is how the vendor DAM
    # keys reach the running profile). Then inject OPENAI_API_KEY below.
    $envDst = Join-Path $profileDir ".env"
    $envSrc = Join-Path $profileSrc ".env"
    if (Test-Path $envSrc) {
        if (-not (Test-Path $envDst)) {
            Copy-Item $envSrc $envDst -Force
        } else {
            $haveKeys = @{}
            foreach ($l in Get-Content $envDst) {
                if ($l -match '^\s*([^#=\s]+)\s*=') { $haveKeys[$Matches[1]] = $true }
            }
            $toAdd = @()
            foreach ($l in Get-Content $envSrc) {
                if ($l -match '^\s*([^#=\s]+)\s*=' -and -not $haveKeys[$Matches[1]]) { $toAdd += $l }
            }
            if ($toAdd.Count) { Add-Content -Path $envDst -Value (@("") + $toAdd) }
        }
    }
    $mainEnv = Join-Path $DataDirAbs ".env"
    if ((Test-Path $mainEnv) -and -not (Select-String -Path $envDst -Pattern '^\s*OPENAI_API_KEY=' -Quiet)) {
        $openaiLine = Select-String -Path $mainEnv -Pattern '^\s*OPENAI_API_KEY=' | Select-Object -First 1
        if ($openaiLine) {
            Add-Content -Path $envDst -Value "`n# Injected by install.ps1 so the studio gateway can run its agent.`n$($openaiLine.Line)"
            Write-Ok "Injected OPENAI_API_KEY into studio .env."
        } else {
            Write-Warn2 "No OPENAI_API_KEY in $mainEnv - studio gateway may not be able to run its agent."
        }
    }

    # 3. Bundle the distilled playbook into the profile.
    if (Test-Path $PlaybookSource) {
        $playbookDst = Join-Path $profileDir "playbook"
        if (Test-Path $playbookDst) { Remove-Item $playbookDst -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $playbookDst | Out-Null
        Copy-Item (Join-Path $PlaybookSource "*") $playbookDst -Recurse -Force
        Write-Ok "Bundled playbook from $PlaybookSource"
    } else {
        Write-Warn2 "Playbook source not found at $PlaybookSource - studio will have no ./playbook/ to load."
    }

    # 4. Ensure work + outbox dirs exist.
    New-Item -ItemType Directory -Force -Path (Join-Path $profileDir "work") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDirAbs "outbox\studio") | Out-Null

    # 4b. Seed dry-run ON once (safe default while testing). The pipeline refuses to
    #     write back to external sources while DRY_RUN exists. Seeded only once: after
    #     you delete DRY_RUN to go live, redeploys won't resurrect it.
    $dryRun = Join-Path $profileDir "DRY_RUN"
    $seeded = Join-Path $profileDir ".dryrun_seeded"
    if (-not (Test-Path $seeded)) {
        Set-Content -Path $dryRun -Encoding ascii -Value @(
            "Dry-run flag for the studio daily pipeline."
            "While this file exists, the pipeline must not write back to any external"
            "source (Google Sheets, fileserver/SharePoint, vendor portals, Teams)."
            "Local artifacts (downloaded images, processed JPGs, outbox ZIP) still run."
            "Go live:  Remove-Item `"$dryRun`""
        )
        New-Item -ItemType File -Path $seeded -Force | Out-Null
        Write-Ok "Seeded DRY_RUN (pipeline starts in dry-run; delete the flag to go live)."
    }

    # 5. Apply config overrides (key/value lines), keeping generated config.yaml valid.
    $overrides = Join-Path $profileSrc "config.overrides"
    if (Test-Path $overrides) {
        foreach ($line in Get-Content $overrides) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith("#")) { continue }
            $parts = $t -split '\s+', 2
            if ($parts.Count -lt 2) { continue }
            docker exec $Container hermes -p studio config set $parts[0] $parts[1] | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warn2 "config set $($parts[0]) failed (continuing)." }
        }
        Write-Ok "Applied config overrides."
    }

    # 6. Ensure the daily cron job exists (06:00 daily).
    $cronList = docker exec $Container hermes -p studio cron list 2>$null
    if ($cronList -match 'studio-daily') {
        Write-Ok "Cron job 'studio-daily' already present."
    } else {
        docker exec $Container hermes -p studio cron create "0 6 * * *" `
            "Run the studio-daily-pipeline skill: execute the evo photo daily pipeline end to end (refresh, source, process, package PIM-ready ZIPs to /opt/data/outbox/studio), then stop. Do not upload to PIM. Report what is ready and every blocker." `
            --name studio-daily `
            --skill studio-daily-pipeline `
            --deliver local `
            --workdir /opt/data/profiles/studio/work | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "hermes cron create (studio) failed." }
        Write-Ok "Created daily cron job 'studio-daily' (06:00)."
    }

    # 7. Start the studio gateway (marks state running -> reconciler restores on rebuild).
    docker exec $Container hermes -p studio gateway start | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "studio gateway start returned non-zero (may already be running)." }
    else { Write-Ok "Studio gateway started (supervised by s6 in the hermes container)." }
}

# --- 1. Verify Docker --------------------------------------------------------
Write-Step "Checking Docker installation"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is not installed or not on PATH. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
}
try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Ok "Docker daemon is running."
} catch {
    throw "Docker is installed but the daemon is not responding. Start Docker Desktop and retry."
}

# Detect `docker compose` (v2) vs `docker-compose` (v1)
$composeCmd = $null
docker compose version *> $null
if ($LASTEXITCODE -eq 0) {
    $composeCmd = @("docker", "compose")
} elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    $composeCmd = @("docker-compose")
} else {
    Write-Warn2 "Docker Compose not found - the gateway will be started with 'docker run' instead."
}

# --- 2. Create data directory ------------------------------------------------
Write-Step "Preparing data directory"
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    Write-Ok "Created $DataDir"
} else {
    Write-Ok "Using existing $DataDir"
}

# Docker Desktop on Windows accepts native paths for bind mounts.
$DataDirAbs = (Resolve-Path $DataDir).Path

# --- 3. Build image ---------------------------------------------------------
Write-Step "Building hermes-evo image (base: $BaseImage)"
if ($composeCmd) {
    & $composeCmd[0] $composeCmd[1..($composeCmd.Count-1)] `
        -f (Join-Path $ScriptDir "docker-compose.yml") `
        build --pull `
        --build-arg "BASE_IMAGE=$BaseImage"
    if ($LASTEXITCODE -ne 0) { throw "docker compose build failed." }
} else {
    docker build --pull -t hermes-evo:latest `
        --build-arg "BASE_IMAGE=$BaseImage" `
        $ScriptDir
    if ($LASTEXITCODE -ne 0) { throw "docker build failed." }
}
Write-Ok "Image built successfully."

# --- 4. First-run setup wizard ----------------------------------------------
$envFile = Join-Path $DataDir ".env"
if ($SkipSetup -or (Test-Path $envFile)) {
    if (Test-Path $envFile) { Write-Step "Setup wizard skipped ($envFile already exists)" }
    else { Write-Step "Setup wizard skipped (-SkipSetup)" }
} else {
    Write-Step "Running interactive setup wizard"
    Write-Warn2 "You will be prompted for API keys; they are written to $envFile"
    docker run -it --rm -v "${DataDirAbs}:/opt/data" hermes-evo:latest setup
    if ($LASTEXITCODE -ne 0) { throw "Setup wizard exited with an error." }
    Write-Ok "Setup complete."
}

if ($NoStart) {
    Write-Step "Done (-NoStart specified, gateway not started)."
    return
}

# --- 5. Resolve dashboard web UI (chat) basic-auth credentials ---------------
Write-Step "Configuring dashboard web UI (chat) basic auth"
$composeEnv = Join-Path $ScriptDir ".env"

# Reuse existing values from a prior run unless new ones are supplied.
$existing = @{}
if (Test-Path $composeEnv) {
    foreach ($line in Get-Content $composeEnv) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $existing[$Matches[1]] = $Matches[2] }
    }
}

# Password: parameter > existing .env > secure prompt.
$plainPassword = $null
if ($DashboardPassword) {
    $plainPassword = [System.Net.NetworkCredential]::new('', $DashboardPassword).Password
} elseif ($existing.ContainsKey('HERMES_DASHBOARD_BASIC_AUTH_PASSWORD') -and $existing['HERMES_DASHBOARD_BASIC_AUTH_PASSWORD']) {
    $plainPassword = $existing['HERMES_DASHBOARD_BASIC_AUTH_PASSWORD']
    Write-Ok "Reusing existing dashboard password from $composeEnv"
} else {
    $sec = Read-Host -AsSecureString "Set a password for dashboard user '$DashboardUser'"
    $plainPassword = [System.Net.NetworkCredential]::new('', $sec).Password
    if (-not $plainPassword) { throw "A dashboard password is required for basic auth." }
}

# Username: parameter default 'admin' unless a value already exists.
if ($DashboardUser -eq 'admin' -and $existing.ContainsKey('HERMES_DASHBOARD_BASIC_AUTH_USERNAME') -and $existing['HERMES_DASHBOARD_BASIC_AUTH_USERNAME']) {
    $DashboardUser = $existing['HERMES_DASHBOARD_BASIC_AUTH_USERNAME']
}

# Stable session secret: reuse if present, else generate one.
$authSecret = $existing['HERMES_DASHBOARD_BASIC_AUTH_SECRET']
if (-not $authSecret) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $authSecret = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    Write-Ok "Generated a new dashboard session secret."
}

# --- 6. Start the gateway in the background ----------------------------------
Write-Step "Starting Hermes gateway"
if ($composeCmd) {
    # Provide the resolved data dir + dashboard auth to docker compose via .env.
    @(
        "HERMES_DATA=$DataDirAbs"
        "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$DashboardUser"
        "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$plainPassword"
        "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$authSecret"
    ) | Set-Content -Path $composeEnv -Encoding ascii
    Write-Ok "Wrote $composeEnv (data dir + dashboard credentials)"

    & $composeCmd[0] $composeCmd[1..($composeCmd.Count-1)] -f (Join-Path $ScriptDir "docker-compose.yml") up -d
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed." }

    Write-Ok "Gateway started."
    Write-Host "`nView logs:    " -NoNewline; Write-Host "$($composeCmd -join ' ') -f `"$(Join-Path $ScriptDir 'docker-compose.yml')`" logs -f" -ForegroundColor White
    Write-Host "Stop:         " -NoNewline; Write-Host "$($composeCmd -join ' ') -f `"$(Join-Path $ScriptDir 'docker-compose.yml')`" down" -ForegroundColor White
} else {
    # Fallback: plain docker run
    docker rm -f hermes *> $null
    docker run -d --name hermes --restart unless-stopped `
        -v "${DataDirAbs}:/opt/data" `
        -p 8642:8642 -p 9119:9119 -p 3978:3978 `
        -e HERMES_DASHBOARD=1 `
        -e "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=$DashboardUser" `
        -e "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=$plainPassword" `
        -e "HERMES_DASHBOARD_BASIC_AUTH_SECRET=$authSecret" `
        hermes-evo:latest gateway run
    if ($LASTEXITCODE -ne 0) { throw "docker run failed." }
    Write-Ok "Gateway started."
    Write-Host "`nView logs:    docker logs -f hermes" -ForegroundColor White
    Write-Host "Stop:         docker stop hermes" -ForegroundColor White
}

# --- 7. Deploy the studio profile (photo workflow + daily cron) --------------
if ($SkipStudio) {
    Write-Step "Studio profile deploy skipped (-SkipStudio)."
} else {
    Deploy-StudioProfile -DataDirAbs $DataDirAbs -ScriptDir $ScriptDir -PlaybookSource $PlaybookSource
}

Write-Host "`nGateway API:   http://localhost:8642" -ForegroundColor White
Write-Host "Dashboard:     http://localhost:9119  (login as '$DashboardUser')" -ForegroundColor White
Write-Host "Teams webhook: http://localhost:3978/health" -ForegroundColor White
if (-not $SkipStudio) {
    Write-Host "Studio profile: docker exec hermes hermes gateway list   (cron: ...hermes -p studio cron list)" -ForegroundColor White
    Write-Host "Studio outbox:  $env:USERPROFILE\.hermes\outbox\studio" -ForegroundColor White
}
Write-Host "`nDone." -ForegroundColor Green
