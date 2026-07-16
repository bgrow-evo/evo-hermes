# Usage Estimates — Per-Task Burn Reference

**Runtime applicability:** Cowork-runtime tool. In Claude Code, use the built-in `/cost` slash command for real-time per-session cost and token usage. The estimates below remain useful for Cowork users, who do not have a built-in usage view, and for cross-environment baselining. Do not remove this file while Cowork remains the target runtime.

---

Created: 2026-04-30. 

Tracks observed session % and context window token cost per workflow type. Built up from before/after readings recorded in handoffs. Use to warn before high-burn work and to plan how many tasks fit in a session.

**How to update:** After each session, compare opening and closing numbers from the handoff. Add or update the relevant row. Note what drove variance (SKU count, browser automation, file count, etc.).

---

## Context window cost (tokens used, approximate)

| Workflow type | Typical cost | Notes |
|---|---|---|
| Startup (CLAUDE.md + operating-rules + workflow-loadouts + handoff) | ~15–20k | Base cost every task |
| Daily Report loadout (+ references + cowork-tool-limitations + workflow) | +~10k on top of startup | |
| Daily Report scan (gviz fetch + parse, no claiming) | +~3–5k | Low — mostly JS tool results |
| Single doc edit (read + edit) | +~2–4k per file | Depends on file size |
| Multi-file doc update batch (4–5 files) | +~15–20k | This session: ~20k for 5 files |
| Vendor image sourcing — full brand (browser automation + downloads) | ~40–60k | High variance; more SKUs = more tokens |
| PIM upload batch (browser automation, image ordering) | ~30–50k | Depends on SKU count and drag complexity |
| Playbook version update (many file reads + edits) | ~50–80k | Highest burn workflow type |

---

## Session % cost (per-session allowance consumed)

| Workflow type | Typical session % burn | Notes |
|---|---|---|
| Startup only (loadout + context check) | ~8–10% | Observed: task _04 opened at 92%, previous closed ~82% |
| Daily Report scan (no vendor work) | ~3–5% | Light browser automation |
| Single targeted doc edit | ~1–2% | |
| Multi-file doc update batch (4–5 files) | ~5–8% | This session: ~6% estimated |
| Vendor image sourcing — full brand | ~20–35% | High — browser automation + image fetches |
| PIM upload batch | ~15–25% | Moderate-high |
| Playbook version update | ~25–40% | Highest burn — many reads, edits, zip |

---

## Planning guidance

- A full Daily Report scan + small doc batch fits comfortably in one session if starting below ~60%.
- Vendor image sourcing for a single brand: plan for ~25–40% session burn. Do not start above 65%.
- Playbook version update: plan for ~30–45% session burn. Do not start above 55%.
- At **85%+**: warn the evo team member. Do not start any high-burn workflow.
- At **90%+**: finish lightweight in-progress work only, then hand off.

---

## Observation log

| Date | Thread | Task | Session open | Session close | Session burn | Context open | Context close | Notes |
|---|---|---|---|---|---|---|---|---|
| 2026-04-30 | _02 | Daily Report startup attempt | ~78% | ~82% | ~4% | low | low | Startup only; no work completed |
| 2026-04-30 | _03 | Doc update (AT check rule) | ~82% | ~82% | ~0% | low | ~38% | Very light; 2 doc edits |
| 2026-04-30 | _04 | Daily Report scan + 5 doc updates | 92% | ~98% | ~6% | ~18% | ~32% | Scan + multi-file batch |

*Add a row at the end of each session using the before/after numbers from the handoff.*
