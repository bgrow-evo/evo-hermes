# Playbook Versioning Procedure

Standalone reference for producing a new version of the evo Photo Workflow — Cowork Playbook. Loaded on demand when versioning work is in progress — not part of any standard workflow loadout.

---

## Folder roles (read this first)

```
<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/   ← editable project source
<COWORK_ROOT>/photo-workflow-cowork-playbook/           ← deployed operating copy (project-specific subfolder)
<EXPORT_ROOT>/photo-workflow-cowork-playbook/           ← review/final ZIPs
```

Where:
- `<PROJECT_SOURCE_ROOT>` — local editable project folder (e.g. `~/Documents/Claude/Code`)
- `<COWORK_ROOT>` — parent Cowork folder (e.g. `~/Documents/Claude/Cowork`); operating copies for each project live in project-specific subfolders under this root
- `<EXPORT_ROOT>` — external ZIP output folder (e.g. `~/Documents/Claude/Code/_exports`)

The operating copy (`<COWORK_ROOT>/photo-workflow-cowork-playbook/`) is the runtime target. `<COWORK_ROOT>` itself may hold multiple project subfolders.

**Edits must be made in the project source.** The ZIP is built from source. The operating copy is what the runtime sees after a deploy and may be wiped at any time. Do not edit the operating copy expecting changes to persist.

### Preflight (every version task)

Before any edit or export, confirm:

1. The current working directory.
2. Whether the target is **project source**, **operating copy**, or **export artifact / temp extraction**.
3. Do not proceed if the role is ambiguous. Ask.

The marker file `PROJECT_SOURCE.md` exists only at the project source root. `OPERATING_COPY.md` ships in the ZIP and is present in the deployed operating copy. It does not persist in the project source between version builds — if you see one in the project source, it is either a leftover from a previous build (delete it) or the current build is in progress. If neither marker is present, stop and verify with the maintainer.

---

## Deployment lifecycle

The Playbook moves through a fixed sequence — source → export → verify → deploy → validate. Skipping or reordering steps causes drift between source, exported ZIP, and runtime.

1. **Edit project source** — `<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/`. All durable edits land here.
2. **Build ZIP** — built from source only. May be a review ZIP (saved to `<EXPORT_ROOT>/photo-workflow-cowork-playbook/reviews/`) or a final ZIP (saved to `<EXPORT_ROOT>/photo-workflow-cowork-playbook/finals/`). Both kinds go through the same deploy-and-validate cycle below.
3. **Verify ZIP** — structure, exclusions, version labels, no `context/handoffs/` or `work/` contents. Detail in step 9 of the procedure below.
4. **Deploy ZIP to operating copy** — extract into `<COWORK_ROOT>/photo-workflow-cowork-playbook/`. Update `OPERATING_COPY.md` with the deployed version details (see step 10 for the content template).
5. **Verify operating copy** — correct version stamps, expected files present, `OPERATING_COPY.md` updated and in place.
6. **Run Cowork validation from the operating copy** — not from the ZIP, not from a temp extraction. Cowork operates on the operating copy, so that is what must be validated. This step applies equally after deploying a review ZIP and after deploying a final ZIP.

**Normal review-and-finalize flow:** source edit → review ZIP → deploy review ZIP to `<COWORK_ROOT>/photo-workflow-cowork-playbook/` → validate → iterate if needed → final ZIP → deploy final ZIP (optional, if operating copy should reflect the released version).

If validation surfaces issues, fix them in **project source** (`<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/`), then rebuild and redeploy. Do not patch the operating copy in place — those edits will be lost on the next deploy.

---

## How versioning works

All durable edits are made **in-place** to files in the project source using Claude's file tools (Read/Write/Edit). The ZIP is an archive snapshot built from source — not a source to deploy from. Deploy = extract the ZIP into the operating copy folder.

Generated zips are stored in an external export root that sits **outside** both Cowork projects:

- Final zips: `_exports/photo-workflow-cowork-playbook/finals/`
- Review iterations: `_exports/photo-workflow-cowork-playbook/reviews/`

Zips do not live inside the Playbook itself. The Playbook's `work/` folder is reserved as the human working folder.

---

## Step-by-step procedure

1. **Edit in place.** Make all changes directly to files in `context/` (and `CLAUDE.md` / `docs/README.md` / `docs/claude-context-management.md` if needed) using the file tools.

2. **Do not zip mid-task.** Since all edits are made live to the actual markdown files, the zip is not needed until the end of the task — after all remaining updates and the handoff have been written. Never zip speculatively or before the task is truly wrapping up.

3. **Version increment cadence.** Each task that produces edits gets a minor version increment (e.g. v9.0 → v9.1). A major increment (e.g. v9.x → v10.0) is reserved for substantial changes — new workflows, significant structural redesigns, or major rule overhauls. The evo team member confirms the version number before zipping.

4. **Update version numbers.** Before zipping, update the version string in all five locations:
   - `CLAUDE.md` (header line)
   - `docs/README.md` (header line)
   - `context/operating-rules.md` (Current version section at the bottom)
   - `PROJECT_SOURCE.md` (Version line)
   - `CHANGELOG.md` (add a new version entry — Added / Changed / Versioning notes / Intentionally unchanged)

4b. **Create `OPERATING_COPY.md` for this release.** Before zipping, create `OPERATING_COPY.md` in the project source root using the template in step 10. Fill in the version, package type, date, and zip filename. This file will be included in the ZIP — when the ZIP is deployed, the marker is already present. After the ZIP is built and verified, delete `OPERATING_COPY.md` from the project source. It must not persist in the source between versions.

5. **Confirm completeness before zipping — then check again.** All edits for the version must be done, and the evo team member must confirm the version number. Before zipping, ask explicitly: "Any final changes before I zip?" then wait. There is almost always one more change. Double or triple check before producing the zip. Rezipping within the same task wastes context tokens — zip once at the very end.

6. **Write the handoff before zipping (final zips only).** The handoff is the local continuity narrative for the next task in this Playbook. Follow the handoff procedure in `context/templates.md`:
   - Close any browser tabs opened during this task
   - Run the context check (two-table markdown) and record numbers
   - Capture closing usage numbers from Settings → Usage
   - Write the handoff to `context/handoffs/YYYY-MM-DD_NN_topic-handoff.md`

   The handoff stays **local** in `context/handoffs/` and is loaded at the start of the next task. It is **not** included in the final zip — see the export rules above. The zip will show `context/handoffs/` as an empty directory entry only.

   **Review iterations do not get a handoff.** Handoffs are task-end artifacts. Writing one mid-iteration produces non-final state in `context/handoffs/` and clutters the continuity record. Only at task end (alongside a final zip) is a handoff written.

7. **Zip the current state.** Create:
   ```
   evo_photo_workflow_cowork_playbook_YYYY-MM-DD_vX.Y[_OptionalText].zip
   ```
   Example: `evo_photo_workflow_cowork_playbook_2026-04-30_v9.0.zip`

   **ZIP contents:** `CLAUDE.md`, `OPERATING_COPY.md` (deployment marker — see below), the `context/` folder (with `context/handoffs/**` excluded — see below), the full `docs/` folder, an **intentionally empty `work/` directory entry**, and an **intentionally empty `context/handoffs/` directory entry** (so the expected project structure is visible in the export).

   **Include — deployment marker:**
   - `OPERATING_COPY.md` — always included in the ZIP, no exceptions. Created in the project source at step 4b with the version details filled in, included when the ZIP is built, and then deleted from the project source after the ZIP is verified (it is a deployment artifact, not a source file — it must not persist in the source between versions).

   **Include as empty directories only:**
   - `work/` — present in the ZIP as a directory entry, no contents. Note: some zip tools silently omit empty directories. Always verify with `unzip -l` after building (step 9). If the tooling cannot preserve a true empty directory, add a `.gitkeep` placeholder.
   - `context/handoffs/` — present in the ZIP as a directory entry, no contents
   - If the ZIP tooling cannot preserve an empty directory, add a single `.gitkeep` placeholder inside as a technical fallback. Prefer a true empty directory entry.

   **Exclude from ZIP:**
   - `CHANGELOG.md` — source-only; not included in shared or deployed packages
   - `PROJECT_SOURCE.md` — source-only marker; never included in shared packages
   - `context/evo-general-context.md` — source-only orientation/onboarding material; not loaded by any workflow loadout
   - `context/planning/` (entire folder) — source-only backlog and decision logs; maintainer surface area, no runtime use
   - `context/projects/` (entire folder) — source-only in-development projects (e.g. `pdp-plp-auditor/`); loadouts that reference these are marked Code-only in `context/workflow-loadouts.md` until promoted
   - `context/prompts/start-it-automation-planning.md` — source-only task starter; IT/automation planning happens on the Code side, not in Cowork
   - `.DS_Store` and `.fuse_hidden*` files
   - All contents of `work/` (the directory entry is included, contents are not)
   - All contents of `context/handoffs/` — completed handoff records are local continuity files, not shared package content. Local handoff files in the project source stay on disk; only the ZIP excludes them.
   - `_exports/` (external export root — sits outside the project anyway, but never include if accidentally referenced)
   - Any other generated ZIP files

   Build the zip via bash to `/tmp/` first, then copy to the appropriate `_exports/` destination (some connected/mounted folders restrict direct zip creation; building in `/tmp/` avoids this).

   The version number (`vX.Y`) cross-references the version in `CLAUDE.md` and is the unique identifier — no sequence counter needed. `_OptionalText` is optional — use only if multiple zips are produced on the same date at the same version (e.g. `_hotfix`).

8. **Save the zip to the correct external location.**

   **Final, released versioned zips:**
   ```
   _exports/photo-workflow-cowork-playbook/finals/
   ```

   **Interim review iterations** (zips produced for external review, internal critique, or any non-final snapshot): use the `_OptionalText` field with a `_review-rN` suffix and save to:
   ```
   _exports/photo-workflow-cowork-playbook/reviews/
   ```

   The version number stays the same throughout (e.g. `v11.0`); only the suffix changes per round:
   ```
   evo_..._2026-05-08_v11.0_review-r1.zip   ← first review iteration
   evo_..._2026-05-08_v11.0_review-r2.zip   ← second review iteration
   ...
   evo_..._2026-05-08_v11.0.zip             ← final, no suffix, in finals/
   ```

   **The trigger for going final is the evo team member explicitly saying so** (e.g., "this is final," "produce the final zip"). Do not promote a review zip to a final zip on your own initiative — even if the most recent review round looks complete. This matches the version-confirmation rule in step 3: the evo team member confirms the version is final before the no-suffix zip is produced.

   When the version is declared final, produce the no-suffix zip in `_exports/photo-workflow-cowork-playbook/finals/` and optionally delete the corresponding entries in `_exports/photo-workflow-cowork-playbook/reviews/` for that version. Final zips are immutable; review zips are disposable.

9. **Verify the zip itself.** Confirm the zip file exists at the export path and has a reasonable size. Spot-check one or two files inside the zip with `unzip -p` if needed. **Verify against intentional deletions** by running `unzip -l <zip> | grep <expected-deletions>` to confirm intentionally deleted files are not present. **Verify the zip excludes `_exports/`** — it should not appear in the listing. **Verify `work/` and `context/handoffs/` are each included as empty directory entries only** — `unzip -l` should show each folder as a directory but no `work/<file>` or `context/handoffs/<file>` entries. **Verify no completed handoff `.md` files are inside the zip.** **Verify `work/` is present as an empty directory entry** — `unzip -l <zip> | grep "work/"` should show the directory entry. If it is missing, the zip build command did not correctly include the empty directory — rebuild using the `/tmp/` approach with explicit empty directory inclusion.

10. **Deploy ZIP to the operating copy.** After the ZIP is verified, extract it into `<COWORK_ROOT>/photo-workflow-cowork-playbook/` so the runtime sees the new version. Steps:
    - If the operating copy folder has stale contents, delete and recreate it rather than relying on shell glob expansion: `rm -rf "$OPCOPY" && mkdir -p "$OPCOPY"`. Patterns like `rm -rf "$OPCOPY"/* "$OPCOPY"/.[!.]*` can fail silently under zsh (which refuses commands where any glob matches nothing). After wiping, `ls -la "$OPCOPY"` should show only `.` and `..` before extracting. The operating copy is disposable; the new `OPERATING_COPY.md` arrives inside the ZIP.
    - Extract the ZIP into the operating copy root.
    - Verify that `OPERATING_COPY.md` is present (it ships in the ZIP). Confirm its contents reflect the correct version, package type, and deploy date. Update the "Deployed on" date if needed. The template below is the canonical content shape — it is created in project source at step 4b, included in the ZIP, and lands in the operating copy at extraction.

      ```markdown
      # Operating Copy

      This folder is the deployed Cowork operating copy for the Photo Workflow Cowork Playbook.

      It is not the editable project source. Do not make durable package edits here.

      Durable edits belong in `<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/`.

      ## Currently deployed package

      Project: Photo Workflow Cowork Playbook
      Deployed version: [version, e.g. v11.3 or v11.3-review-r1]
      Package type: [review / final]
      Source package: [zip filename]
      Deployed from: `<EXPORT_ROOT>/photo-workflow-cowork-playbook/[reviews or finals]/`
      Deployed to: `<COWORK_ROOT>/photo-workflow-cowork-playbook/`
      Deployed on: YYYY-MM-DD

      ## Validation rule

      Cowork-runtime validation should be run from this operating copy, whether the deployed package is a review candidate or a final package.
      ```

    - Verify the operating copy: version stamps in `CLAUDE.md` / `docs/README.md` / `context/operating-rules.md` match the deployed version, expected files are present, `OPERATING_COPY.md` is present and updated, no `PROJECT_SOURCE.md` (it is source-only and excluded from ZIPs). **Also confirm every path excluded from the ZIP per step 7 is absent.** If any appear, the wipe failed silently and you're seeing a merge — re-wipe and re-extract.

    Do not edit the operating copy as if it were canonical. Any fix discovered during validation must be applied back to project source, then rebuilt and redeployed.

11. **Cowork runtime validation pass.** After deployment, open a fresh Cowork task and run `context/prompts/start-cowork-validation.md` against the **deployed operating copy** (`<COWORK_ROOT>/photo-workflow-cowork-playbook/`). This confirms that the deployed package actually runs cleanly in Cowork — the architectural rule that workflow stage promotions and version releases require a Cowork-environment test run. This step applies after deploying a review ZIP (to validate before declaring final) and after deploying a final ZIP (to confirm the release). Do not treat any version as shippable until this validation pass completes successfully. If issues are found, fix them at project source, rebuild, and redeploy. Update the per-version additions section of `start-cowork-validation.md` between releases to reflect what changed in the next version.

    **Warning.** Do not validate directly against the ZIP or a temp extraction. Cowork operates on the operating copy, so the operating copy is what must be validated. Validating a ZIP or temp extraction will pass while the operating copy can still be stale or wrong.

---

## Restoring from a zip

If the bash sandbox cannot overwrite files in the connected package folder via `unzip`, restoration must be done manually — extract the zip on your machine and copy the contents back to the project's root folder.

---

## Version history

The current zip in `_exports/photo-workflow-cowork-playbook/finals/` and the live `context/` folder should always reflect the same version. Once the evo team member confirms a version is complete, zip immediately — then do not continue editing unless starting a new version.
