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
- The config path is preset via the `RCLONE_CONFIG` env var
  (`/opt/data/profiles/studio/rclone.conf`), so plain `rclone` already finds the
  remote. Passing `--config "$RCLONE_CONFIG"` explicitly is harmless and recommended:

```bash
RC="rclone --config $RCLONE_CONFIG"
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

Use `copy` (not `sync`).

## Posting a download link to the chat

You can hand the user a direct download link for any blob — works in a **DM or a
channel** (no Power Automate needed). A read-only, container-scoped SAS is preset in
the env (`STUDIO_BLOB_BASE_URL` + `STUDIO_BLOB_READ_SAS`). Build the link by joining:

```bash
# after copying e.g. 2026-06-22/Smith_pim-ready.zip to the container:
echo "$STUDIO_BLOB_BASE_URL/2026-06-22/Smith_pim-ready.zip?$STUDIO_BLOB_READ_SAS"
```

Post that URL in your reply. The recipient clicks it to download the ZIP directly from
blob — no channel, no SharePoint, no extra connector. (The SAS is read-only and
expires; if a link 403s, the SAS needs rotating — report it.) URL-encode the path
segment if a filename contains spaces.

A Power Automate / Logic App flow watching `studio-outbox` can also post links to a
**channel** automatically (see `docs/power-automate-studio-outbox.md`); the link above
is what you use for direct/DM delivery.

## Rules

- This is the agent's **own** storage, so pushing here is allowed in **both dry-run and
  live** — it's how the delivery loop is tested. (To keep dry-run packages off a
  production Teams channel, point the Power Automate flow at a test channel while
  testing.) Tag dry-run manifests with "(dry-run)" so watchers can tell.
- Push only finished PIM-ready artifacts (ZIP, manifest, contact sheet) — keep raw
  source images out of blob.
