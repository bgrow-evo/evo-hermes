# evo System Guardrails

Safe-use rules for Claude Cowork around live evo systems, applied to the Photo Workflow Cowork Playbook.

This file is the general evo live-system safety layer. Photo-specific workflow rules live in `context/operating-rules.md` and the workflow files; those rules build on these guardrails, they do not replace them.

---

## Purpose

Claude Cowork is helpful, fast, and confident — including when it is wrong. Around live evo business systems, "confident and wrong" can mean an unintended PIM write that propagates to live PDPs, a vendor image uploaded to the wrong SKU, a vendor portal action that misinterprets source data and grabs the wrong images, or a deletion that cannot be undone.

These guardrails exist so the human stays in the loop on every action that affects live data, and so Claude's role stays in the zone where it is genuinely additive: analysis, drafting, QA, prep, and documentation — not unsupervised execution against systems of record.

---

## What matters most

The most important controls are the **live-system safety controls** in Tier 1: human approval before writes, explicit confirmation before deletion or replacement, scoped approval before bulk actions, rollback awareness, and human final approval for customer-facing correctness. Other operating rules support reliability, but they are not substitutes for these critical controls.

The tiers below separate **what cannot be compromised** from **what supports reliable execution** from **what is convention or maintainer preference**. They are not equally important.

---

## Scope of live evo systems

These guardrails apply to Cowork tasks that touch any of:

- **Product Information Manager (PIM)** — product data, images, matrix assignments, status changes, image ordering, marking rows complete
- **Shopify** — products, collections, inventory, page content, PDP/PLP visible state
- **Digital Asset Managers (DAM)** — vendor DAMs (Aprimo, Bynder, brand-specific), internal DAM, image archives
- **Vendor portals** — brand-specific portals where Claude reads or writes
- **SharePoint and Google Drive** — shared documents, the Daily Report, the Merch Sheet, the PO tracker, Claude Photo Guide source decks, any sheet other team members rely on
- **Operational reports** — Daily Report, PO tracker, Missing Images Report, any sheet other team members rely on
- **Image assets** — any file that may be uploaded to PIM, the DAM, or otherwise exposed on a live PDP
- **Bulk file operations** — image batch processing, bulk renames, bulk moves, bulk deletions — even when local, because they are hard to reverse and easy to misjudge

If your task touches any of these, this doc applies.

---

## Core principle

> Claude assists with **analysis, documentation, QA, and prep**. Claude does not perform live-system changes without human review, explicit approval, prior testing, and a known rollback path.

Three corollaries:

1. **Read before writing.** Before changing anything in a shared system, summarize what was found and what will change. The team member approves before Claude proceeds.
2. **Approve every live write individually unless a workflow has been explicitly batch-approved.** "Approve all" is not the default. Per-action approval is.
3. **No work that lacks a rollback path** unless the team member explicitly accepts that risk. If you cannot describe how to undo it, you should not start it.

---

## Tier 1 — Critical system guardrails

Non-negotiable live-system controls. Treat as absolute. Never weakened by team conventions, output preferences, or maintainer convenience.

### No live-system write without explicit human approval

Before uploading images to PIM, reordering images, deleting images, changing Primary/Pattern dropdowns, changing matrix assignment, marking rows complete, publishing in Shopify, or modifying any field in a live system — state the exact target (SKU, colorway, file, row, URL, system) and the exact action, and wait for explicit go-ahead. **This applies even when the next step seems obvious.** PIM and Shopify commit instantly; most actions cannot be undone.

### No deletion, replacement, clear, archive, or destructive action without explicit confirmation

Do not delete files, clear data, replace files, archive records, change status to a downstream value, mark Daily Report rows complete, or remove images from PIM without explicit instruction. Before any destructive action, check recoverability (recent zip in `_exports/photo-workflow-cowork-playbook/finals/`, local backup, version history, vendor source) and state it in the same message that requests approval.

### No bulk or destructive operations without scoped approval and a rollback path

Before running bulk image processing, sweeping renames, repeated requests to brand sites or evo systems (PIM, Daily Report, PO Tracker, Sheets), or any action with broad scope — describe the plan, name the rollback path, estimate cost if expensive, and wait for explicit go-ahead. If no rollback path exists, do not proceed unless the team member explicitly accepts that risk.

### Read before write

Before changing PIM, the Daily Report, the PO Tracker, the Merch Sheet, or any shared system, summarize what was found and what will change. The team member approves before Claude proceeds. This applies universally — PIM, Shopify, DAM, sheets, vendor portals, file operations.

### Identify the exact target before action

Every action must name its target precisely:

- **Products:** EB-SKU and product name + color (e.g. `EB-272463-1003 / Granville Shoulder Bag / Sea Salt`). Never refer to a product by name alone or SKU alone.
- **Files:** full path, not just filename
- **Rows:** sheet name, tab, row number, and column
- **System changes:** system name, record ID, field, old value, new value

Vague action descriptions ("update the products," "fix the rows") are not actionable and must be refused.

### Stop on unexpected behavior

If a system responds in a way the workflow did not predict — a missing record, an unexpected error, a UI change in PIM, a vendor DAM behavior change, a Daily Report value that does not match prior reads — stop. Surface what was observed. Do not retry, do not re-route, do not improvise. Wait for human guidance.

### Do not bypass existing approval gates

If a workflow defines an approval gate at a step, hit that gate every time. Do not skip it because the prior batch was approved, because the workflow looks routine, or because it appears the team member is in a hurry. Approval inheritance is not allowed (see Risk levels below).

### Claude is never the final approval

For any of these categories, the team member is the final approver — even when Claude has read, prepared, or proposed:

- Product image accuracy (the right image is on the right product, color, matrix value, in the right order)
- Pricing, inventory, and any field that affects what customers see or buy
- Compliance, legal, or contractual content
- Any system change that another team member will downstream act on as a system of record (Daily Report status changes, PIM "complete" flags, PO tracker updates)

Claude can prepare, propose, draft, or QA. The team member signs off.

---

## Tier 2 — Operational reliability rules

Important execution practices that keep Photo workflows reliable and predictable. Not the same risk tier as Tier 1 — a Tier 2 lapse usually causes inefficiency or rework, not unrecoverable harm — but they should be followed by default.

### Pause and confirm before high-burn work

Before beginning a task that will consume significant tokens (many file reads, browser automation with screenshots, source document digestion, long structured output) — estimate the cost in plain text and ask for confirmation before proceeding. See `docs/claude-context-management.md` and `context/diagnostics/usage-estimates.md` for what counts as high-burn for the Photo package.

### Use workflow loadouts

Load only the files the current workflow type requires. Do not pre-load the full package "just in case." See `context/workflow-loadouts.md` for the loadout pattern.

### Inspect before testing anything new

When encountering a new system, UI interaction, or upload mechanism for the first time — inspect the page source, network behavior, or relevant code before attempting any action. Understand what the action does under the hood before triggering it. This is what prevents unintended changes in shared systems like PIM.

### Use a dedicated browser window for Cowork browser work

Cowork cannot open new browser windows — only new tabs. The team member opens a fresh Chrome window at task start; Cowork then opens tabs within that window. This keeps Claude's work clearly separate from the team member's other browsing.

### Check for open browser tabs at task start

Before opening any tabs, check for tabs already open and close any no longer needed. Cowork can only close tabs it opened in the current task — prompt the team member to close others.

### Capture direct URLs — never descriptions

When a system, sheet, DAM, or resource is referenced, record its full direct URL in `context/references.md`. A navigation description requires manual clicking and cannot be used directly. Always check the Merch Sheet before accessing any vendor DAM — DAM links change frequently and the Merch Sheet is the live source of truth.

### Search the full Cowork folder tree before reporting on files

When locating any file — zips, archives, outputs, or any artifact — run a full-tree search using bash (`find /sessions/.../mnt/Cowork/ -name "pattern" | sort`) across the entire tree. Never stop at one subfolder and report results as complete. A partial search will miss files in sibling folders and produce incorrect "not found" or "latest is X" reports.

### Use bash-first file discovery when accuracy matters

For handoffs, version checks, package reviews, and cross-file documentation updates, prefer bash-based checks (`find`, `ls`, `grep`) over Glob. Glob has been observed to return empty results for connected folders even when files are present. Glob may be used as a secondary convenience check, but verify against bash results in the current folder/task before relying on it. See `context/cowork-tool-limitations.md` for the full Glob entry.

### Maintain handoffs

Every task ends with a handoff capturing what was completed, what is in progress, key decisions, next actions, and context window/usage numbers. The next task loads only the most recent handoff and the workflow loadout — not the full history. See `context/templates.md` for the handoff format.

### Never infer that a value has changed without evidence

If a field was previously documented as "see Merch Sheet" or another placeholder and the actual value was never recorded, finding the real value is not evidence of a change — it is the first time it was captured. Do not describe or imply a change unless a previously recorded value differs from a newly observed one.

### Current rules override stale handoffs

`CLAUDE.md`, `context/operating-rules.md`, and `context/workflow-loadouts.md` always take precedence over anything in a handoff file. Handoffs capture state at a moment in time; the rules files capture current policy.

### Run the documentation feedback loop

Produce a doc-improvement candidate before the task ends whenever: something breaks unexpectedly; a workflow step completes successfully for the first time; a rule is violated, clarified, or newly established; a vendor- or system-specific behavior is discovered; a troubleshooting entry proves wrong. Use `context/doc-update-index.md` to identify all affected files. See `context/prompts/start-doc-update.md` for the structured prompt.

---

## Tier 3 — Team and maintainer preferences

Useful conventions that keep the Photo Playbook consistent and easier to maintain. Not system guardrails — a Tier 3 inconsistency is a style issue, not a safety issue. Do not present these as live-system safety requirements.

- **Folder and file naming preferences** — kebab-case for content files, ALL CAPS for `CLAUDE.md` / `README.md` / `CHANGELOG.md`, sequential numbering only for the workflow pipeline files (`01-…`, `02-…`)
- **Output style preferences** — table layouts, heading hierarchy, list formatting, code-block conventions
- **Package maintenance conventions** — version bump cadence, zip naming, archive organization, when to add a CHANGELOG entry, the `_exports/photo-workflow-cowork-playbook/reviews/` review-suffix pattern
- **Claude Code-only conveniences** — slash commands, hooks, permission modes, settings.json — Code-side maintainers may use these freely, but they must not be introduced into the user-facing Cowork package
- **Handoff detail preferences** — narrative vs. bulleted style, table formats for usage numbers, level of detail on next actions

These preferences serve the Photo team. They do not substitute for, override, or weaken Tier 1 or Tier 2 controls.

---

## Risk levels

Every action falls into one of four risk levels. The level determines what approval is required.

| Level | Examples | Required before action |
|---|---|---|
| **Low** | Summarize content, draft language, classify or categorize, propose options, search files, read live systems read-only, scan the Daily Report without claiming | Routine — no special gate |
| **Medium** | Local file rename, prep EB-SKU folders, generate intermediate artifacts (CSVs, sequenced filenames), browser navigation to read a system | State the plan and proceed unless the team member objects |
| **High** | Upload images to PIM, delete files, reorder PIM images, change matrix assignment, change Primary/Pattern, mark a Daily Report row complete, publish in Shopify, send a message | Per-action approval — state the exact target (SKU, colorway, file), the exact action, and wait for explicit go-ahead |
| **Prohibited without approval** | Bulk destructive operations, anything involving credentials, anything that bypasses an existing approval gate, irreversible operations on shared infrastructure | Stop. Surface the request. Do not proceed even with implicit cues — require explicit, scoped approval and document it in the handoff. |

**A note on "approval inheritance":** Approval for one action does not extend to a similar action on a different record. If the team member approves uploading images for SKU A, that does not approve uploading images for SKU B — even if the workflow looks identical. Per-action approval is the default; batch approval must be explicit and scoped.

---

## Required workflow metadata

Every workflow file in `context/workflows/` should declare its metadata at the top. This is what tells Cowork — and the team member — what to expect.

| Field | Meaning |
|---|---|
| **Owner** | Team or role responsible for maintaining this workflow. Use a team or role so the field stays accurate as people change roles. |
| **Systems touched** | Every live evo system this workflow reads or writes (PIM, Shopify, DAM, Daily Report, PO Tracker, etc.). List by name. |
| **Inputs** | What must exist before the workflow can run (files, references, prior workflow outputs). |
| **Outputs** | What the workflow produces. Files, system changes, documentation updates. |
| **Approval gate** | Where in the workflow the team member approves the next live-system action. May be one gate or several. |
| **Rollback path** | How to undo this workflow's writes if something goes wrong. If "no rollback possible," the workflow must be Production stage with extra confidence. |
| **Stage** | Production / Beta / Alpha / Backlog. See `context/operating-rules.md` for current stage assignments. |
| **Cowork-runtime requirements** | Anything the team member must do at task start (folder connection, browser window, model selection, Adaptive Thinking setting). |
| **Code-maintenance notes** | Optional. Anything package maintainers should know — Code-only conveniences that are fine to use during maintenance but must not be inserted into the user-facing workflow. |

A workflow that does not declare these is not ready to be used in Production.

---

## Photo implementation note

The Photo Workflow Cowork Playbook applies these guardrails to:

- Product image workflows (Daily Report → vendor image sourcing → image editing and processing → PIM upload and image ordering)
- Vendor image processing — vendor DAM downloads, image editing in Python/Pillow and Photoshop, image standardization
- PIM Product Image Manager — uploads, reordering, matrix assignments, Primary/Pattern dropdown changes, marking rows complete
- Image ordering and QA against `context/standards/image-standards.md` and `context/standards/pim-category-ordering.md`
- Related reporting in the Daily Report, the PO Tracker, the Merch Sheet, and the Missing Images Report
- Customer-facing PDP and PLP image presentation, including the PDP/PLP audit project in `context/projects/pdp-plp-auditor/` *(source-only; in development)*

Photo-specific operating rules in `context/operating-rules.md` build on these guardrails — they refine, scope, and add Photo workflow specifics, but they do not replace the Tier 1 controls. If a Photo rule and a Tier 1 rule appear to conflict, Tier 1 wins.
