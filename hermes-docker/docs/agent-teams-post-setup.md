# Post messages to a private Teams channel (delegated Microsoft Graph auth)

The studio agent can post its daily summary into a **private** Teams channel by posting as
`hermes-ai@evo.com` via delegated Microsoft Graph, not via the Bot Framework (which cannot
reliably post into private channels — a Microsoft Teams platform limitation).

## Architecture

```
hermes-ai@evo.com  ──device-code sign-in──>  Entra app "Hermes Studio Teams Post" (public client)
                                                    OAuth 2.0 device flow
                                                    scopes: ChannelMessage.Send + offline_access
                                                    v
                                        refresh token cached locally
                                        ~/.hermes/profiles/studio/.graph_user_token_cache.json

    (then, every run)

post_channel_message.py  ──silent refresh──>  Microsoft Graph v1.0
                                                    POST /teams/{team-id}/channels/{channel-id}/messages
```

## Step 1 — Provision Entra app (run on host)

The shared Graph Entra app for the whole hermes-ai integration (chat adapter +
this channel-post skill) is provisioned by **`provision-hermes-ai-graph.ps1`** —
it grants `ChannelMessage.Send` plus the chat scopes and writes
`TEAMS_GRAPH_CLIENT_ID` / `TEAMS_GRAPH_TENANT_ID` into `~/.hermes/.env` and the
studio profile `.env`.

```powershell
cd C:\Users\bgrow\Projects\evo_photo\hermes-docker
.\provision-hermes-ai-graph.ps1 -SkipPrompt
```

The script is **idempotent** — run it multiple times safely. For channel posting,
additionally set `TEAMS_GRAPH_TEAM_ID` / `TEAMS_GRAPH_CHANNEL_ID` in the studio
profile `.env` (the target team/channel for the daily-summary post).

## Step 2 — Add hermes-ai@evo.com as a channel member (Teams UI)

The account must be a **member** of the channel (a normal member-add action, different from
the blocked app-install). A channel owner can add them:

1. In Teams, open the "Hermes POC" channel.
2. Channel settings → Members → Add member.
3. Search for `hermes-ai@evo.com` and add.

The device-code sign-in in Step 3 will fail if the account is not a channel member.

## Step 3 — One-time device-code sign-in (interactive, browser)

This signs in `hermes-ai@evo.com` once, mints a refresh token, and caches it locally
so the agent can post without prompting again.

**Run inside the Docker container** (so the cache lands directly in the persistent volume):

```powershell
# Copy the login script into the container
docker cp .\profiles\studio\skills\agent-teams-post\scripts\graph_login.py hermes:/tmp/graph_login.py

# Run it as the hermes user
docker compose exec --user hermes hermes bash -c `
  "HERMES_HOME=/opt/data/profiles/studio /opt/hermes/.venv/bin/python3 /tmp/graph_login.py"
```

The script prints:
```
To sign in, use a web browser to open the page https://microsoft.com/devicelogin
and enter the code XXXXXXXXX to authenticate.
```

**You must complete this in a browser as `hermes-ai@evo.com`** (requires that account's
password + any MFA enrolled on it). The script blocks until you do.

On success:
```
✓ Signed in as hermes-ai@evo.com
```

The refresh token is now cached at `/opt/data/profiles/studio/.graph_user_token_cache.json`
(inside the container; on the host, this is `~/.hermes/profiles/studio/.graph_user_token_cache.json`).

## Step 4 — Verify (non-destructive diagnostic)

Confirm that the token + silent refresh work:

```powershell
docker compose exec --user hermes hermes bash -c `
  "HERMES_HOME=/opt/data/profiles/studio /opt/hermes/.venv/bin/python3 /opt/data/profiles/studio/skills/agent-teams-post/scripts/graph_whoami.py"
```

Expected output:
```
✓ Hermes AI <hermes-ai@evo.com>
```

If this fails with `interaction_required`, re-run Step 3. If it fails with `token_not_found`,
re-run Step 3 (the sign-in didn't complete).

## Step 5 — Send a test message

```powershell
docker compose exec --user hermes hermes bash -c `
  "HERMES_HOME=/opt/data/profiles/studio /opt/hermes/.venv/bin/python3 /opt/data/profiles/studio/skills/agent-teams-post/scripts/post_channel_message.py --test"
```

Expected output:
```
✓ Message posted to b2bf59a4-0aaa-47b3-a985-a3a17668b29e/19:3_P4d9-3DQ2MAcVxhPs9nBo_IPRsvdFbkOSpHqZ-Sqc1@thread.tacv2
```

Then check the **Hermes POC** channel in Teams. The test message should appear:
```
✅ Hermes Studio Graph-post test — 2026-07-13T...
```

## Step 6 — Wire into studio-daily-pipeline (optional)

If testing succeeds, update `studio-daily-pipeline` to call `post_channel_message.py` on live
(non-dry-run) runs to post the daily summary into the private channel. See that skill's
"Final output / delivery to chat" section for integration guidance.

---

## Notes

### Token refresh is automatic

The `msal` library handles refresh silently. As long as the refresh token is valid
(hasn't been revoked by password reset, policy change, or 90-day inactivity), the agent
can post without re-auth.

### Re-auth: when needed

If `graph_whoami.py` returns `interaction_required`, the refresh token is dead. Re-run
**Step 3** (device-code sign-in) to get a fresh one. This is a bounded, documented operation.

### Least privilege

The Entra app has **only** `ChannelMessage.Send` (delegated) — it cannot read mail, access
calendar, list users, or do anything else. The refresh token is scoped to this one permission.

### Token cache is a credential

The file `~/.hermes/profiles/studio/.graph_user_token_cache.json` contains the refresh token
for `hermes-ai@evo.com`. Treat it like a password:
- Never commit it to version control (it's gitignored).
- Never share it.
- If compromised, `hermes-ai@evo.com` can revoke it by changing their password.

### Private channels only

This skill posts **only** to the specific team/channel wired up (via `TEAMS_GRAPH_TEAM_ID`
and `TEAMS_GRAPH_CHANNEL_ID`). To change the target channel, edit the provisioning script
or manually update those env vars, then re-run the provisioning step.

The account must be a **member** of any channel you target. If you need to post to a different
channel, add `hermes-ai@evo.com` as a member there, then update the env vars.
