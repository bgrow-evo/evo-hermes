---
name: studio-daily-pipeline
description: "Run the evo photo workflow end-to-end, unattended: refresh the daily report, source vendor images, process them to PIM spec, and package a PIM-ready ZIP to the outbox for a human to upload. Invoked by the studio profile's daily cron job."
version: 1.0.0
author: evo studio
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [photo-workflow, evo, pipeline, cron, daily, orchestration]
    related_skills: [evo-image-processing]
---

# Studio Daily Pipeline

You are running the evo photo workflow unattended, on a schedule. Your goal: get as
far as possible toward PIM-ready output without a human, and hand off a ZIP for the
human-only steps. Never fabricate the result of a step you could not actually do.

## Dry-run mode (CHECK THIS FIRST, every run)

Before anything else, determine the mode:

```bash
test -f /opt/data/profiles/studio/DRY_RUN && echo DRY_RUN_ON || echo DRY_RUN_OFF
```

Also treat the run as dry-run if the trigger message contains `DRY RUN` /
`--dry-run` (case-insensitive). State the resolved mode in your first line of output
and in the manifest.

**When DRY-RUN is ON, you must not write back to ANY external source.** Specifically
FORBIDDEN:
- Google Sheets: do **not** run the 📸 Images-menu refresh functions, do **not**
  paste the Sheet ID into `CONFIG!B2`, do **not** change sharing/permissions, do
  **not** edit any cell. Reading the report (incl. the read-only `gviz` CSV
  endpoint) is allowed.
- Fileserver / SharePoint / DAM: no uploads, no moves, no "Post Production to Edit"
  drops, no edits to vendor portals. Browsing and **downloading** source images to
  the local work dir is allowed (that is local, not a write-back).
- Teams: no posts, no messages, no compose-box typing.
- PIM: never (already out of scope).

**ALLOWED in dry-run**: download source images, process them, write to `work/` and the
outbox ZIP + MANIFEST, **and push the package to your own blob storage** (`agent-blob`)
— that is your storage, used to test the delivery loop, not an evo shared system. The
manifest must list, under "Would have written (skipped — dry-run):", every *external*
write you skipped (Sheets, fileserver, Teams) and what it would have done. Tag the
manifest title with "(dry-run)" so anything watching the blob can tell.

If any step's only path forward requires an external write, **skip it and record it**
— do not find a workaround.

Default safety: if you cannot determine the mode for any reason, assume DRY-RUN ON.

## Ground rules (read first, every run)

Load, in order, from the bundled playbook at `./playbook/` (relative to this profile;
absolute: `/opt/data/profiles/studio/playbook/`):

1. `context/evo-system-guardrails.md` — live-system safety. **Non-negotiable.**
2. `context/operating-rules.md`
3. `context/workflow-loadouts.md`

Then load each workflow file only when you reach that stage (per the loadouts).

- You touch real vendor portals, fileservers, Google Sheets, and Teams. Obey every
  Tier 1/2/3 guardrail. When unsure whether an action is safe/reversible, **stop and
  record it as a blocker** instead of proceeding.
- You will hit human-only gates (VPN file import, OAuth consent, image-order
  confirmation, PIM upload). Do not guess, fake, or click Post/Submit for a human.
  Record the blocker and continue with whatever you *can* do.
- Be token-aware: inspect images via ~400px thumbnails (Read the thumb, not the
  full-res source). Run the context check periodically.

## Stages

### 1. Daily Report Refresh  (`context/workflows/01-daily-report-refresh.md`)
Refresh the missing-images report if it has not run today. The xlsx import needs VPN
+ a human (cross-origin iframe) and OAuth is one-time — if you cannot reach the file,
**record the blocker** and fall back: open the existing report and scan for unclaimed
NEW rows to drive the rest of the run. Do not post to Teams on a human's behalf.
**DRY-RUN:** skip the refresh entirely (it writes to the Sheet). Only *read* the
existing report (gviz CSV) to find NEW rows; log the refresh as a skipped write.

### 2. Vendor Image Sourcing & SKUing  (`context/workflows/02-...md`)
For unclaimed NEW rows, source images from the vendor DAMs (creds in this profile's
`.env`; the Merch Sheet is the live source of truth — passwords drift). Lay them out
in the standard folder structure under the day's work dir:
`work/<YYYY-MM-DD>/<Brand>/Original/EB-XXXXXX-XXXX/`. Skip a brand/SKU and record a
blocker if a DAM login fails — do not retry destructively.

### 3. Image Editing & Processing  (`context/workflows/03-...md` + `evo-image-processing` skill)
- Check `context/standards/pim-category-ordering.md` for the category's image order.
- Generate thumbnails, inspect, decide shot types (baseline / on-model / lifestyle).
- Because image order needs human confirmation and this run is unattended, use the
  category rules to choose a **best-effort order** and clearly mark it
  "proposed, unconfirmed" in the manifest. Note any SKU where shot type was ambiguous.
- Run `evo-image-processing` (`process_images.py`) per SKU into
  `work/<date>/<Brand>/Output/EB-XXXXXX-XXXX/` with `--main` and `--order`.
- Route non-white/non-transparent main images to the "Complex main image clipping"
  manual path — package what's clean, flag the rest. **DRY-RUN:** do not upload the
  complex-clip batch to the fileserver; just list those SKUs as a skipped write.

### 4. Package for PIM  (replaces the PIM-upload workflow)
- **Write the manifest first** so it can be bundled into the ZIP:
  `/opt/data/outbox/studio/<YYYY-MM-DD>/MANIFEST.md` covering brands/SKUs packaged,
  image counts, proposed-vs-confirmed order, complex-clip SKUs deferred to Photoshop,
  and every blocker hit. End it with the explicit human action:
  **"Upload these ZIPs to PIM (Workflow #4)."**
- Then run `evo-image-processing` (`package_zip.py`) per brand to build
  `/opt/data/outbox/studio/<YYYY-MM-DD>/<Brand>_pim-ready.zip`, passing
  `--manifest /opt/data/outbox/studio/<YYYY-MM-DD>/MANIFEST.md` so the manifest is
  bundled at the zip root alongside the SKU image folders.
- **Do not upload to PIM yourself.** Packaging is the end of your job.

## Final output / delivery to chat

The Teams bot can send **text and images only — it cannot attach a `.zip`** (Bot
Framework adapter limit). So deliver, in this order:

1. **Post the MANIFEST inline** — paste the full body of
   `/opt/data/outbox/studio/<date>/MANIFEST.md` as the chat message (it is text). Lead
   with what is ready to upload, then the blocker list (what a human must still do).
2. **Attach a contact-sheet image** — images *are* supported, so give a visual preview
   of what you packaged. Build one per brand from the thumbnails with ImageMagick and
   send it as an image attachment:
   ```bash
   montage /opt/data/profiles/studio/work/<date>/<Brand>/Output/*/thumbs/*.jpg \
     -tile 4x -geometry 240x240+6+6 -title "<Brand> <date> (dry-run)" \
     /opt/data/outbox/studio/<date>/<Brand>_contact-sheet.png
   ```
   Then attach that PNG to the chat.
3. **Push the package to your blob storage AND post a download link** — use the
   `agent-blob` skill to `rclone copy` the day's ZIP + MANIFEST + contact sheet to
   `agent-blob:studio-outbox/<date>/` (do this in **both dry-run and live** — it's your
   own storage). Then build the read-only SAS download link for each ZIP
   (`$STUDIO_BLOB_BASE_URL/<date>/<Brand>_pim-ready.zip?$STUDIO_BLOB_READ_SAS`) and
   **include it in your chat reply** so the user can download directly — works in a DM
   or channel. (A Power Automate flow watching the container can also post links to a
   channel automatically.)
4. **Reference the ZIP path too** — state the local outbox path, e.g.
   `/opt/data/outbox/studio/<date>/<Brand>_pim-ready.zip` (host:
   `~/.hermes/outbox/studio/...`), and note the bot itself can't attach files.

Always state the resolved mode (DRY-RUN / LIVE) in the first line.
