# Workflow Loadouts

Load this file every Cowork Task alongside `operating-rules.md`. Identify the workflow type, then load only the additional files listed for that loadout. Do not load files outside the loadout unless the work explicitly requires them.

**Terminology note:** "Cowork Task" is the runtime unit (a single conversation). "Workflow type" is the category of work being routed (Daily Report Refresh, Vendor Image Sourcing, etc.). A "workflow loadout" is the file bundle loaded for a workflow type. This file (`workflow-loadouts.md`) was previously named `task-loadouts.md`; the rename was made in v11.0-review-r3 to remove the ambiguity between the two meanings of "task."

**Baseline (implicit in every loadout — not repeated below):**
- `context/evo-system-guardrails.md` — Tier 1/2/3 live-system safety rules
- `context/operating-rules.md`
- `context/workflow-loadouts.md`
- The most recent file in `context/handoffs/` (loaded as part of the task startup procedure)

Each loadout below lists only the **additional** files to load on top of this baseline.

**Two-phase loading rule:**
- **Phase 1 (startup):** Load all baseline + loadout files. This is the full initial load — do it before the context check and before any work begins.
- **Phase 2 (on demand):** After the context check, do not pre-load anything else speculatively. Load additional files only when the specific step that needs them is actually starting.

**Workflow maturity stages and current stage assignments** are in `operating-rules.md` (Workflow maturity stages section). Check the stage of any workflow before running it.

**`CHANGELOG.md` is not part of any loadout.** Load it only for versioning/release work — preparing a release zip, reviewing release history, or summarizing changes between versions. Do not load during routine task startup or normal workflow execution.

---

## Loadout: Daily Report Refresh

**Load (in addition to baseline):**
- `context/references.md`
- `context/cowork-tool-limitations.md`
- `context/workflows/01-daily-report-refresh.md`
- `context/troubleshooting.md`

**Do not load:**
- Any other workflow files
- standards/, projects/, planning/
- HTML gauge unless task becomes long (context check is always fine)

**Adaptive thinking:** Off — mechanical execution.

**Burn check:** Skip unless task is already long.

**Handoff trigger:** End of run, or if scripts error repeatedly.

---

## Loadout: Vendor Image Sourcing

**Load (in addition to baseline):**
- `context/references.md`
- `context/cowork-tool-limitations.md`
- `context/workflows/02-vendor-image-sourcing-and-skuing.md`
- `context/standards/image-standards.md`
- `context/standards/vendor-dam-guide.md`
- `context/troubleshooting.md`

**Do not load:**
- Daily report workflow, PIM workflow
- planning/, projects/
- HTML gauge unless task becomes long (context check is always fine)

**Adaptive thinking:** Off — defined workflow.

**Burn check:** Run compact check before bulk image downloads or DAM access sequences.

**Handoff trigger:** End of brand/PO, or context window approaching 75%.

---

## Loadout: PIM Upload and Image Ordering

**Load (in addition to baseline):**
- `context/references.md`
- `context/cowork-tool-limitations.md`
- `context/workflows/04-pim-upload-and-image-ordering.md`
- `context/troubleshooting.md`

**Do not load by default:**
- `context/standards/image-standards.md` — load on demand only if images were not processed through the editing step (e.g. sourced and uploaded directly). By upload time, all images should already be 1500×1500 JPGs with white backgrounds — standards were evaluated during editing.
- `context/standards/pim-category-ordering.md` — load on demand only if image files are not already sequenced via numeric filename prefixes. If the editing step was completed correctly, file order is already determined and this guide is not needed. Required if uploading files that were not pre-sequenced.

**Do not load:**
- Other workflow files, planning/, projects/
- HTML gauge unless task becomes long (context check is always fine)

**Adaptive thinking:** Off — defined workflow. On only if unexpected PIM behavior requires diagnosis.

**Burn check:** Skip unless many SKUs in scope.

**Handoff trigger:** End of upload batch, or before starting a new brand.

---

## Loadout: PIM Photo Guide Intake / Standards Update

**Load (in addition to baseline):**
- `context/cowork-tool-limitations.md` — required; standards intake often surfaces new tool behavior
- `context/standards/image-standards.md`
- `context/standards/pim-category-ordering.md`
- Relevant handoff if continuing prior task

**Do not load:**
- All workflow files, references.md (unless needed for cross-check)
- planning/, projects/ unless specifically needed

**Adaptive thinking:** Off for extraction and formatting. On only for standards reconciliation with conflicts.

**Burn check:** Required before starting. Source document digestion is high-burn — confirm approach (text-only vs. screenshots) before proceeding. Estimate: reading 100+ slides text-only = ~10–15k tokens.

**Handoff trigger:** After each major section, or at 60% context window.

---

## Loadout: Image Editing and Processing

**Load (in addition to baseline):**
- `context/references.md`
- `context/cowork-tool-limitations.md`
- `context/workflows/03-image-editing-and-processing.md`
- `context/standards/image-standards.md`
- `context/standards/pim-category-ordering.md`
- `context/troubleshooting.md`

**Do not load:**
- Other workflow files, planning/, projects/
- HTML gauge unless task becomes long

**Adaptive thinking:** Off for standard processing. On only for unexpected image-quality failures or workflow redesign.

**Burn check:** Flag before reading many full-resolution source images or generating large thumbnail sets.

**Handoff trigger:** End of batch, before PIM upload, or if image order/quality decisions remain unresolved.

---

## Loadout: Playbook Update / Versioning

**Load (in addition to baseline):**
- `context/doc-update-index.md` — always required; identifies all files affected by any documentation change
- `context/cowork-tool-limitations.md` — required; updates to limitations are a core output of this task
- Specific files being edited only
- Relevant handoff or planning note

**Do not load:**
- Full playbook — load files individually as needed
- diagnostics/ unless requested

**Adaptive thinking:** On for structural design decisions. Off for mechanical file edits.

**Burn check:** Required. Playbook updates are high-burn — multiple file reads and edits. Estimate cost before loading files.

**Handoff trigger:** Before zipping. Never zip mid-task speculatively.

---

## Loadout: PDP-PLP Audit

**Status:** In development / Claude Code only. The `context/projects/pdp-plp-auditor/` files are source-only and are not present in deployed Cowork packages. Do not attempt to run this loadout from a deployed operating copy — it will fail to load. When the auditor is promoted out of Alpha and the project files are added to the deployable, this status note will be removed.

**Load (in addition to baseline):**
- `context/references.md`
- `context/cowork-tool-limitations.md` — required; Alpha-stage workflow; new limitations expected during testing
- `context/standards/image-standards.md`
- `context/standards/pim-category-ordering.md`
- `context/projects/pdp-plp-auditor/overview.md` *(source-only)*
- `context/projects/pdp-plp-auditor/results-template.md` *(source-only)*

**Do not load:**
- Workflow files (except PIM upload if re-ordering images)
- planning/, handoffs/ (unless continuing)

**Adaptive thinking:** On for audit strategy design. Off for mechanical audit execution.

**Burn check:** Required before browser automation sequences. Screenshots are expensive.

**Handoff trigger:** After each audit batch, or at 60% context window.

---

## Loadout: IT Request / Bug Report

**Load (in addition to baseline):**
- `context/templates.md`
- Relevant workflow file if the bug is workflow-specific
- `context/troubleshooting.md` if diagnosing a known issue

**Do not load:**
- standards/, projects/, planning/
- HTML gauge (context check needs no file load)

**Adaptive thinking:** Off for templated drafting. On if diagnosing a novel system failure.

**Burn check:** Skip.

**Handoff trigger:** Not usually needed — short task.

---

## Default loadout (workflow type unknown)

If the workflow type is unclear at task start, load only the baseline (operating-rules.md, workflow-loadouts.md, most recent handoff).

Then ask the evo team member what the task goal is before loading anything else. `context/evo-general-context.md` is source-only orientation material and is not present in deployed packages — if a Cowork user asks for evo background, summarize from operating-rules.md and the workflow files rather than attempting to load a file that is not there.
