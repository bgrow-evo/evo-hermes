# Hermes Agent — evo deployment (Azure Container Apps + Teams as `hermes-ai`)

Custom Docker/Azure setup for the [Nous Research Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/docker), preconfigured for evo's photo workflow. Hermes talks on Microsoft Teams **as the licensed user `hermes-ai@evo.com`** via delegated Microsoft Graph — no Teams app, no Bot Framework registration, no threaded replies.

> The earlier Bot Framework / Teams-app approach was retired 2026-07-16. Its scripts and manifest live in [`archive/`](archive/) for reference only. Full setup + ops detail for the current model: [docs/hermes-ai-chat-setup.md](docs/hermes-ai-chat-setup.md).

## Architecture

```
Bill / team (Teams)                    hermes-ai@evo.com (licensed user)
   │  1:1 DM or group chat, plain messages     │
   ▼                                           ▼
Microsoft Graph  (delegated: Chat.ReadWrite, ChannelMessage.Send, User.Read, offline_access)
   ▲  poll /chats/{id}/messages every ~3s              │ POST /chats/{id}/messages (inline reply)
   │                                                   ▼
Azure Container App: aca-hermes-nfs  (image acrhermessbx.azurecr.io/hermes:<tag>)
   ┌──────────────────────────────────────────────────────────────┐
   │  s6-overlay (PID 1)                                          │
   │  ├─ aca-proxy (:8080 — ACA ingress/health)                   │
   │  ├─ gateway: default  ── teams_graph adapter                 │
   │  │     DMs with hermes-ai (dm_mode=all) + Hermes Admin chat  │
   │  ├─ gateway: studio   ── teams_graph adapter                 │
   │  │     "Studio Photo" group chat + daily photo-workflow cron │
   │  └─ aca-sync (60s snapshot /opt/data → Azure Files)          │
   └──────────────────────────────────────────────────────────────┘
        /opt/data (EmptyDir, live)  ⇄  /mnt/hermes-persist
                                        Azure Files: sthermessbxwu2/hermes-data
                                        ── SINGLE SOURCE OF TRUTH ──
```

Key properties:

- **No inbound webhook needed for chat.** The `teams_graph` adapter polls hermes-ai's own chats outbound over HTTPS (delegated Graph — not the metered tenant-wide APIs). No ngrok, no public bot endpoint, no manifest publishing.
- **Flat, inline conversations.** DMs and group chats are non-threaded surfaces. (Teams *channels* are structurally threaded for users too — the existing [`agent-teams-post`](docs/agent-teams-post-setup.md) skill covers proactive channel posts.)
- **One chat → one profile.** Chat IDs are wired per profile; each profile has its own config, skills, memory, sessions, and pairing store.
- **The Azure Files share is authoritative.** Restored to `/opt/data` on boot, snapshotted back every 60s. There is deliberately **no image seeding** — profile changes are made on the volume and survive image upgrades.

## Teams connection (teams_graph)

| Piece | Value |
|---|---|
| Adapter | [`plugins/teams_graph/adapter.py`](plugins/teams_graph/adapter.py), baked into the image at `/opt/hermes/plugins/platforms/teams_graph/` (auto-loads) |
| Identity | `hermes-ai@evo.com` (licensed user; replies appear as that user) |
| Entra app | "Hermes Studio Teams Post (delegated)" — public client `8723feb3-bb77-4a0e-9c04-bbde8ec2cf37`, admin-consented delegated scopes `Chat.ReadWrite`, `ChannelMessage.Send`, `User.Read`, `offline_access` |
| Auth | One-time device-code sign-in → refresh token cached at `/opt/data/.graph_user_token_cache.json` (shared by both gateways, synced to the share, self-heals across rotation via mtime reload) |
| Routing | `default` profile: all 1:1 DMs (`dm_mode: all`) + `HERMES_ADMIN_CHAT_ID`. `studio` profile: `STUDIO_CHAT_ID` ("Studio Photo" group chat) |
| Authorization | Hermes pairing per profile (`hermes pairing approve teams_graph <code>`) + optional `TEAMS_GRAPH_ALLOWED_USERS` allowlist |
| Config | Written per profile by `scripts/aca/hermes-aca-configure-profiles.sh` at boot from env (`TEAMS_GRAPH_CLIENT_ID`, `TEAMS_GRAPH_TENANT_ID`, chat IDs). Per-profile values live in each profile's `config.yaml`, never in shared container env |

### One-time setup

1. **Provision the Entra app + admin consent** (tenant admin):
   ```powershell
   .\provision-hermes-ai-graph.ps1 -SkipPrompt
   ```
2. **Create the chats**: group chat per profile (add `hermes-ai@evo.com` as member); a 1:1 DM works immediately once discovered.
3. **Device-code sign-in as hermes-ai** (browser + that account's MFA):
   ```powershell
   docker run --rm -e TEAMS_GRAPH_CLIENT_ID=<client-id> -e HERMES_HOME=/opt/data `
     -v $env:USERPROFILE\.hermes:/opt/data -v $PWD\plugins\teams_graph\scripts:/scripts:ro `
     --entrypoint /opt/hermes/.venv/bin/python3 nousresearch/hermes-agent:latest /scripts/graph_login.py
   ```
4. **Capture chat IDs** with `plugins/teams_graph/scripts/list_chats.py` (same docker pattern) and set `HERMES_ADMIN_CHAT_ID` / `STUDIO_CHAT_ID` in `~/.hermes/.env`.
5. **Seed the token cache into the share** and deploy:
   ```powershell
   az storage file upload --account-name sthermessbxwu2 --share-name hermes-data `
     --source $env:USERPROFILE\.hermes\.graph_user_token_cache.json --path .graph_user_token_cache.json
   .\scripts\azure\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt
   ```
6. **Pair each human, per profile**: first message gets a pairing code; approve it on the server (see ops below). Approvals persist on the share.

### Re-auth runbook (refresh token dead: password reset, CA policy, 90-day idle)

The adapter goes fatal with `auth_expired` and retries on a backoff — no restart needed once the cache is fixed:

1. Re-run the device-code sign-in (step 3 above).
2. Upload the fresh cache to the share root (step 5 command).
3. The sync loop pulls it to live within 60s (newest-wins) and the adapter reconnects.

## Azure deployment

| Resource | Name |
|---|---|
| Resource group | `rg-hermes-sbx` |
| Container app | `aca-hermes-nfs` (env `aca-env-hermes-nfs-sbx-wu2`, vnet `vnet-hermes-sbx-wu2`) |
| Registry | `acrhermessbx.azurecr.io/hermes:<tag>` |
| Data share | `sthermessbxwu2` / `hermes-data` (Standard Azure Files, SMB) |
| FQDN | `aca-hermes-nfs.whiteplant-ace3060d.westus2.azurecontainerapps.io` |

```powershell
# Build image in ACR (≈2 min)
.\scripts\azure\Build-HermesImage.ps1 -SubscriptionName Playground -AcrName acrhermessbx -ImageTag <tag>

# Deploy a revision (reads ~/.hermes/.env for TEAMS_GRAPH_* + chat IDs)
.\scripts\azure\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt -SkipBuild -ImageTag <tag>

# Health
curl.exe -s https://aca-hermes-nfs.whiteplant-ace3060d.westus2.azurecontainerapps.io/healthz
curl.exe -s https://aca-hermes-nfs.whiteplant-ace3060d.westus2.azurecontainerapps.io/default/health
curl.exe -s https://aca-hermes-nfs.whiteplant-ace3060d.westus2.azurecontainerapps.io/studio/health
```

Profile state (skills, playbook, sessions, memories, pairing, token cache) survives every deploy: boot restores the share into `/opt/data`, the sync loop snapshots back every 60s and on shutdown.

### Server ops (ACA exec has NO shell)

`az containerapp exec --command` passes the string as argv — redirects, quotes, and `&&` do **not** work, and the `hermes` CLI breaks the exec socket. Working pattern:

1. Write a small `.sh` script locally; upload it to the share under **`.cache/`** (that path is excluded from the sync loop's `--delete`, so it isn't cleaned away):
   ```powershell
   az storage file upload --account-name sthermessbxwu2 --share-name hermes-data --source my-op.sh --path .cache/my-op.sh
   ```
2. Execute it (quote-free): `az containerapp exec -n aca-hermes-nfs -g rg-hermes-sbx --command "sh /mnt/hermes-persist/.cache/my-op.sh"`
3. Have the script write results to `/mnt/hermes-persist/.cache/…` and download them with `az storage file download`.

Rules learned the hard way:
- Scripts must `export HOME=/opt/data HERMES_HOME=/opt/data` (or the profile home) before calling the `hermes` CLI.
- exec runs as **root** — `chown -R 10000:10000` anything the script touches under `/opt/data` (pairing store: `/opt/data/platforms/pairing`, per profile `/opt/data/profiles/<p>/platforms/pairing`), or the gateway can't read it.
- Adapter success logs are INFO-level and invisible in `az containerapp logs` — verify liveness via the `.teams_graph_state.json` watermark files on the share, or the per-profile `logs/gateway.log`.
- Installing/changing **skills** on a running profile: install to the volume, then delete `<profile-home>/.skills_prompt_snapshot.json` and restart the revision (the gateway caches its skill index at boot).

### Pairing a new user (per profile)

First message from an unknown user returns a pairing code. Approve it server-side with the script pattern above running:

```sh
hermes pairing approve teams_graph <CODE>              # default profile
hermes -p studio pairing approve teams_graph <CODE>    # studio profile
```

(then chown the pairing stores — see rules above). Approvals persist on the share.

## LLM provider — OpenAI Codex via OAuth

Hermes runs on the `openai-codex` provider (`gpt-5.6-terra`), authenticated against the
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
> because they live in the mounted data volume. On ACA the same file lives on the
> data share.

The resulting config in `~/.hermes/config.yaml`:

```yaml
model:
  base_url: https://chatgpt.com/backend-api/codex
  default: gpt-5.6-terra
  provider: openai-codex
```

## Profiles

A Hermes **profile** is a separate `HERMES_HOME` (its own `config.yaml`, `.env`,
`SOUL.md`, skills, cron jobs, and state) that runs as its own s6-supervised gateway
inside the same container — a separate agent, not a separate container.

### `studio` — daily photo workflow

The **studio** profile is an unattended agent for the evo photo workflow. It owns the
"Studio Photo" group chat, the custom skills (`studio-daily-pipeline`,
`evo-image-processing`, `agent-blob`, `agent-teams-post`), and the operating playbook
at `profiles/studio/playbook/` (guardrails, standards, prompts). On the server these
live on the data share under `profiles/studio/`.

A scheduled job (`hermes -p studio cron list`) runs the pipeline dry-run daily at
06:00 UTC and delivers results into the Studio Photo chat. Output ZIPs + `MANIFEST.md`
land in `/opt/data/outbox/studio/<date>/`, with blob download links via the
`agent-blob` skill.

> The repo's `profiles/studio/` tree is **reference material** — the live copy on the
> share is authoritative. The DAM credential in
> `playbook/context/standards/vendor-dam-guide.md` is redacted in the repo copy; the
> Merch Sheet is the source of truth for vendor logins.

## Local development (docker compose)

`install.ps1` still supports a local run (builds `hermes-evo:latest`, mounts
`~/.hermes` as `/opt/data`). The teams_graph adapter polls outbound, so local Hermes
can chat on Teams with **no tunnel** — it just needs the Graph token cache + env
vars present in `~/.hermes`. Don't run local and ACA against the same chats at the
same time (both would answer).

```powershell
.\install.ps1              # first install (wizard)
.\install.ps1 -SkipSetup   # rebuild + restart
docker compose logs -f
docker compose exec hermes bash
```

> Never run two containers against the same data directory simultaneously — the
> SQLite stores are not safe for concurrent writes.

## File reference

| File | Purpose |
|---|---|
| `Dockerfile` | Extends pinned `nousresearch/hermes-agent:v2026.7.20`; bakes Teams SDK deps, image tools, the `teams_graph` adapter, and ACA hook scripts |
| `plugins/teams_graph/` | The Graph-user Teams adapter + ops scripts (`graph_login.py`, `list_chats.py`, `graph_whoami.py`) |
| `provision-hermes-ai-graph.ps1` | One-time: Entra public-client app, delegated Graph scopes, admin consent, env wiring |
| `scripts/azure/Build-HermesImage.ps1` | ACR cloud build |
| `scripts/azure/Deploy-HermesStandardStorage.ps1` | Roll an ACA revision (env, secrets, volumes) |
| `scripts/aca/hermes-aca-configure-profiles.sh` | Boot hook: sources s6 env, configures both profiles (model, teams_graph, home chats) |
| `scripts/aca/hermes-aca-restore.sh` / `hermes-aca-sync.sh` | Share→live restore on boot / live→share snapshot every 60s (token cache newest-wins) |
| `scripts/aca/hermes-aca-proxy.py` | :8080 ingress — health endpoints + path routing |
| `docs/hermes-ai-chat-setup.md` | Full teams_graph setup + ops doc |
| `docs/agent-teams-post-setup.md` | Proactive channel posting as hermes-ai (private channels) |
| `docs/agent-blob-setup.md` | Studio agent's Azure Blob storage (rclone + SP) |
| `install.ps1` / `docker-compose.yml` | Local dev run |
| `profiles/studio/` | Studio profile reference copy (skills, playbook — DAM password redacted) |
| `archive/` | Retired Bot Framework / Teams-app scripts, manifest, and old handoffs |

## Notes

- The image uses `s6-overlay` as PID 1; it supervises and auto-restarts gateways.
- Gateway logs on ACA: per-profile `logs/gateway.log` under each profile home on the share (container stdout only carries WARN/ERROR).
- The `platforms.teams` (Bot Framework) adapter and `/api/messages` proxy routes still exist in config/code but are **dormant and unused** — scheduled for removal after the burn-in period, along with the old bot Entra registrations (`3146b701-…`, `521aaadb-…`).
