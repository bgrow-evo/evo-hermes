---
name: agent-blob
description: "Access the studio agent's own Azure Blob Storage container via rclone (service-principal auth, headless). Use to push PIM-ready packages to blob for downstream Teams delivery, or to read/list blobs the agent owns. This is the agent's own container, not evo's shared SharePoint/Drive."
version: 1.0.0
author: evo studio
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [azure, blob, rclone, storage, delivery, evo, studio]
    related_skills: [studio-daily-pipeline, evo-image-processing]
---

# Agent Blob Storage (Azure, via rclone)

You have your **own** Azure Blob Storage container, reached with `rclone` (installed in
this container) using a service principal — fully headless, no user sign-in. This is
your delivery/scratch space, **not** evo's shared SharePoint or any team Drive.

## Connection

- Remote name: **`agent-blob`**  (the storage account)
- Container: **`studio-outbox`**  (first path segment after the remote)
- Config file (in the volume, persists across rebuilds): `/opt/data/profiles/studio/rclone.conf`
- Always pass `--config`:

```bash
RC="rclone --config /opt/data/profiles/studio/rclone.conf"
$RC lsd  agent-blob:                 # list containers -> auth works
$RC ls   agent-blob:studio-outbox    # list blobs in the container
```

If these error with an auth/credential message, the remote isn't set up — stop and
report it; do **not** try to re-auth (that needs the service-principal secret; see
`docs/agent-blob-setup.md`).

## Common operations

```bash
RC="rclone --config /opt/data/profiles/studio/rclone.conf"

# Push a day's PIM-ready output to blob (copy = never deletes):
$RC copy /opt/data/outbox/studio/2026-06-22 "agent-blob:studio-outbox/2026-06-22" \
   --include "*_pim-ready.zip" --include "MANIFEST.md" --include "*_contact-sheet.png"

# Verify what landed:
$RC ls "agent-blob:studio-outbox/2026-06-22"
```

Use `copy` (not `sync`). A Power Automate flow watching `studio-outbox` posts the ZIP
into Teams (see `docs/power-automate-studio-outbox.md`, Option A).

## Rules

- **Dry-run:** pushing to blob triggers the downstream Teams post, so treat it as an
  external delivery — **skip it in dry-run** and log it as "would push to blob". Only
  push when LIVE. Read/list is always fine.
- Push only finished PIM-ready artifacts (ZIP, manifest, contact sheet) — keep raw
  source images out of blob.
