# Claude Context Management Guide

**Human reference only. Not loaded by Claude.**

This document captures general best practices for managing context, usage, and session discipline when working with Claude Cowork over extended projects. It is project-independent — save or share it as a standalone reference for any new Cowork setup.

---

## Terminology

- In **Claude Cowork**, a single conversation is called a **task**. A new task starts a new context window.
- In **Claude Code** (used by package maintainers), a single conversation is called a **session**.
- In both products, the **5-hour rolling usage window** is called a **session** at Anthropic's billing level. To avoid collision with Code's per-conversation use of "session," this document calls the 5-hour window the **session usage limit** when disambiguation matters.

The rest of this guide uses **task** for the conversation unit, since the runtime is Claude Cowork.

---

## Two separate limits — don't confuse them

Claude has two independent constraints that work differently and are easy to mix up.

**Usage limits** control how much Claude can be used over time. They reset on a timer (the 5-hour session usage limit and a separate weekly cap, depending on your plan). High-burn activities consume usage faster: large file loads, browser automation with screenshots, Adaptive Thinking, long generated output, repeated tool loops, and continuing a very long existing task.

Check your usage at: **Claude > Settings > Usage**

The usage page typically shows:
- Current 5-hour session percentage used and reset time
- Weekly all-models limit and reset time
- Feature-specific usage if applicable

A 5-hour session reset does not help if the weekly all-models cap is already exhausted — check both.

**Length limits** (the context window) control how much information fits inside one conversation. This includes the active conversation history, loaded files, uploaded documents, tool results, screenshots, and Claude's generated outputs. The context window does not reset when a session usage timer resets — everything in a task is preserved until you start a new task.

**Neither limit is visible to Claude directly.** Claude estimates context window fill from token size heuristics. Claude cannot see your usage meter — check Settings > Usage yourself.

---

## Context window fill — when to act

Warning thresholds (communicated in conversation, not as a visual):
- **50%** — awareness checkpoint; note it, continue
- **75%** — avoid starting major new work in this task
- **85%** — finish current step, write a handoff as the next step
- **90%** — stop what you're doing and write a handoff now

The context window gauge (if your project has one) estimates fill. Load it only when: you type a trigger word like "gauge," the task has grown very long, Claude recommends a handoff, or a large source document is about to be loaded.

For routine checks, a plain two-table text summary costs nothing to generate and is sufficient.

---

## Task vs. session — a critical distinction

A **task** is a single conversation context window. It ends when the context window fills or you start a new task. Everything in the task is preserved until it ends. Context window fill is the only thing that drives handoff decisions.

A **session** is the rolling 5-hour usage limit with its own timer. When the timer runs out, the session resets automatically. This does not end the task, does not clear the context window, and does not require a handoff — the conversation continues exactly where it left off.

A low session timer can be a practical reason to pause, wrap up, or write a handoff before starting a large next step. However, it is not technically required: when the session timer resets, the task remains available and the context window does not clear. Use the session timer as a practical planning signal, not as a continuity requirement. Context-window fill remains the required handoff trigger.

Session timer behavior is determined by your plan and may change as Anthropic evolves the product.

---

## Adaptive thinking — on or off

Adaptive thinking is a mode where Claude reasons more extensively before responding. It is locked at the start of a task and cannot be changed mid-task.

**Turn it OFF for** execution work with defined steps: following a workflow, mechanical file edits, templated output, navigation steps, any work where the right answer is already determined and the work is carrying it out.

**Turn it ON for** genuine design problems: designing a new workflow from scratch, debugging an unexpected failure with no known fix, making decisions with competing tradeoffs and no clear answer.

Adaptive thinking consumes significantly more tokens without improving output quality on procedural work. If it's on for a mechanical task, note it and turn it off for the next task.

**At the start of every task, Claude will ask you to confirm whether Adaptive Thinking is on or off, then state whether that matches the workflow type.** If it doesn't match, Claude will write a handoff and prompt you to start a new task with the correct setting — it will not proceed with the wrong setting. You may type "AT is on" or "AT is off" as shorthand in your opening prompt.

---

## Modular context loading

The most important discipline for long-running projects is **loading only what the current task needs**.

A common failure mode: loading the entire project knowledge base at the start of every task "just in case." This fills the context window faster, burns more usage, and doesn't improve output quality — Claude can only use what's relevant to the current task.

A better approach: define task-specific loadouts that specify exactly which files to load for each workflow type. Keep those files lean. Load additional files only when a specific step requires them, not speculatively.

Suggested loading hierarchy:
- **Always load:** core rules, task routing file
- **Load per workflow type:** only the workflow, standards, or reference files that task actually needs
- **Load on demand:** step-specific files when that step is actually starting
- **Never pre-load:** planning files, diagnostics, old session notes, files for future steps

---

## High-burn workflow types

These consume usage quickly, especially in combination:
- Large playbook/context set loaded at task start
- Source document digestion (reading many slides or pages)
- Browser automation with screenshots
- Adaptive thinking on
- Long generated output
- Repeated tool loops
- Continuing a long task that already has heavy prior turns

**Before starting a high-burn task,** estimate the cost in plain text and ask for confirmation. For very expensive operations (reading 100+ slides, extended browser automation sequences), check Settings > Usage first.

**Mitigation:** Use task-specific loadouts, keep output concise, prefer fresh tasks for high-burn work, turn off Adaptive Thinking for mechanical work.

---

## Handoff discipline

Write a handoff before the context window fills — not after. Every task ends with a handoff document that captures: what was completed, what's in progress, key decisions, next actions, and context window/usage numbers.

The handoff is the continuity mechanism. The next task loads only the most recent handoff and the workflow loadout — not the full history. This keeps starting state lean and prevents context window bloat from accumulated history.

A well-maintained handoff system means you can always pick up exactly where you left off, even after a gap of days or weeks.

---

## Practical task discipline

- Use the smallest sufficient context for the task
- Load only the workflow loadout — not the full project
- Flag high-burn work before starting it
- Write a handoff before the task gets expensive, not after
- Start a fresh task for high-burn work rather than continuing a loaded one
- Check Settings > Usage before starting source document digestion or extended automation sequences
- A session reset is a practical planning signal, not a continuity requirement — context window percentage is what drives the handoff decision

---

## Plan notes (verify at claude.ai — values change)

- **Team Standard:** more usage than Pro; 200k context window
- **Team Premium:** 5× more usage than Standard
- **Enterprise:** flexible pooled usage; 500k context window; org and user spend limits

*Check claude.ai/settings for current plan details.*
