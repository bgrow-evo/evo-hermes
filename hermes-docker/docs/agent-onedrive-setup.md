# Give the studio agent its own OneDrive (rclone, one-time)

The studio agent reaches **its own** OneDrive — the drive of the M365 service account
`hermes-ai@evo.com` — through `rclone` (installed in the image). Auth is **delegated**
(the agent signs in *as* that account), so it gets a real personal `/me` drive with no
tenant-wide app permission. After this one-time setup the refresh token lives in the
volume and renews itself; rebuilds don't require re-auth.

```
Studio agent (container)
  └─ rclone --config /opt/data/profiles/studio/rclone.conf  agent-od:
        └─ OneDrive of hermes-ai@evo.com  (delegated OAuth, refresh token in rclone.conf)
```

## Prerequisites (M365 admin — yours)

1. `hermes-ai@evo.com` exists (the account already used for Codex OAuth).
2. It has a license that includes **OneDrive for Business** (e.g. Business Basic+).
3. Its OneDrive is **provisioned** — sign into https://portal.office.com once as that
   account and open OneDrive, or pre-provision via the SharePoint admin center.
   (`rclone about agent-od:` later confirms it's live.)

## Step 1 — authenticate (on a machine with a browser)

The OAuth step needs a browser, so do it on the **host** (Windows), then move the token
into the container. Install rclone on the host once:

```powershell
winget install --id Rclone.Rclone -e
```

Create the remote, signing in as the agent account:

```powershell
rclone config
# n) New remote
# name>            agent-od
# Storage>         onedrive            (Microsoft OneDrive)
# client_id>       <leave blank>
# client_secret>   <leave blank>
# tenant>          1c2caf71-5666-4b98-bffc-ae0da8c4a4db   (evo tenant; or leave blank)
# Edit advanced config?  n
# Use auto config?  y   -> browser opens; SIGN IN AS hermes-ai@evo.com
# (if headless: choose n and run the printed `rclone authorize "onedrive"` on a browser box)
# Your choice>     1   (OneDrive Personal or Business -> Business)
# choose the drive: the hermes-ai@evo.com drive
# Yes this is OK
# q) Quit config
```

Confirm it works on the host:

```powershell
rclone about agent-od:        # prints quota -> auth + drive provisioning OK
rclone lsd  agent-od:
```

## Step 2 — move the token into the container's volume

`rclone config file` on the host prints the path (usually
`%APPDATA%\rclone\rclone.conf`). Copy **only the `[agent-od]` stanza** into the studio
profile's config in the volume so the agent uses it:

```powershell
# Where the agent reads it (host view of the volume):
$dst = "$env:USERPROFILE\.hermes\profiles\studio\rclone.conf"
Copy-Item (rclone config file | Select-Object -Last 1) $dst -Force   # simplest: copy whole conf
```

> If your host `rclone.conf` has other remotes you don't want in the container, copy the
> file then delete the unrelated stanzas — keep `[agent-od]` only.

## Step 3 — verify from inside the agent

```powershell
docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf about agent-od:
docker exec hermes rclone --config /opt/data/profiles/studio/rclone.conf lsd  agent-od:
```

Quota output = the agent can now read/write its OneDrive. The `agent-onedrive` skill
documents the day-to-day commands; the studio pipeline pushes PIM-ready packages to
`agent-od:HermesStudioOutbox/<date>/` on **live** runs.

## Notes

- **Token refresh:** rclone stores a refresh token and renews access tokens
  automatically. Re-auth (repeat Step 1) only if the refresh token is revoked or the
  account password/MFA policy forces it.
- **Security:** the token in `rclone.conf` grants access to that account's OneDrive.
  It lives only in the volume (`~/.hermes/profiles/studio/`), which is gitignored and
  never in the repo. Treat it like a credential.
- **Dry-run:** the agent skips the OneDrive push while `DRY_RUN` is set (it cascades to
  a Teams channel post). Read/list is always allowed.
- This replaces the host `publish-studio-outbox.ps1` robocopy step — the agent writes
  to OneDrive directly, so Power Automate can watch `agent-od`'s `HermesStudioOutbox`.
