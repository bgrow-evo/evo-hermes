---
name: agent-teams-post
description: "Post messages to a private Teams channel via delegated Microsoft Graph auth (hermes-ai@evo.com). One-time device-code setup; then silent token refresh thereafter."
version: 1.0.0
author: evo studio
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [teams, msgraph, msal, delivery, private-channel, evo, studio]
    related_skills: [studio-daily-pipeline, agent-blob]
---

# agent-teams-post

Post messages into a **private** Teams channel using delegated Microsoft Graph auth as
`hermes-ai@evo.com`. This solves the Microsoft Teams platform limitation: bots cannot
reliably post into private channels, but licensed users can post as themselves.

Unlike the Bot Framework reply path (which requires an active chat conversation to reply
into), this skill posts **proactively** to a fixed team/channel — ideal for unattended
cron runs and private channels.

This is a **third delivery path**, separate from:
- Bot Framework replies (interactive DMs / standard channels)
- Azure Blob SAS links (fallback for any channel via the blob skill)

## Architecture

```
One-time (human + browser):
  hermes-ai@evo.com  ──device-code sign-in──>  Entra app "Hermes Studio Teams Post" (public client)
                                                    OAuth 2.0 device flow, scope ChannelMessage.Send + offline_access
                                                    v
                                        refresh token cached in
                                        /opt/data/profiles/studio/.graph_user_token_cache.json

Headless (every run):
  post_channel_message.py  ──silent refresh-->  Microsoft Graph v1.0
                                                    POST /teams/{team-id}/channels/{channel-id}/messages
```

## Setup

See `docs/agent-teams-post-setup.md` for the one-time provisioning flow (Entra app,
environment variables, device-code sign-in). That doc is the source of truth for
getting started.

## Common operations

`scripts/graph_whoami.py` — diagnostic: confirms token + auto-refresh are working,
prints the signed-in account (should be `hermes-ai@evo.com`). **No side effects.**

```bash
/opt/hermes/.venv/bin/python3 scripts/graph_whoami.py
```

`scripts/post_channel_message.py` — the main send. Posts a message (text or HTML-formatted)
to the team/channel configured in the profile's `.env`.

```bash
# Send a real message
/opt/hermes/.venv/bin/python3 scripts/post_channel_message.py \
  --text "Daily job complete. <a href='$DOWNLOAD_LINK'>Get the ZIP</a>"

# Send an obvious test message (for verification during setup)
/opt/hermes/.venv/bin/python3 scripts/post_channel_message.py --test
```

## Rules

- **Scope**: Posts **only** to the specific team/channel wired up during setup
  (`TEAMS_GRAPH_TEAM_ID` / `TEAMS_GRAPH_CHANNEL_ID` in the profile `.env`). Does not
  support arbitrary team/channel targeting.
- **Dry-run gating**: **Does not post while `DRY_RUN` is set**, matching the existing
  Teams-posting rule in `studio-daily-pipeline`. Read/list operations are unaffected.
- **Auth errors**: On any token/Graph error (401, 403, network), stop and report; do
  **not** attempt to re-auth (that needs the human device-code login, a bounded operation
  documented in setup).
- **Interactive only**: This is **not** a replacement for the Bot Framework reply path
  (which works in live DM/channel conversations). Use it only when there is no live
  conversation to reply into — i.e., unattended cron or private-channel delivery.

## Notes

- **Token refresh**: MSAL handles it silently. Re-do the device-code sign-in only if
  the refresh token is revoked (password reset, Conditional Access policy, 90-day idle
  expiry).
- **Service principal isolation**: No secrets are baked into the skill. The refresh token
  lives only in the volume (`~/.hermes/profiles/studio/.graph_user_token_cache.json`),
  which is gitignored.
- **Graph scope**: Delegated `ChannelMessage.Send` + `offline_access` only. This does
  not grant other permissions (no mail send, no calendar, no directory access).
- **Private channels**: This skill works in private channels precisely because it posts
  as the user, not as an app. The user must be a member of the channel (a normal
  add-member operation, separate from app install).
