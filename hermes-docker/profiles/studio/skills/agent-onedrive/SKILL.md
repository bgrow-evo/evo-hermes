---
name: agent-onedrive
description: "Access the studio agent's own OneDrive via rclone (delegated, signed in as the agent's M365 service account). Use to push PIM-ready packages to OneDrive for downstream Teams delivery, or to read/list files the agent owns. Not for evo's shared SharePoint/Drive — this is the agent's personal drive only."
version: 1.0.0
author: evo studio
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [onedrive, rclone, msgraph, delivery, evo, studio]
    related_skills: [studio-daily-pipeline, evo-image-processing]
---

# Agent OneDrive (rclone)

You have your **own** OneDrive — the drive of the agent's M365 service account
(`hermes-ai@evo.com`). Access it with `rclone`, which is installed in this container.
This is your personal delivery/scratch space, **not** evo's shared SharePoint or any
team Drive. Never use it to bypass the dry-run rule for evo's shared systems.

## Connection

- Remote name: **`agent-od`**
- Config file (in the volume, persists across rebuilds): `/opt/data/profiles/studio/rclone.conf`
- Always pass `--config` so you use the right token regardless of environment:

```bash
RC="rclone --config /opt/data/profiles/studio/rclone.conf"
$RC about agent-od:                 # sanity check: shows quota -> auth works
$RC lsd  agent-od:                  # list top-level folders
```

If `rclone about agent-od:` errors with "didn't find section" or a token error, the
remote isn't set up yet — stop and report it; do **not** try to re-auth (that needs a
human browser sign-in; see `docs/agent-onedrive-setup.md`).

## Common operations

```bash
RC="rclone --config /opt/data/profiles/studio/rclone.conf"

# Push a day's PIM-ready output to OneDrive (mirrors, only newer files):
$RC copy /opt/data/outbox/studio/2026-06-22 "agent-od:HermesStudioOutbox/2026-06-22" \
   --include "*_pim-ready.zip" --include "MANIFEST.md" --include "*_contact-sheet.png"

# Verify what landed:
$RC ls "agent-od:HermesStudioOutbox/2026-06-22"
```

Use `copy` (not `sync`) so you never delete anything already in OneDrive. Target a
dedicated `HermesStudioOutbox/<date>/` folder so a Power Automate flow can watch it and
post the ZIP into Teams (see `docs/power-automate-studio-outbox.md`, Option A).

## Rules

- **Dry-run:** pushing to OneDrive triggers the downstream Teams post, so treat it as an
  external delivery — **skip it in dry-run** and log it as "would push to OneDrive".
  Only push when LIVE.
- Read/list operations are always fine.
- Keep large raw source images out of OneDrive — push only the finished PIM-ready
  artifacts (ZIP, manifest, contact sheet).
