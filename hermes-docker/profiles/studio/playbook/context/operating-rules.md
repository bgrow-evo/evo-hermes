# evo Photo Workflow — Operating Rules

This file contains the task-start procedure, standing rules, workflow overview, maturity stages, and handoff policy for evo Photo Workflow Cowork tasks.

For the general evo live-system safety layer (Tier 1/2/3 critical controls, risk levels, required workflow metadata, what Claude is never the final approval for), see `context/evo-system-guardrails.md`. Apply it to any task involving PIM, Shopify, DAM, SharePoint/Drive, vendor portals, reports, image assets, or bulk file operations. The rules below build on those guardrails — they do not replace the Tier 1 controls.

---

## Start of task — always do this first

In Cowork, model selection and Adaptive Thinking are **locked at task start** and cannot be changed mid-task. Confirm both before any work begins. If wrong for the workflow type, note it in the handoff so the next task opens correctly. Recommending a mid-task setting change is not actionable.

### Adaptive Thinking — when to use which

| Setting | Use for |
|---|---|
| **OFF** | Daily Report runs · vendor image sourcing · PIM upload and image ordering · filling templates or capturing findings · any execution task with defined steps |
| **ON** | Designing a new workflow with competing tradeoffs · debugging an unexpected failure with no known fix · planning PDP-PLP auditor architecture · producing a new version of the playbook |

Adaptive Thinking consumes significantly more tokens without improving output quality on procedural work. Never hardcode a specific model or Adaptive Thinking setting as the permanent answer — models and features evolve.

### Task vs. session — two separate constraints

Cowork uses **task** for a single conversation (the unit that holds the context window). The 5-hour rolling usage window is also called a **session** at Anthropic's billing level. To avoid confusion, these rules name them explicitly.

| | What it is | What controls it | Drives handoff? |
|---|---|---|---|
| **Task** | Single conversation context window (200k tokens) | Context window % | Yes — only this drives handoff timing |
| **Session (5-hour usage limit)** | Per-session usage allowance (Settings → Usage) | Hard cap on usage; resets on its own schedule | No — resets do not end the task |

A session reset does not end the task, does not clear the context window, and does not require a handoff — the conversation continues exactly where it left off. A low session timer can be a practical reason to pause, wrap up, or write a handoff before starting a large next step. However, it is not technically required: when the session timer resets, the task remains available and the context window does not clear. Use the session timer as a practical planning signal, not as a continuity requirement. Context-window fill remains the required handoff trigger.

### Session usage warning thresholds

| Session % | Action |
|---|---|
| **85%+** | Warn the evo team member explicitly. Recommend against starting any high-burn workflow. Suggest wrapping up, writing a handoff, and starting a new task after the session resets. |
| **90%+** | Do not initiate any new high-burn work. Decline if proposed. Finish in-progress lightweight work only, write the handoff, stop. |

### Task startup procedure

1. Confirm the Cowork folder is connected
2. Read `CLAUDE.md`
3. Load mandatory startup files: `operating-rules.md`, `workflow-loadouts.md`, and the most recent handoff. The handoffs folder may be empty in a freshly deployed package — if so, ask the evo team member for context. When a handoff is loaded, treat it as a brief: summarize the pending work and confirm the session's goals with the evo team member before any execution begins.
4. Identify the workflow type from the handoff and the evo team member's request
5. Load the full initial workflow loadout for that workflow type (see `workflow-loadouts.md`)
6. **Adaptive Thinking and model check — required, do not skip.** Ask the evo team member: "Is Adaptive Thinking on or off for this task?" State the correct setting for the identified workflow type. If mismatched, write a handoff immediately and prompt a new task with the correct setting. Do not proceed with mismatched settings.
7. **Usage check — required, do not skip.** Ask the evo team member to share a Settings → Usage screenshot. Record opening numbers (current session %, weekly all-models %, weekly Claude Design %, daily routine runs X / 25). Note: the usage meter updates with delay after a heavy response — actual % may be higher than what is shown. Steps 6 and 7 should be requested together in a single message.
8. **Run context check.** After the full initial loadout is complete and usage is recorded, run the context check (two-table markdown) and report numbers. This baseline must reflect the full starting state — running it before the loadout is complete produces a false low reading.

**On-demand loading after startup:** Once the initial loadout is complete and the context check is done, do not pre-load files speculatively. Load step-specific files only when the step that requires them is actually starting.

---

## Standing rules

- **Inspect before testing anything new.** When encountering a new system, UI interaction, or upload mechanism for the first time — inspect the page source, network behavior, or relevant code before attempting any action. Understand what the action does under the hood before triggering it. This prevents unintended changes, especially in shared systems like PIM.
- **Pause and confirm before anything large, bulk, or repeated.** Before restructuring files, running bulk operations, making sweeping edits, repeated requests to brand sites or evo systems (PIM, Daily Report, PO Tracker, Google Sheets), or any action with broad scope — describe the plan, estimate token/usage cost if expensive, and wait for explicit go-ahead. Ask whether anything else needs clarifying before starting. This prevents rate-limiting, unintended data changes, and rework from missed assumptions.
- **Flag when Adaptive Thinking should be on but isn't.** If a mid-task decision involves competing tradeoffs with no clear answer, an unexpected failure with no known fix, or architectural design — flag it explicitly before proceeding. Name the decision and why Adaptive Thinking would help. Do not silently push through ambiguous design decisions.
- **Always identify products by EB-SKU and product name + color.** Include both the EB-SKU (e.g. EB-272463-1003) and the product name and color (e.g. Granville Shoulder Bag / Sea Salt). Never refer to a product by name alone or SKU alone.
- **Always work in a dedicated browser window opened by the evo team member.** Claude cannot open new browser windows — only new tabs. At the start of any browser work, prompt the evo team member to open a fresh Chrome window first. Claude then opens tabs within that window. This keeps Claude's work clearly separate and easy to find.
- **Check for open browser tabs at task start.** Before opening any tabs, check for tabs already open and close any no longer needed. Claude can only close tabs it opened in the current task — prompt the evo team member to close others.
- **Request folder access at task start for image work.** Cowork does not retain folder access between tasks. Prompt the evo team member to connect the working folder via `request_cowork_directory`. Prefer local drives (e.g. `~/Desktop/Editing`) over OneDrive for image work.
- **"Pick up where we left off" → load the most recent file in `context/handoffs/`.** Use bash (`ls /sessions/.../mnt/Cowork/context/handoffs/`) to list handoff files. Sort by filename and load only the last result. All task-end documents are handoffs — no separate "report" type. **File discovery in Cowork:** when accuracy matters — handoffs, version checks, package reviews, cross-file documentation updates — prefer bash-based checks (`find`, `ls`, `grep`) before relying on Glob. Glob may be used as a secondary convenience check, but do not rely on Glob alone in Cowork unless it has been verified against bash results in the current folder/task (see `cowork-tool-limitations.md`).
- **Check all today's handoffs at task start.** Use bash-based file discovery (`find` or `ls`) to check for handoff files with today's date (`YYYY-MM-DD` prefix) so all work completed earlier in the day is visible. Glob may be used as a secondary check, but do not rely on Glob alone in Cowork — see the prior bullet and `cowork-tool-limitations.md`.
- **Close browser tabs proactively.** Close tabs as soon as they're no longer needed — don't wait until task end.
- **Every PIM write action requires explicit approval.** Before uploading images, reordering, deleting, changing Primary/Pattern dropdowns, changing matrix assignment, or marking rows complete — state the exact SKU, colorway, and action, and wait for explicit go-ahead. This applies even when the next step seems obvious. PIM is a live production system; every action commits instantly and cannot be undone.
- **Read before writing all shared systems.** Before changing PIM, Daily Report, PO Tracker, or any shared system, summarize what was found and what will change.
- **Flag high-burn work before starting.** Before beginning a task that will consume significant tokens (many file reads, browser automation with screenshots, source document digestion, long structured output) — estimate the cost in plain text and ask for confirmation before proceeding.
- **Search the full Cowork folder tree before reporting on files.** When locating any file — zips, archives, outputs, or any artifact — always run `find /sessions/.../mnt/Cowork/ -name "pattern" | sort` across the entire tree using bash. Never stop at a subfolder and report results as complete. A partial search will miss files in sibling folders and produce incorrect "not found" or "latest is X" reports.
- **No deletions without explicit confirmation.** Do not delete files, clear data, or mark rows complete without explicit instruction. Before deleting any Cowork file, check recoverability (recent zip in `_exports/photo-workflow-cowork-playbook/finals/` or local backup) and state it.
- **Never infer that a value has changed without evidence.** If a field was previously documented as "see Merch Sheet" (or any other placeholder) and the actual value was never recorded, finding the real value is not evidence of a change — it is simply the first time it was captured. Do not describe or imply a change unless a previously recorded value differs from a newly observed one.
- **Always capture direct URLs — never descriptions.** When a system, sheet, DAM, or resource is referenced, record its full direct URL in `references.md`. A navigation description is not sufficient — it requires manual clicking and cannot be used directly. If a URL is not yet known, flag it as a gap and obtain it at the first opportunity.
- **Prefer structured sources over browser navigation.** For PDP audits or data gathering: prefer sitemap, Shopify product JSON (`/products/[handle].json`), feed, export, or spreadsheet over page-by-page browsing.
- **Always check the Merch Sheet before accessing any vendor DAM.** DAM links change frequently — never navigate to a vendor DAM from memory or from the vendor DAM guide without first confirming the current link in the Merch Sheet. This applies even to brands with established DAM entries. The Merch Sheet is the live source of truth; the vendor DAM guide records historical findings only.
- **Warn before context window fills.** If the task is growing long, warn proactively and recommend writing a handoff and starting a fresh task. Write the handoff at task end — not mid-task unless the context window is actually forcing a stop.
- **Use the context check by default; reserve the gauge for high-fill situations.** Context check: two-table markdown summary, no tool call needed. Use for routine checks. Gauge: HTML widget via `show_widget`, ~1–2k tokens — reserve for 75%+ fill or when the evo team member types "gauge." Warning thresholds apply to the **context window** only (not the session timer — see above): 50% = awareness; 75% = moderate warning; 85% = handoff zone; 90% = critical, stop now.
- **Current rules override stale handoffs.** `CLAUDE.md`, `operating-rules.md`, and `workflow-loadouts.md` always take precedence over anything in a handoff file.
- **Update context files when instructed.** User-flagged corrections: update immediately. Proactive improvements: hold until task end and batch.
- **Log PIM Photo Guide gaps immediately.** Any uncovered product type, angle, or scenario → raise it as a documentation-improvement candidate with the question and date. Flag and ask before making assumptions. The maintainer logs confirmed gaps in source-side backlog.
- **Documentation feedback loop.** Produce a doc-improvement candidate before the task ends whenever: something breaks unexpectedly; a workflow step completes successfully for the first time; a rule is violated, clarified, or newly established; a vendor-specific behavior is discovered; a troubleshooting entry proves wrong. Use `context/doc-update-index.md` to identify all affected files. Batch proactive improvements at task wrap-up.
- **Guard against silent drift when consolidating or rewriting docs.** When asked to consolidate, tighten, or rewrite documentation where specific wording may carry meaning: pause before rewriting; specific language often encodes domain knowledge, edge cases, or deliberate qualifiers. Flag the drift risk explicitly before doing the work and offer a safer variant — adding metadata fields, consolidating clear duplicates, or flagging rewrite candidates inline — rather than silently rewording. Default to additive over destructive: a new Status field, date, or comment is safer than a rewrite. Let the evo team member decide whether to rewrite.

---

## Playbook versioning

See `context/versioning.md` for the full procedure, including zip naming, save location, and version increment cadence.

---

## Workflow pipeline

The evo digital content workflow is a sequential pipeline. Steps feed into each other in this order:

1. **Daily Report** — identifies missing images and descriptions across On Hand, On Order, and Dropship inventory. Output: prioritized work queue. *(Production)*
2. **Vendor image sourcing and SKUing** — acquires vendor images, matches to SKU/colorway, creates EB-SKU folders. *(Beta)*
3. **Image editing and processing** — Python/Pillow shell-based processing for clean-source images; Photoshop for complex clipping. *(Beta — Python/Pillow confirmed; Photoshop automation Alpha)*
4. **PIM upload and image ordering** — uploads folders to PIM, orders images, marks work complete. *(Beta)*
5. **PDP-PLP audit** — validates live PDPs and PLPs against image standards and go-live conditions. *(Alpha — see `context/projects/pdp-plp-auditor/`; source-only / Claude Code only — not available in deployed Cowork packages)*

If a step hasn't happened, do not proceed to the next step without explicit confirmation.

**Workflow state model — a single SKU moves through these states:**

> Not claimed → Claimed / searching → Images sourced → Processed → Uploaded to PIM → Ordered / QA'd → Complete

Workflow files use descriptive section headings, not global step numbers. The pipeline stage files (01–, 02–, 03–, 04–) are numbered only for sort order — do not reference them as "Step 1" or "Step 2" within documentation or conversation.

---

## Workflow maturity stages

Before running any workflow, check its maturity stage and calibrate accordingly.

| Stage | Meaning |
|---|---|
| **Production** | Tested repeatedly; safe to use with normal review points |
| **Beta** | Tested successfully in limited conditions; use with explicit validation and stop points |
| **Alpha** | Designed or partially documented but not fully tested; narrow test scope only; do not run broadly without explicit user confirmation at each step |
| **Backlog** | Planned but not ready to execute |

**Current stage assignments:** Daily Report = Production · Vendor image sourcing = Beta · Python/Pillow image editing = Beta · Photoshop automation = Alpha · PIM upload = Beta · PDP-PLP auditor = Alpha · Playbook maintenance = Beta

**Stage promotion rule:** Workflow stage promotions (Alpha → Beta, Beta → Production) require a Cowork-environment test run, not a Code-only run. See `CLAUDE.md` for the Architecture status.

---

## PDP go-live conditions

A product goes live on evo.com only when ALL of the following are true:

1. Inventory assigned in NetSuite via Purchase Order such that the SKU appears on the Missing Images Report
2. Web Display set to "Full" in Item Setup at the child SKU level (set by buyers)
3. Product Information complete in Products Manager in PIM, status set to "Live" (not "Pending Edit")
4. At least one image assigned for that matrix value in Product Images in PIM

**Critical exception:** If a new variant belongs to a parent SKU already live on Shopify, it can go live without an image. Shopify renders a text-only thumbnail (size or color name). This bypasses the normal image requirement and will not be caught by a standard missing-image check. This is a known audit gap requiring visual inspection.

---

## What to load

Do not load the full `context/` folder by default.

Every task starts by loading:
- `context/evo-system-guardrails.md`
- `context/operating-rules.md`
- `context/workflow-loadouts.md`
- The most recent file in `context/handoffs/`

Then identify the workflow type from the handoff and user request, and load only the files listed in the matching workflow loadout in `workflow-loadouts.md`.

Do not load workflows, standards, projects, planning, diagnostics, or additional handoffs unless the active workflow loadout requires them or the evo team member explicitly asks.

**`CHANGELOG.md` is not part of any default loadout.** Load it only when preparing a release/version zip, reviewing release history, or summarizing changes between versions. It is root-level human reference, not runtime context. Do not load during routine task startup or normal workflow execution.

---

## Handoff rule

Every task ends with a handoff. There is no separate "report" type — all task-end documents are handoffs regardless of whether the work is complete or mid-flight.

**Close browser tabs at task end — after the handoff is written.** Once the handoff file is complete: (1) ask the evo team member to confirm they are ready to close tabs, (2) close all tabs Claude opened in this task using `tabs_close_mcp`. Closing the last tab in the task's tab group auto-removes the group and closes the Chrome window — no separate window-close step needed. Always do this in order: handoff first, then confirm with user, then close tabs.

See `context/templates.md` for the complete handoff format, filename convention, filing rules, and step-by-step procedure.

Write proactively — before the context window fills, not after. The session timer is a practical planning signal, not a continuity requirement — it resets automatically. Only context window percentage drives the handoff decision.

---

## Current version

Current version: v11.5. Rollback target: v11.4.

---

## Chat vs. Cowork

Use Cowork for tasks requiring file access, browser control, screenshots, or live project context. For strategy, wording, or stakeholder communication that does not require live Cowork context, suggest switching to a regular Claude.ai chat with a compact handoff prompt — this preserves the Cowork context window for execution work. See README for guidance on model and Adaptive Thinking selection before starting a task.
