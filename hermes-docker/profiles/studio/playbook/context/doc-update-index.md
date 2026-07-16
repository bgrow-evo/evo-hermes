# Documentation Update Index

Use this file to identify ALL files that need updating when a correction or new finding arises. For every topic, check all listed files — not just the primary one. Consult this index before committing any documentation change.

**How to use:** Find the topic that matches the correction. Update every file listed. If a topic isn't here, add it.

**How to maintain:** When a correction touches a file not listed under its topic, add it. When a new topic area emerges, add a new entry. **Every new file added to the playbook must be added to this index** — add it under all relevant topics when it is created.

---

## File system / directory inspection (Glob vs. bash)

**Primary:** `context/cowork-tool-limitations.md`
**Also check:** `context/troubleshooting.md` (failure modes)

Examples: Glob returning empty results for connected local folders, using bash find/ls instead

---

## Browser automation / Cowork tool behavior

**Primary:** `context/cowork-tool-limitations.md`
**Also check:** `context/operating-rules.md` (standing rules), `context/troubleshooting.md` (failure modes), relevant workflow file if the behavior affects a specific step

Examples: tab management, file deletion, dialog access, download methods, relay server, CORS, permission prompts

---

## Browser tab management

**Primary:** `context/cowork-tool-limitations.md`
**Also check:** `context/operating-rules.md` (standing rules), `context/workflows/02-vendor-image-sourcing-and-skuing.md`, `context/workflows/04-pim-upload-and-image-ordering.md`

---

## File deletion

**Primary:** `context/cowork-tool-limitations.md`
**Also check:** `context/operating-rules.md` (standing rules), `context/workflows/02-vendor-image-sourcing-and-skuing.md`, `context/workflows/04-pim-upload-and-image-ordering.md`

---

## Folder setup / Editing folder connection

**Primary:** `context/workflows/02-vendor-image-sourcing-and-skuing.md`, `context/workflows/03-image-editing-and-processing.md`
**Also check:** `context/evo-general-context.md` *(source-only)* (working folder structure), `context/cowork-tool-limitations.md` (if tool behavior is involved)

---

## Daily Report — ON HAND tab

**Primary:** `context/references.md`
**Also check:** `context/workflows/02-vendor-image-sourcing-and-skuing.md` (claiming/status steps), `context/troubleshooting.md` (known failure modes)

---

## Daily Report — ON ORDER tab

**Primary:** `context/references.md`
**Also check:** `context/workflows/02-vendor-image-sourcing-and-skuing.md` (claiming/notes convention)

---

## Daily Report — general / scripts / commands

**Primary:** `context/workflows/01-daily-report-refresh.md`
**Also check:** `context/references.md` (column maps), `context/troubleshooting.md` (known failure modes)

---

## PO Tracker

**Primary:** `context/references.md`
**Also check:** `context/workflows/02-vendor-image-sourcing-and-skuing.md` (claiming/status steps)

---

## SKU format / EB-SKU naming

**Primary:** `context/references.md`
**Also check:** `context/workflows/02-vendor-image-sourcing-and-skuing.md`, `context/workflows/04-pim-upload-and-image-ordering.md`

---

## File naming (images)

**Primary:** `context/references.md`
**Also check:** `context/standards/image-standards.md`

---

## Product photo taxonomy / shot type naming and sequence standards

**Primary:** `context/standards/product-photo-taxonomy.md` *(planned — not yet created; see backlog)*
**Also check:** `context/standards/pim-category-ordering.md` (category-specific ordering rules), `context/workflows/03-image-editing-and-processing.md` (file naming step)

Examples: shot type definitions (baseline, on-model-back, detail), sequencing rules, bag exception, zero-padding convention

---

## Image standards (white background, resolution, crop rules)

**Primary:** `context/standards/image-standards.md`
**Also check:** `context/workflows/03-image-editing-and-processing.md` (summary), `context/workflows/04-pim-upload-and-image-ordering.md` (checklist)

---

## PIM image ordering / category rules

**Primary:** `context/standards/pim-category-ordering.md`
**Also check:** `context/workflows/04-pim-upload-and-image-ordering.md` (checklist and upload steps), `context/workflows/03-image-editing-and-processing.md` (image order during file naming/renaming step)

---

## PIM upload behavior / quirks

**Primary:** `context/workflows/04-pim-upload-and-image-ordering.md`
**Also check:** `context/troubleshooting.md` (known failure modes), `context/references.md` (system URLs)

---

## PIM system access / URLs

**Primary:** `context/references.md`
**Also check:** `context/operating-rules.md` (high-risk areas), `context/workflows/04-pim-upload-and-image-ordering.md`

---

## Vendor DAM behavior (login, search, download)

**Primary:** `context/standards/vendor-dam-guide.md`
**Also check:** `context/cowork-tool-limitations.md` (if tool limitation is involved), `context/troubleshooting.md` (failure modes), `context/references.md` (if URL or credential changes)

---

## Vendor image sourcing workflow steps

**Primary:** `context/workflows/02-vendor-image-sourcing-and-skuing.md`
**Also check:** `context/standards/vendor-dam-guide.md` (vendor-specific), `context/standards/image-standards.md` (quality rules), `context/troubleshooting.md` (failure modes)

---

## Image editing / Photoshop processing

**Primary:** `context/workflows/03-image-editing-and-processing.md`
**Also check:** `context/standards/image-standards.md`

---

## Intermediate file cleanup (zips, source files)

**Primary:** `context/workflows/04-pim-upload-and-image-ordering.md`
**Also check:** `context/workflows/02-vendor-image-sourcing-and-skuing.md` (if sourcing-stage cleanup)

---

## Playbook versioning / zip naming

**Primary:** `context/versioning.md`
**Also check:** `context/operating-rules.md` (pointer and version number), `CLAUDE.md` (version number), `docs/README.md` (version number), `PROJECT_SOURCE.md` (version number), `CHANGELOG.md` (version-by-version history — source-only, not included in shared/deployed packages), `docs/claude-context-management.md` (plan notes if changed)

---

## Handoff / report naming and format

**Primary:** `context/templates.md`
**Also check:** `context/operating-rules.md` (pointer and handoff rule), `CLAUDE.md` (file rules section)

---

## Context check / gauge

**Primary:** `context/diagnostics/context-window-gauge.md`
**Also check:** `context/operating-rules.md` (standing rule on context check usage)

---

## Task startup procedure

**Primary:** `context/operating-rules.md`
**Also check:** `CLAUDE.md` (startup section), `context/workflow-loadouts.md` (loadout-specific steps), `docs/README.md` (human-facing startup guidance), `docs/claude-context-management.md` (task discipline guidance)

---

## Workflow loadouts (what to load per workflow type)

**Primary:** `context/workflow-loadouts.md`
**Also check:** `CLAUDE.md` (context loading policy), `context/operating-rules.md` (Workflow maturity stages section — referenced from each loadout)

---

## Workflow maturity stages

**Primary:** `context/operating-rules.md` (Workflow maturity stages section)
**Also check:** `context/workflow-loadouts.md` (cross-references stages but does not define them); `CLAUDE.md` (Architecture status — stage promotion rule)

Examples: stage definitions (Production / Beta / Alpha / Backlog), current stage assignments per workflow, stage promotion rules (Cowork-environment validation required)

---

## Documentation feedback loop / doc updates

**Primary:** `context/prompts/start-doc-update.md`
**Also check:** `context/operating-rules.md` (Documentation feedback loop standing rule), `context/doc-update-index.md` (this file — referenced in the loop), `context/templates.md` (handoff section captures doc updates produced)

Examples: classifying takeaways, identifying target files, applying smallest-safe updates, preserving Cowork-runtime guidance, surfacing conflicts before reconciling

---

## Cowork runtime validation (post-version-zip)

**Primary:** `context/prompts/start-cowork-validation.md`
**Also check:** `context/versioning.md` (step 10 — when to run), `context/operating-rules.md` (workflow stage promotion rule), `CLAUDE.md` (Architecture status — validation rule)

Examples: standard checklist for every new version, version-specific additions per release, capturing findings as documentation feedback candidates

---

## Architecture status / Cowork-runtime vs Code-maintenance

**Primary:** `CLAUDE.md` (Architecture status section)
**Also check:** `docs/README.md` (Architecture status section), `context/diagnostics/context-window-gauge.md` (Runtime applicability header), `context/diagnostics/usage-estimates.md` (Runtime applicability header)

Examples: runtime-target rules, scaffolding-protection rules, Cowork-runtime vs Code-only feature distinction, Skills stage-gating

---

## evo system guardrails (Tier 1/2/3, risk levels, approval gates, rollback path, workflow metadata, Claude not final approval, bulk operations)

**Primary:** `context/evo-system-guardrails.md`
**Also check:** `context/operating-rules.md` (Photo-specific operating rules build on the guardrails), `CLAUDE.md` (always-load list and architecture status), `context/workflow-loadouts.md` (baseline includes guardrails), `docs/README.md` (Governance and safety summary)

Examples: Tier 1 critical system guardrails (no live-system writes without approval, no deletions without confirmation, no bulk ops without rollback path, read before write, identify exact target, stop on unexpected behavior, do not bypass approval gates, Claude is never final approval); Tier 2 operational reliability rules (high-burn pause, workflow loadouts, dedicated browser window, capture URLs, full-tree file search, bash-first discovery, handoffs, feedback loop); Tier 3 team/maintainer preferences (naming, output style, package conventions); risk levels (Low / Medium / High / Prohibited); required workflow metadata (Owner / Systems / Inputs / Outputs / Approval gate / Rollback path / Stage / Cowork-runtime requirements / Code-maintenance notes); approval inheritance is not allowed; categories where Claude is never the final approver (image accuracy, pricing, inventory, compliance, system-of-record changes)

---

## Live systems in scope (PIM / Shopify / DAM / SharePoint / reports / vendor portals / image assets / bulk file operations)

**Primary:** `context/evo-system-guardrails.md` (Scope of live evo systems section)
**Also check:** `context/operating-rules.md` (standing rules), `context/references.md` (system URLs), `context/cowork-tool-limitations.md` (system-specific behavior), `context/standards/vendor-dam-guide.md` (vendor DAMs), `context/workflows/` (per-workflow system specifics)

---

## Standing rules (bulk requests, deletions, PIM actions, etc.)

**Primary:** `context/operating-rules.md`
**Also check:** `context/evo-system-guardrails.md` (Tier 1 critical controls), Relevant workflow file if the rule applies to a specific step, `docs/README.md` (Key Rules summary)

---

## Troubleshooting entries

**Primary:** `context/troubleshooting.md`
**Also check:** Relevant workflow file if the failure mode affects a specific step; `context/cowork-tool-limitations.md` if it's a tool limitation

---

## IT request / bug report templates

**Primary:** `context/templates.md`
**Also check:** `context/workflow-loadouts.md` (IT Request loadout)

---

## Team roles / systems in scope

**Primary:** `context/evo-general-context.md` *(source-only — not in deployed packages)*
**Also check:** `context/operating-rules.md` (if scope or risk rules are affected)

---

## PDP/PLP audit

**Primary:** `context/projects/pdp-plp-auditor/overview.md` *(source-only — not in deployed packages)*
**Also check:** `context/projects/pdp-plp-auditor/results-template.md` *(source-only)*, `context/standards/image-standards.md`, `context/standards/pim-category-ordering.md`

---

## Go-live conditions

**Primary:** `context/operating-rules.md`
**Also check:** `context/workflows/04-pim-upload-and-image-ordering.md`

---

*Last updated: 2026-05-08*
