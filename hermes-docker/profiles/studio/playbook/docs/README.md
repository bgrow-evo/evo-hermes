# evo Photo Workflow — Cowork Playbook

**Human reference only. Claude does not load this file.**

Current version: v11.5
Last updated: 2026-05-13

---

## What this is

A modular Claude Cowork markdown playbook for evo Photo Team workflows, covering product photography, vendor image processing, post-production, PIM Product Image Manager, image standards, upload workflows, QA, troubleshooting, workflow loadouts, and task handoffs. Adjacent Digital Content context is included where it intersects Photo workflows; this package does not represent the full Digital Content Team operating model.

See CLAUDE.md for the context loading policy.

---

## Architecture status

This playbook is **Cowork-runtime-first and Code-maintained**: Claude Code may be used to edit, refactor, version, and test the documentation package, but user-facing workflows must remain executable in Claude Cowork without relying on Code-only commands, hooks, permissions, or slash-command behavior.

The intended runtime for evo team members is Claude Cowork. Claude Code may be used by maintainers to edit and version this package, but Code-only features (slash commands like `/context` and `/cost`, hooks, permissions configuration, mid-session model switching) are not assumed to be available to end users.

---

## Folder roles

```
<PROJECT_SOURCE_ROOT>/photo-workflow-cowork-playbook/   ← editable project source
<COWORK_ROOT>/photo-workflow-cowork-playbook/           ← deployed operating copy (project-specific subfolder)
<EXPORT_ROOT>/photo-workflow-cowork-playbook/           ← review/final ZIPs
```

Where `<PROJECT_SOURCE_ROOT>` is the local editable project folder, `<COWORK_ROOT>` is the parent Cowork folder (e.g. `~/Documents/Claude/Cowork`), and `<EXPORT_ROOT>` is the external ZIP output folder. The operating copy lives in a project-specific subfolder under `<COWORK_ROOT>`.

Durable documentation edits must be made in project source, then rebuilt and deployed. The operating copy is an extracted runtime package and may be wiped on redeploy — do not treat it as canonical.

Marker files: `PROJECT_SOURCE.md` at the project source root. `OPERATING_COPY.md` ships in the ZIP and is present in the deployed operating copy; it does not persist in the project source between version builds.

---

## Terminology

- **Cowork Task** — a Cowork runtime work unit (a single conversation, one context window). The Cowork UI lists prior conversations as tasks.
- **Session** — the rolling 5-hour usage window with its own timer. A session reset does not end the Cowork Task or clear the context window.
- **Workflow type** — a category of work being routed (Daily Report Refresh, Vendor Image Sourcing, PIM Upload, etc.). What a Cowork Task is *doing*.
- **Workflow loadout** — the file bundle loaded for a workflow type. Defined in `context/workflow-loadouts.md`.

Where the word "task" could be confused with the conversation-level meaning, prefer **Cowork Task** for the runtime unit, **workflow type** for the kind of work being routed, and **workflow loadout** for the file bundle.

---

## Before you start a Cowork task

### 1. Choose your model

Model selection is locked once a Cowork task starts and cannot be changed mid-task.

| Workflow type | Recommended model |
|---|---|
| Execution: Daily Report, PIM upload, vendor image sourcing | Claude Sonnet (faster, lower burn) |
| Design/planning: new workflows, architecture, playbook versioning | Claude Sonnet or Opus depending on complexity |
| Quick lookups or simple file edits | Claude Sonnet or Haiku |

*Model names and capabilities evolve. Check Anthropic's documentation if unsure.*

### 2. Choose Adaptive Thinking — on or off

Adaptive Thinking is also locked at task start.

**Turn OFF for:**
- Daily Report runs
- Vendor image sourcing following a defined workflow
- PIM upload and image ordering
- Any execution task with defined steps

**Turn ON for:**
- Designing a new workflow from scratch with competing tradeoffs
- Debugging an unexpected failure with no known fix
- Planning PDP-PLP auditor architecture
- Producing a new version of the playbook

**Why it matters:** Adaptive Thinking consumes significantly more tokens per turn without improving output quality on procedural work.

**At task start, Claude will ask you to confirm whether Adaptive Thinking is on or off, then tell you whether that matches the workflow type.** If it doesn't match, Claude will write a handoff and prompt you to start a new task with the correct setting — it will not proceed with the wrong setting. You may type "AT is on" or "AT is off" as shorthand in your opening prompt.

### 3. Set up your Cowork folder

In Claude Desktop (macOS), set the Cowork folder as your default/selected folder with "Always Allow." New tasks will start with it already connected.

If not already connected, Claude will request it by path. The Cowork package should live in a local user-controlled folder (OneDrive paths are deprecated for the package). Example: `/Users/[username]/Documents/Claude/Cowork`. The exact path may vary by user.

---

## Task starter prompts

**General task:**
```
Load CLAUDE.md. My task today is: [describe task]. AT is [on/off].
```

**Continuing from a prior task:**
```
Load CLAUDE.md. Continue from context/handoffs/[YYYY-MM-DD_NN_topic-handoff].md. AT is [on/off].
```

**Starter prompts for specific workflows** are in `context/prompts/`.

---

## Usage limits vs. context window limits

Claude has two separate constraints that are easy to confuse.

**Usage limits** control how much Claude can be used over time. Check your current usage at: **Claude > Settings > Usage**. The usage page shows current 5-hour session percentage, session reset time, weekly all-models usage, and weekly reset time. A session reset does not help if the weekly all-models cap is already exhausted — check both.

**Context window limits** control how much information fits in one conversation. The context window gauge (in `context/diagnostics/context-window-gauge.md`) estimates how full the current task is.

**High-burn factors** that affect usage quickly: large playbook loads, source document digestion, browser automation with screenshots, Adaptive Thinking, long generated output, repeated tool loops.

For high-burn tasks, check Settings > Usage before starting and ask Claude for a plain-text burn estimate.

---

## Folder structure

```
photo-workflow-cowork-playbook/
├── CLAUDE.md                        — startup router (Claude reads this first)
├── context/                         — Claude's working context
│   ├── operating-rules.md           — standing rules (always loaded)
│   ├── workflow-loadouts.md         — what to load per workflow type (always loaded)
│   ├── evo-general-context.md       — company, team, systems background
│   ├── references.md                — URLs, column maps, SKU formats
│   ├── cowork-tool-limitations.md   — what Claude can and cannot do
│   ├── templates.md                 — post templates, ticket templates
│   ├── troubleshooting.md           — known failure modes and fixes
│   ├── diagnostics/                 — optional: context-window-gauge.md
│   ├── workflows/                   — step-by-step workflow docs
│   ├── standards/                   — image standards, PIM category ordering
│   ├── projects/                    — active project docs
│   ├── prompts/                     — task starter prompts
│   ├── handoffs/                    — task continuity files (local; excluded from shared exports)
│   └── planning/                    — backlog and future work (load only when needed)
├── work/                            — human working folder; contents excluded from package exports
└── docs/                            — human-only reference (this file lives here)
```

---

## Versioning

Playbook versions follow `vMAJOR.MINOR` format. Generated ZIPs are stored in an external export root, **outside** the project, at:

- Final ZIPs: `<EXPORT_ROOT>/photo-workflow-cowork-playbook/finals/`
- Review iterations: `<EXPORT_ROOT>/photo-workflow-cowork-playbook/reviews/`

The `work/` folder inside the Playbook is the human working folder; generated ZIPs do not live there.

`CHANGELOG.md` lives at the project source root but is **excluded from shared and deployed packages**. Load it only during Code-side maintenance when preparing a release or reviewing version history.

---

## Key rules (summary)

The three rules that matter most for new users. The general evo live-system safety layer (Tier 1/2/3) is in `context/evo-system-guardrails.md`. The Photo-specific operating rules build on it in `context/operating-rules.md`.

- **Read before writing.** Claude summarizes what it found and what it will change before changing it. Applies to every shared system (PIM, Daily Report, PO Tracker, Sheets).
- **Every PIM write action requires explicit approval.** State the exact SKU, colorway, and action; wait for go-ahead. PIM saves instantly with no undo.
- **No deletions, no claims of completion, no final approval without human confirmation.** Claude is never the final approval for product image accuracy.

---

## Governance and safety summary

- This Playbook is a controlled workflow context package, not a loose prompt set.
- It is Cowork-runtime-first and Code-maintained.
- It uses human approval gates, workflow maturity stages, handoffs, and versioning.
- Claude assists with analysis, documentation, QA, preparation, and controlled execution.
- Live-system writes require explicit human approval.
- Workflow promotion requires Cowork-environment validation.
- The goal is safe, repeatable Cowork-assisted workflow execution around live evo systems.

The full safety architecture — Tier 1 critical system guardrails, Tier 2 operational reliability rules, Tier 3 team and maintainer preferences, risk levels, required workflow metadata, and what Claude is never the final approval for — is in `context/evo-system-guardrails.md`. Apply it to any task involving PIM, Shopify, DAM, SharePoint/Drive, vendor portals, reports, image assets, or bulk file operations.
