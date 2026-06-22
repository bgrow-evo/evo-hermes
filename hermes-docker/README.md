# Hermes Agent — Docker install (evo)

Custom Docker setup for the [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/docker) with Microsoft Teams integration, preconfigured for evo's workflow.

## Architecture

```
Teams client
    │  HTTPS
    ▼
ngrok tunnel ──► localhost:3978/api/messages
                        │
                 Docker container (hermes-evo)
                 ┌────────────────────────────────────────┐
                 │  s6-overlay (PID 1)                    │
                 │  ├─ gateway: default (port 8642)       │
                 │  │   └─ Teams adapter (port 3978)      │
                 │  ├─ gateway: studio  (profile)         │
                 │  │   └─ daily photo-workflow cron      │
                 │  └─ dashboard (port 9119)              │
                 └────────────────────────────────────────┘
                        │  /opt/data (bind mount)
                 ~/.hermes on host
                 (config.yaml, .env, memories, logs,
                  profiles/studio/, outbox/studio/)
```

The custom `Dockerfile` extends `nousresearch/hermes-agent:latest` and pre-installs the Microsoft Teams SDK (`microsoft-teams-apps`, `aiohttp`) plus image-manipulation tools for the studio profile (`imagemagick`, `libvips-tools`, `webp`, `zip`) so nothing lazy-installs at runtime. This survives image rebuilds.

The **default** gateway handles interactive Teams/dashboard chat. The **studio** gateway is a separate profile (its own `HERMES_HOME` under `~/.hermes/profiles/studio`) supervised by the same s6 instance — it runs the daily photo workflow on a cron. See [Profiles](#profiles).

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and **running**
- PowerShell 5.1+ (ships with Windows)
- [ngrok](https://ngrok.com/) installed and authenticated (for Teams webhook)
- A Microsoft 365 account with permission to register bot apps in your tenant

## Quick start (first install)

```powershell
# from this folder
.\install.ps1
```

What it does:

1. Verifies Docker and detects `docker compose`.
2. Creates `%USERPROFILE%\.hermes` (all Hermes state — `.env`, `config.yaml`, sessions, memories, skills, logs).
3. **Builds** the custom `hermes-evo:latest` image from the local `Dockerfile`.
4. Runs the **interactive setup wizard** on first install (prompts for LLM API keys).
5. Prompts for a dashboard password and starts the gateway in the background.

After install:

| Endpoint | URL |
|---|---|
| Gateway API | http://localhost:8642 |
| Dashboard / chat UI | http://localhost:9119 |
| Teams webhook | http://localhost:3978/health |

### Dashboard web UI

The dashboard (`HERMES_DASHBOARD=1`) uses HTTP **basic auth** — Hermes refuses to start it without an auth provider.

- `install.ps1` prompts for a password on first run (username defaults to `admin`).
- Credentials are written to the local `.env` here and forwarded into the container.
- Subsequent installs reuse the stored password automatically.

Set credentials non-interactively:

```powershell
.\install.ps1 -DashboardUser hunter -DashboardPassword (Read-Host -AsSecureString "pw")
```

## Microsoft Teams bot setup

### 1. Register the bot (one time per tenant)

Run `teams-bot-setup.ps1` in a separate terminal. It registers an Azure Bot, starts ngrok, and prints the credentials:

```powershell
.\teams-bot-setup.ps1 -NgrokAuthToken <your-ngrok-token>
```

Copy the `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID` it prints into `~/.hermes/.env`:

```dotenv
TEAMS_CLIENT_ID=<client id from teams app create>
TEAMS_CLIENT_SECRET=<client secret>
TEAMS_TENANT_ID=<tenant id>
TEAMS_ALLOW_ALL_USERS=false
TEAMS_ALLOWED_USERS=<comma-separated AAD object IDs of allowed users>
```

And enable Teams in `~/.hermes/config.yaml`:

```yaml
platforms:
  teams:
    enabled: true
    extra:
      client_id: <same as TEAMS_CLIENT_ID>
      client_secret: <same as TEAMS_CLIENT_SECRET>
      port: 3978
      tenant_id: <same as TEAMS_TENANT_ID>
```

### 2. Start the tunnel + sync the endpoint (every session)

Just re-run the same script. It is **idempotent**: it resolves ngrok (even if
it's only installed via winget and not on PATH), reuses or starts the tunnel,
finds the existing `Hermes` app, and updates its messaging endpoint to the
current ngrok URL automatically.

```powershell
.\teams-bot-setup.ps1
```

No need to manually run `ngrok http 3978` or edit the endpoint in the portal —
the script does both and verifies the tunnel reaches the bot's `/health`.

> ngrok must stay running while you use the bot. Because the free tier issues a
> new URL each launch, just re-run `teams-bot-setup.ps1` after any ngrok restart.

### 3. Install the bot in Teams

```powershell
# Find the teamsAppId from the original teams app create output, then:
teams app get <teamsAppId> --install-link
```

Open the printed link in your browser to install the bot in your Teams client. You can then DM "Hermes" in Teams.

### Current credentials (evo tenant)

Stored in `~/.hermes/.env` on the host (`/opt/data/.env` inside the container):

| Variable | Value |
|---|---|
| `TEAMS_CLIENT_ID` | `3146b701-6559-4671-b9d9-91e7508884b1` |
| `TEAMS_TENANT_ID` | `1c2caf71-5666-4b98-bffc-ae0da8c4a4db` |
| `TEAMS_ALLOWED_USERS` | `82bd9911-5920-4d97-965a-96b8d624143f` |
| `TEAMS_CLIENT_SECRET` | stored in `~/.hermes/.env` |
| `NGROK_AUTHTOKEN` | stored in project `.env` |

## LLM provider — OpenAI Codex via OAuth

Hermes runs on the `openai-codex` provider (`gpt-5.5`), authenticated against the
evo ChatGPT **Team** workspace (account `309dd741-6002-4291-b973-8294070a61b9`).

### Why the normal flow doesn't work

`hermes auth add openai-codex` only supports the OAuth **device-code** flow, which
evo's tenant blocks two ways:

- **Azure AD** `AADSTS50105` — the ChatGPT enterprise app requires explicit user
  assignment for `hermes-ai@evo.com`.
- **ChatGPT workspace** — the admin has disabled device-code authentication.

The fix is to run the standard **authorization-code + PKCE** flow manually (the same
one the Codex CLI uses, redirect `http://localhost:1455/auth/callback`). Helper
scripts live in `.codex-oauth/`.

### Re-authenticating (token refresh fails, or new host)

Hermes auto-refreshes the access token using the stored refresh token, so this is
only needed if refresh fails or you're provisioning a fresh data dir.

```powershell
# 1. Generate the login URL (writes PKCE state into the data volume)
docker cp .\.codex-oauth\step1_authorize.py hermes:/tmp/step1_authorize.py
docker compose exec --user hermes hermes /opt/hermes/.venv/bin/python3 /tmp/step1_authorize.py

# 2. Open the printed URL, sign in with the tenant account.
#    The browser redirects to http://localhost:1455/auth/callback?code=...&state=...
#    which fails to load — that's expected. Copy the FULL URL from the address bar.

# 3. Write that callback URL into the data volume (NOT into the repo):
Set-Content "$env:USERPROFILE\.hermes\.codex_callback.txt" '<paste callback URL>'

# 4. Exchange the code for tokens and save them into Hermes's auth store:
docker cp .\.codex-oauth\step2_exchange.py hermes:/tmp/step2_exchange.py
docker compose exec --user hermes hermes bash -c "cd /opt/hermes && HERMES_HOME=/opt/data /opt/hermes/.venv/bin/python3 /tmp/step2_exchange.py"

# 5. Restart and (optionally) smoke-test:
docker compose restart hermes
docker cp .\.codex-oauth\smoke_test.py hermes:/tmp/smoke_test.py
docker compose exec --user hermes hermes bash -c "cd /opt/hermes && HERMES_HOME=/opt/data /opt/hermes/.venv/bin/python3 /tmp/smoke_test.py"
```

A working smoke test prints `HTTP 200` and an SSE `response.created` event.

> **Important:** the callback URL contains a single-use auth code; never commit it.
> `.gitignore` already excludes `.codex_*` artifacts. Tokens are stored in
> `~/.hermes/auth.json` (provider `openai-codex`) and survive container rebuilds
> because they live in the mounted data volume.

The resulting config in `~/.hermes/config.yaml`:

```yaml
model:
  base_url: https://chatgpt.com/backend-api/codex
  default: gpt-5.5
  provider: openai-codex
```

## Install options

```powershell
.\install.ps1 -DataDir "D:\hermes-data"              # custom data directory
.\install.ps1 -SkipSetup                             # skip wizard (config already exists)
.\install.ps1 -NoStart                               # build only, don't start
.\install.ps1 -BaseImage nousresearch/hermes-agent:v1.2.3  # pin upstream release
```

## Common commands

```powershell
# All commands must be run from this folder (hermes-docker/)

# Logs (live)
docker compose logs -f

# Stop / start
docker compose down
docker compose up -d

# Rebuild image after Dockerfile changes (e.g. SDK version bumps)
docker compose build --pull
docker compose up -d

# Gateway logs (detailed — s6-log writes here, not to docker logs)
docker compose exec hermes bash -c "tail -f /opt/data/logs/gateways/default/current"

# Gateway exit diagnostics (check when gateway crashes silently)
docker compose exec hermes bash -c "tail -20 /opt/data/logs/gateway-exit-diag.log"

# Verify Teams webhook is alive
docker compose exec hermes curl -s http://localhost:3978/health

# Interactive CLI chat
docker run -it --rm -v "$env:USERPROFILE\.hermes:/opt/data" hermes-evo:latest

# Open a shell in the running container
docker compose exec hermes bash
```

## Profiles

A Hermes **profile** is a separate `HERMES_HOME` (its own `config.yaml`, `.env`,
`SOUL.md`, skills, cron jobs, and state) that runs as its own s6-supervised gateway
**inside the same `hermes` container** — a separate agent, not a separate container.

### `studio` — daily photo workflow

`profiles/studio/` defines the **studio** profile: an unattended agent that runs the
[evo Photo Workflow](../photo-workflow-cowork-playbook-distilled) on a daily cron
(06:00). It refreshes the daily report, sources vendor images, processes them to the
PIM spec (1500×1500 JPG q95, white-flattened main, numeric-prefix order), and
**packages a PIM-ready ZIP** to `~/.hermes/outbox/studio/<date>/` for a human to
upload. It does not upload to PIM and never acts on a human's behalf in a live
system — human-only steps (VPN import, OAuth, image-order confirmation, PIM upload)
are recorded as blockers in the run's `MANIFEST.md`.

The image-manipulation tools it needs (`imagemagick`, `libvips-tools`, `webp`,
`zip`; Pillow ships in the base image) are installed by the `Dockerfile` and so are
baked into `hermes-evo:latest`. The profile itself lives in the bind-mounted volume
(`~/.hermes/profiles/studio`), so it survives image rebuilds.

`install.ps1` deploys the profile on every run (idempotent): creates it, copies the
scaffold + distilled playbook into the volume, applies `config.overrides`, ensures
the cron job, and starts the studio gateway (marked running so the container's boot
reconciler restores it after a rebuild).

```powershell
docker exec hermes hermes gateway list                 # default + studio status
docker exec hermes hermes -p studio cron list           # the daily job
docker exec hermes hermes -p studio cron run <job_id>    # fire on next tick (test)
docker compose exec hermes bash -c "tail -f /opt/data/logs/gateways/studio/current"
ls ~/.hermes/outbox/studio/                              # daily ZIP output
```

Skip the studio deploy with `.\install.ps1 -SkipStudio`. Point at a different
playbook source with `.\install.ps1 -PlaybookSource <path>`. See
[profiles/studio/README.md](profiles/studio/README.md) for full detail.

## Upgrading

```powershell
# Pull the latest upstream release and rebuild
.\install.ps1 -SkipSetup

# Or pin a specific release
.\install.ps1 -SkipSetup -BaseImage nousresearch/hermes-agent:v1.2.3
```

`install.ps1 -SkipSetup` skips the API key wizard and just rebuilds + restarts. It also **re-runs the studio profile deploy** (idempotent) so the rebuilt image's tools and the latest scaffold/playbook are picked up. The profile itself and its state survive the rebuild because they live in the `~/.hermes` volume. Add `-SkipStudio` to leave the studio profile untouched.

## Deploying to a new host

1. Install Docker Desktop and start it.
2. Install ngrok and run `ngrok config add-authtoken <token>`.
3. Copy this `hermes-docker/` folder to the new machine.
4. Copy (or recreate) `%USERPROFILE%\.hermes\.env` and `%USERPROFILE%\.hermes\config.yaml` with the Teams credentials above. `~/.hermes/.env` must contain `OPENAI_API_KEY` — the studio gateway needs it to run, and the deploy copies it into the profile.
5. For the studio profile, make the distilled playbook reachable — by default `install.ps1` looks for `..\photo-workflow-cowork-playbook-distilled` next to `hermes-docker/`. Copy it there, or pass `-PlaybookSource <path>`.
6. Run `.\install.ps1 -SkipSetup` from the `hermes-docker/` folder.
7. Start ngrok: `ngrok http 3978`
8. Update the bot's messaging endpoint in Azure Bot registration to the new ngrok URL.

The bot's `CLIENT_ID`, `CLIENT_SECRET`, and `TENANT_ID` are reused — no new Azure registration needed.

## File reference

| File | Purpose |
|---|---|
| `Dockerfile` | Extends upstream image, pre-installs Teams SDK + image tools (studio) |
| `docker-compose.yml` | Service definition — ports, volumes, env vars |
| `install.ps1` | One-command setup for Windows; also deploys the `studio` profile |
| `teams-bot-setup.ps1` | Registers the Azure bot and starts ngrok (default profile) |
| `teams-bot-setup-studio.ps1` | Registers a 2nd bot for the studio profile (:3979) and wires it |
| `publish-studio-outbox.ps1` | Mirrors the studio outbox into OneDrive (for the Power Automate flow) |
| `profiles/studio/` | The `studio` photo-workflow profile (SOUL, skills, config, cron) |
| `docs/power-automate-studio-outbox.md` | Flow: watch outbox → upload ZIP to a Teams channel |
| `.env` *(generated)* | Compose vars: `HERMES_DATA`, dashboard credentials |
| `.gitignore` | Excludes generated `.env` and data dirs |

## Notes

- **Never** run two containers against the same data directory simultaneously — the SQLite session/memory stores are not safe for concurrent writes.
- The image uses `s6-overlay` as PID 1 — it supervises and auto-restarts both the gateway and dashboard. `docker compose down` shuts everything down cleanly.
- Gateway output goes to `/opt/data/logs/gateways/default/current` (via s6-log), **not** to `docker compose logs`. Check that file for Teams connection details.
- The ngrok tunnel must be running before Teams can deliver messages. If ngrok restarts with a new URL, update the bot's messaging endpoint in the Azure portal.
- Port `3978` is published in `docker-compose.yml`. Teams messages flow: `Teams → Azure Bot Service → ngrok → host:3978 → container:3978 → Hermes gateway`.
- `install.ps1` writes a local `.env` with `HERMES_DATA` and dashboard credentials. This is **not** your secrets file — API keys and Teams credentials live in `~/.hermes/.env`.

### Studio profile notes

- The studio gateway is a **separate profile**, not a separate container — it has its own state DB under `~/.hermes/profiles/studio`, so it does not violate the "no concurrent writes to the same store" rule above.
- Studio gateway logs: `/opt/data/logs/gateways/studio/current` (the default gateway's are under `.../default/current`).
- The daily job runs **unattended with auto-approval** (`approvals.cron_mode: allow` in the profile config). It touches live vendor portals, Google Sheets, and fileservers. Review `profiles/studio/SOUL.md` and the playbook guardrails before changing its scope.
- Change the schedule (cron expression is UTC):
  ```powershell
  docker exec hermes hermes -p studio cron list                 # get the job id
  docker exec hermes hermes -p studio cron edit <job_id> --schedule "0 13 * * *"
  docker exec hermes hermes -p studio cron pause <job_id>        # disable
  docker exec hermes hermes -p studio cron run <job_id>          # fire on next tick (test)
  ```
- Daily output (PIM-ready ZIPs + `MANIFEST.md`) lands in `~/.hermes/outbox/studio/<YYYY-MM-DD>/`. Studio does **not** post to Teams or upload to PIM — a human takes the ZIP from the outbox. See [profiles/studio/README.md](profiles/studio/README.md).
