# Start Documentation Update Task

**Workflow stage:** Beta — first iteration of the documentation feedback loop as a structured prompt. Iterate based on real use; promote toward a Skill once the pattern is stable.

**Settings check before starting:**
This is structured execution with some judgment (classification + targeting). Adaptive thinking should be **OFF** for routine updates. Turn ON only when the takeaway involves competing tradeoffs, structural design decisions, or conflicting existing guidance. Confirm your current settings.

**Load:** Use the **Playbook Update / Versioning** loadout from `context/workflow-loadouts.md`. The `doc-update-index.md` file is mandatory for this workflow.

**Note on task ordering:** The standard 8-step task startup procedure in `context/operating-rules.md` runs first, regardless of which prompt is being invoked. This prompt then drives the doc-update work *within* that task — it does not replace startup. If pasted as the opening message of a Cowork task, expect Claude to complete startup first, then read this prompt, then execute the doc-update process.

---

## Purpose

Use this prompt when the evo team member provides a new takeaway, finding, correction, workflow change, limitation, governance decision, or testing result and asks to update the playbook documentation.

This is the **documentation feedback loop** — the process that turns each test run into living documentation without losing control of the package.

---

## Process

For each takeaway:

1. **Restate the takeaway** in one sentence to confirm understanding.
2. **Classify the takeaway** as one of:
   - Universal workflow requirement
   - Cowork-runtime requirement
   - Code-maintenance-only convenience
   - Experimental future Skill / plugin candidate
   - Deprecated / redundant in all environments
3. **Identify the target file or files** by consulting `context/doc-update-index.md`. If the topic is not yet in the index, flag it for index update.
4. **Read target files before editing.** Confirm what is currently there before making changes.
5. **Apply the smallest sufficient update.** Do not rewrite surrounding sections. Do not consolidate or restructure unless explicitly asked.
6. **Check for duplicate or conflicting guidance** in related files. If found, surface to the evo team member — do not silently reconcile.
7. **Update `context/doc-update-index.md`** if the topic mapping changes (new file added, new topic area, new cross-reference).
8. **Preserve maturity-stage labels** (Production / Beta / Alpha / Backlog), handoff rules, and versioning rules. These are structural and should not change as a side effect of a content update.
9. **Summarize the changes:**
   - Files changed and why
   - Conflicts found
   - Deferred follow-up
   - Whether the current handoff should be updated to reflect this change

---

## Safety rules

- **Do not delete files.**
- **Do not broadly rewrite files** unless the evo team member explicitly asks.
- **Do not remove Cowork-runtime guidance** just because Claude Code has a native equivalent. The package is Cowork-runtime-first.
- **Do not convert workflows or prompts to Skills** unless explicitly asked. Skills migration is stage-gated.
- **Do not touch live PIM, DAM, SharePoint, vendor systems, or production data** as part of a documentation update.
- **Do not silently reconcile conflicts** between files. Surface the conflict and let the evo team member decide.
- **Do not bump the playbook version** as part of a single doc update. Version bumps happen at task end via the `versioning.md` procedure when multiple changes accumulate.

---

## When this prompt is the wrong choice

- The change is a new workflow procedure, not a documentation correction → use the relevant workflow's start prompt or the Playbook Update loadout directly.
- The change requires structural restructuring (new folders, file renames, package reorganization) → propose to the evo team member first; do not proceed without explicit approval.
- The change is a one-off note that does not belong in the playbook → record it in the handoff instead.

---

*Notes on this prompt's own evolution: This file is itself a Beta-stage workflow. Capture friction points, missed steps, and over-edits in the handoff as candidates for refinement. When the pattern is stable across 5+ uses, evaluate promotion toward a Skill.*
