# Templates

Output formats for common deliverables. Copy and fill in as needed.

*Context check (two-table markdown) needs no file load — write inline. HTML gauge: load `context/diagnostics/context-window-gauge.md` first; use only when explicitly requested or at 75%+ fill.*

---

## Task handoff

**Filename:** `YYYY-MM-DD_NN_[topic]-handoff.md`

Where `NN` is a zero-padded counter (01, 02…) that increments for each file on the same date, regardless of topic. Underscores separate the date, counter, and topic so the date's own dashes remain visually distinct.

Example: `2026-04-30_01_daily-report-handoff.md`, `2026-04-30_02_vendor-sourcing-handoff.md`

**Save to:**
`context/handoffs/` — required; loaded at next task start

Completed handoffs are **local continuity records**. They stay on disk in `context/handoffs/` and are loaded at the start of the next task. They are **excluded from shared review/final zips**; the `context/handoffs/` folder appears in shared zips only as an empty directory entry. See `context/versioning.md` for the export rules.

**File rules:**
- Always use dated filenames — never generic names
- Never delete or edit files in `context/handoffs/` — all are permanent historical records (local)
- Each task produces a new dated file; prior files remain untouched

**Before writing the handoff — always do this first:**
1. Close any browser tabs opened during this task
2. Run the context check (two-table markdown) and record the numbers
3. Ask the evo team member for a Settings → Usage screenshot and record closing numbers
4. Ask the evo team member if there are any additional next steps to capture
5. Then write the handoff with accurate context window and usage data included

**Draft incrementally during complex tasks.** For tasks with many decisions, new findings, or multiple workflow steps — maintain a running draft as work progresses. Note key decisions and completed steps as they happen. Finalize and save at the end.

**Version increment at task end.** If any `.md` files were edited during the task, increment the minor version (e.g. v9.0 → v9.1), update `CLAUDE.md` and `context/operating-rules.md` with the new version number, and produce a zip. See `context/versioning.md` for the full procedure.

```markdown
# [Topic] — Handoff
**Date:** YYYY-MM-DD HH:MM PT
**File:** `YYYY-MM-DD_NN_topic-handoff.md`

---

## Goal / Scope

## What Was Completed

## What Is In Progress / Blocked
(If nothing, write "None — work complete.")

## Key Decisions and Findings

## Documentation Updated This Task
(Omit section if none.)

## Cross-Project Sync Candidates

Reusable findings from this Photo Playbook update that may need to be reflected in the Digital Content Cowork Framework or another related Cowork project. Promote the principle, not the implementation detail.

- None

## Playbook Version
(Omit section if no version increment this task.)

## Next Actions

**Important — two categories of next actions:**
- **In progress / claimed:** Work already started or claimed in the Daily Report (name written in col A, status set). Safe to pick up directly in the next task.
- **Candidates only:** SKUs or POs identified as possible priorities but not yet claimed. Do NOT assume these are still available — rescan the Daily Report fresh at the start of the next task. Someone else may have claimed them, inventory may have changed, or a higher priority may have appeared.

## Context Window at Task End

| Total used | Available |
|---|---|
| ~Xk / 200k (~X%) | ~Xk (X%) |

| System | Context files | Conversation | Tool results |
|---|---|---|---|
| ~Xk (X%) | ~Xk (X%) | ~Xk (X%) | ~Xk (X%) |

**Context usage analysis:** [narrative: loadout used, what drove each bucket, light/moderate/heavy classification and why]

## Session Timer and Usage Limits

| Limit | Opening | Closing | Delta |
|---|---|---|---|
| Current session | X% (resets in Xhr Ymin) | X% | +X% |
| Weekly — all models | X% (resets Tue X:XX AM) | X% | +X% |
| Weekly — Claude Design | X% | X% | +X% |
| Daily routine runs | X / 25 | X / 25 | +X |

[narrative: divergence notes, weekly flag if applicable]
```

---

## Teams Daily Report post

Copy cells A1:C6 from the Summary tab directly into Teams (preserves table format and green "(new)" text), then add:

```
Daily Report: https://docs.google.com/spreadsheets/d/1hiQ4WNclu6j_nH-TraL3Mx5NSzQUmpQ99Cda4bVrFmI/edit
Report: [link to today's imported PI Report spreadsheet]
```

---

## PDP audit results table

| Product URL | Brand | Product Name | Parent SKU | Variant / Color | Issue Type | Expected | Actual | Evidence | Impact | Severity |
|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | |

**Issue types:** Missing image | Wrong image | Wrong order | Variant mismatch | Text-only thumbnail | Go-live condition not met | Other

**Severity:** P1 - Customer-facing / revenue impact | P2 - Quality / brand impact | P3 - Process / internal

---

## IT Helpdesk bug report / service request

**Request type:** [Bug Report / Service Request / Access Request / Other]

**Requested by:** [evo team member name, role]

**Date observed:**

**Summary:** [One sentence describing the issue or request]

**System / URL affected:**

**Steps to reproduce (for bugs):**
1.
2.
3.

**Expected behavior:**

**Actual behavior:**

**Evidence:** [Screenshot / URL / recording]

**Business impact:** [Customer-facing? Internal only? Workflow blocked?]

**Priority / timeline:**

**Notes:**

---

## IT request template

**Request type:** [Automation / Access / Infrastructure / Other]

**Requested by:** [evo team member name, role]

**Summary:** [One sentence]

**Business need:**

**What we're asking for:**

**What we've already tried or ruled out:**

**Questions for IT:**
1.
2.

**Priority / timeline:**
