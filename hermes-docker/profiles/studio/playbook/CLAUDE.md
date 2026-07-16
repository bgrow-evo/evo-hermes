# evo Photo Workflow — Cowork Playbook

Current version: v11.5 · Last updated: 2026-05-13

---

## Folder roles

The Playbook lives in three folder roles:

```
<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/   ← editable project source
<COWORK_ROOT>/photo-workflow-cowork-playbook/           ← deployed operating copy (project-specific subfolder)
<EXPORT_ROOT>/photo-workflow-cowork-playbook/           ← review/final ZIPs
```

Where `<PROJECT_SOURCE_ROOT>` is the local editable project folder, `<COWORK_ROOT>` is the parent Cowork folder (e.g. `~/Documents/Claude/Cowork`), and `<EXPORT_ROOT>` is the external ZIP output folder. The operating copy lives in a project-specific subfolder under `<COWORK_ROOT>`.

**Edits belong in project source.** The operating copy is a deployed runtime package and may be wiped on redeploy. Do not treat it as canonical.

Before any edit or export, confirm which folder role you are in:
1. `PROJECT_SOURCE.md` exists only at the project source root.
2. `OPERATING_COPY.md` ships in the ZIP and is present in the deployed operating copy. It does not persist in the project source between version builds — if you see one in the project source, it is either a leftover from a previous build (delete it) or the current build is in progress.
3. If neither marker is present, stop and verify before proceeding.

See `context/versioning.md` for the full deployment lifecycle.

---

## Architecture status

This playbook is **Cowork-runtime-first and Code-maintained**: Claude Code may be used to edit, refactor, version, and test the documentation package, but user-facing workflows must remain executable in Claude Cowork without relying on Code-only commands, hooks, permissions, or slash-command behavior.

- **Runtime target:** Claude Cowork (non-developer evo team members)
- **Maintenance environment:** Claude Code (edits made here must not introduce Cowork-incompatible dependencies)
- **Skills:** Experimental and stage-gated. Do not introduce Skill-based workflows into the user-facing package without Cowork validation at Production stage.
- **Validation rule:** Workflow stage promotions (Alpha → Beta, Beta → Production) require a Cowork-environment test run, not a Code-only run.
- **Cowork-runtime scaffolding** (e.g. context window gauge, usage estimates, model/Adaptive Thinking startup check guidance) must not be removed solely because Claude Code has native equivalents. Cowork users still need them.

---

## Startup

1. Confirm the Cowork folder is connected
2. Load `context/operating-rules.md` and `context/workflow-loadouts.md`
3. Follow the task startup procedure in `context/operating-rules.md`

Do not load `docs/README.md`. Use the context check (two-table markdown) by default — reserve the HTML gauge for when the evo team member explicitly types "gauge."

---

## Context loading policy

**Always load:**
- `context/evo-system-guardrails.md` — live-system safety guardrails (critical controls, operational reliability rules, and team preferences); applies to any task involving PIM, Shopify, DAM, SharePoint/Drive, vendor portals, reports, image assets, or bulk file operations
- `context/operating-rules.md`
- `context/workflow-loadouts.md`
- `context/doc-update-index.md` — whenever making any documentation correction; scan to identify all affected files before editing

**Load per workflow loadout only** (see `context/workflow-loadouts.md`):
- `context/references.md`
- `context/cowork-tool-limitations.md`
- `context/templates.md`
- `context/troubleshooting.md`
- `context/workflows/` — load the relevant workflow file only
- `context/standards/` — load only what the task requires

**Load at every task start:**
- `context/handoffs/` — load the most recent handoff file. Use bash (`ls`) to list — do not rely on Glob (see `cowork-tool-limitations.md`). Sort by filename and load only the last result. Also check for any other handoffs dated today. The handoffs folder is empty in a freshly deployed package — if so, no prior handoff is available; ask the evo team member for context.

**Load only when explicitly needed:**
- `context/diagnostics/` — context window gauge only; load when requested or at 75%+ fill
- `context/versioning.md` — only when producing a new version
- `context/doc-update-index.md` — whenever making any documentation correction; scan to identify all affected files before editing

**Do not load by default:**
- `docs/` — human-only reference; do not load unless explicitly reviewing documentation

**Source-only — not present in deployed packages:**
- `context/evo-general-context.md` — orientation/onboarding material; the maintainer keeps it source-side
- `context/planning/` — backlog and decision logs; source-side maintainer surface only
- `context/projects/` — in-development projects (e.g. `pdp-plp-auditor/`) kept source-side until promoted
- `CHANGELOG.md` — source-only release history; load only during Code-side release/maintenance work
- `PROJECT_SOURCE.md` — source-root marker only; never in deployed packages

---

## Folder structure

See `docs/README.md` for the canonical folder structure diagram.
