# Hermes on Teams as the `hermes-ai@evo.com` user (teams_graph adapter)

Talk to `@hermes-ai` — the licensed user — in a 1:1 DM or group chat. No Teams
app, no Bot Framework, no threads. Mirrors the Nextcloud Talk operating model:
bot *user* account, poll chats, reply inline as that user.

> Supersedes the Bot Framework `@Hermes` app path (now in `archive/`). The old bot
> registrations stay dormant during burn-in and get retired after.

## Architecture

```
Bill (Teams)                          hermes-ai@evo.com (licensed user)
  |  DM or group chat, plain messages      |
  v                                        v
Microsoft Graph (delegated: Chat.ReadWrite, ChannelMessage.Send, User.Read, offline_access)
  ^ poll /chats/{id}/messages every ~3s            | POST /chats/{id}/messages (inline reply)
  |                                                v
/opt/hermes/plugins/platforms/teams_graph/adapter.py   (baked into the evo image)
  +-- default profile: "Hermes Admin" group chat + all 1:1 DMs (dm_mode=all)
  +-- studio  profile: "Studio Photo" group chat (dm_mode=none)
  +-- shared MSAL token cache: /opt/data/.graph_user_token_cache.json
```

- Delegated own-chat reads — NOT the metered tenant-wide `getAllMessages` APIs.
- No inbound public endpoint needed for chat (polling is outbound HTTPS).
- Channels stay proactive-post-only via the existing `agent-teams-post` skill
  (channels are structurally threaded for users too — flat chat only exists in
  DMs/group chats).

## One-time setup

### 1. Entra app + admin consent (Bill, tenant admin)

```powershell
cd C:\Users\bgrow\Projects\evo_photo\hermes-docker
.\provision-hermes-ai-graph.ps1 -SkipPrompt
```

Creates/updates the public-client app **"Hermes Studio Teams Post (delegated)"**
with delegated scopes `Chat.ReadWrite`, `ChannelMessage.Send`, `User.Read`,
`offline_access` (IDs resolved dynamically), grants tenant admin consent, and
writes `TEAMS_GRAPH_CLIENT_ID` / `TEAMS_GRAPH_TENANT_ID` into
`~/.hermes/.env` and `~/.hermes/profiles/studio/.env`.

### 2. Create the chats (Teams UI)

1. Group chat **"Hermes Admin"** — members: you + `hermes-ai@evo.com`.
2. Group chat **"Studio Photo"** — members: you + `hermes-ai@evo.com`.
3. Send hermes-ai one 1:1 DM (materialises the DM chat).

### 3. Device-code sign-in as hermes-ai (one time, browser + MFA)

```powershell
docker run --rm -e TEAMS_GRAPH_CLIENT_ID=<client-id> -e HERMES_HOME=/opt/data `
  -v $env:USERPROFILE\.hermes:/opt/data `
  -v $PWD\plugins\teams_graph\scripts:/scripts:ro `
  --entrypoint /opt/hermes/.venv/bin/python3 nousresearch/hermes-agent:latest /scripts/graph_login.py
```

Complete the printed code at https://microsoft.com/devicelogin **as
hermes-ai@evo.com**. Refresh token lands in
`~/.hermes/.graph_user_token_cache.json` (0600; treat as a credential — it is
gitignored and must never be committed).

### 4. Capture chat IDs

```powershell
docker run --rm -e TEAMS_GRAPH_CLIENT_ID=<client-id> -e HERMES_HOME=/opt/data `
  -v $env:USERPROFILE\.hermes:/opt/data -v $PWD\plugins\teams_graph\scripts:/scripts:ro `
  --entrypoint /opt/hermes/.venv/bin/python3 nousresearch/hermes-agent:latest /scripts/list_chats.py
```

Put the group-chat IDs in `~/.hermes/.env`:

```env
HERMES_ADMIN_CHAT_ID=19:...@thread.v2
STUDIO_CHAT_ID=19:...@thread.v2
```

### 5. Seed the token cache into Azure Files + deploy

```powershell
az storage file upload --account-name sthermessbxwu2 --share-name hermes-data `
  --source $env:USERPROFILE\.hermes\.graph_user_token_cache.json --path .graph_user_token_cache.json

.\scripts\azure\Deploy-HermesStandardStorage.ps1 -Push -SkipPrompt -SkipTeamsUpdate
```

`hermes-aca-configure-profiles.sh` restores the cache from
`/mnt/hermes-persist` on boot and configures `platforms.teams_graph` on both
profiles (per-profile chat routing lives in each profile's config.yaml, NOT in
container env — both gateways share the env).

## Runtime behavior

| Surface | Profile | Notes |
|---|---|---|
| 1:1 DM with hermes-ai | `default` | auto-discovered (`dm_mode: all`) |
| "Hermes Admin" group chat | `default` | configured chat ID |
| "Studio Photo" group chat | `studio` | configured chat ID |
| Any other chat | ignored | not in poll set; unauthorized senders dropped |
| Private channels | proactive posts only | existing `agent-teams-post` skill |

- Replies show as **hermes-ai**, inline, no thread.
- `/new` in a chat resets only that chat's session.
- Allowlist: `TEAMS_GRAPH_ALLOWED_USERS` (AAD object IDs / UPNs), seeded from
  `TEAMS_ALLOWED_USERS` when unset.
- Watermarks persist at `<profile-home>/.teams_graph_state.json` — no replay
  after restart.

## Ops

- **Health**: gateway logs show `teams_graph: polling N chat(s) every 3s`.
- **Token death** (password reset, CA policy change, 90-day idle): adapter goes
  fatal with `auth_expired` — re-run step 3, re-upload the cache (step 5), and
  restart the revision. It never silently re-auths.
- **Throttling**: Graph 429s are backed off automatically; ~3 chats at 3s poll
  is ~1 req/s — far under chat-read limits.
- **Retire the bot path** (after burn-in): remove `/api/messages` routing from
  `hermes-aca-proxy.py`, disable `platforms.teams` on both profiles, archive the
  Bot Framework app registrations (`3146b701-…`, `521aaadb-…`).
