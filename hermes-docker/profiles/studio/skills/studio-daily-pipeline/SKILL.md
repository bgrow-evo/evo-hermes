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
  manual path — package what's clean, flag the rest.

### 4. Package for PIM  (replaces the PIM-upload workflow)
- Run `evo-image-processing` (`package_zip.py`) to build, per brand,
  `/opt/data/outbox/studio/<YYYY-MM-DD>/<Brand>_pim-ready.zip`.
- Write `/opt/data/outbox/studio/<YYYY-MM-DD>/MANIFEST.md` covering: brands/SKUs
  packaged, image counts, proposed-vs-confirmed order, complex-clip SKUs deferred to
  Photoshop, and every blocker hit. End with the explicit human action:
  **"Upload these ZIPs to PIM (Workflow #4)."**
- **Do not upload to PIM yourself.** Packaging is the end of your job.

## Final output (the cron delivers this)

A short summary: date, brands/SKUs packaged, ZIP paths in the outbox, and a bulleted
blocker list (what a human must still do). Lead with what is ready to upload.
