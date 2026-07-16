# Start Cowork Validation Task

**Workflow stage:** Beta — first formalization of the post-version-zip Cowork validation pass. Iterate based on real use; promote toward a Skill once stable across multiple version cycles.

**When to run:** After every new version zip of the playbook is produced (per `context/versioning.md` step 10). Before treating the new version as deployable.

**Settings before opening the task:**
- **Model:** Sonnet (this is execution-style validation, not design)
- **Adaptive thinking:** OFF (mechanical run-through)
- **Folder:** Cowork folder must be connected with the latest live package state

**Load:** Use the **PIM Photo Guide Intake / Standards Update** loadout from `context/workflow-loadouts.md` as the test case. It loads a representative subset of files without touching live systems.

---

## Purpose

Confirm that a freshly-zipped version of the playbook runs cleanly in Cowork after Code-side maintenance. v10.0 introduced the rule that workflow stage promotions and version releases require a Cowork-environment test run, not a Code-only run. This prompt is that test run.

This is a **read-only validation**. No real workflow execution. No live system writes. No edits to the package.

---

## Standard validation checklist (run every time)

Work through these in order:

1. **Folder connection.** Confirm the Cowork folder is connected and report the path.

2. **Architecture status reads cleanly.** Read `CLAUDE.md`. Report any wording in the "Architecture status" section that contradicts Cowork-user assumptions or reads awkwardly.

3. **Task startup procedure executes cleanly.** Follow the task startup procedure in `context/operating-rules.md`. Report any step where the wording is unclear, where the procedure assumes Code-only behavior, or where Cowork cannot perform what is asked.

4. **Baseline-implicit loadout pattern works.** After loading the chosen test loadout, confirm Claude actually loaded `operating-rules.md` and `workflow-loadouts.md` in addition to the listed loadout files — these are no longer enumerated per loadout but should still be loaded as baseline.

5. **`start-doc-update.md` is invocable.** Read `context/prompts/start-doc-update.md`. Confirm a Cowork user could paste it as an opening message and have it work — that it does not assume Code-side behavior or unavailable tools.

6. **Diagnostics file headers do not confuse Cowork users.** Read `context/diagnostics/context-window-gauge.md` and `context/diagnostics/usage-estimates.md`. Confirm the "Runtime applicability" headers read as informational (Code users have native equivalents) rather than as deprecation notices.

7. **Glob guidance is consistent.** Read the Glob guidance in `context/operating-rules.md` (the "Pick up where we left off" rule and the "Check all today's handoffs" rule) and `context/cowork-tool-limitations.md` (the Glob entry). Confirm the wording is consistent across all three — bash-first, Glob as secondary check after verification — with no remaining "never use Glob" language.

8. **Context check baseline.** Run the context check (two-table markdown) and report numbers. This is the baseline after the loadout is fully loaded.

---

## Version-specific additions

Each new version may introduce changes that warrant additional validation steps beyond the standard checklist. Add per-version items below — clear them between version cycles, or archive them in this file as historical notes if useful.

### v10.0 — first pass

- Confirm the new "Architecture status" section in `CLAUDE.md` and `docs/README.md` does not break Cowork's expectation of how the playbook starts up.
- Confirm the consolidated maturity-stages section in `operating-rules.md` reads correctly when loaded as part of the baseline.
- Confirm the new `CHANGELOG.md` at root is *not* auto-loaded by Cowork (it should be reference material, not a startup load).

*(After v10.0 validation, clear or archive these items and add v10.1's per-version additions as needed.)*

---

## Report format (standard output)

Produce a structured report at the end of the session. The format below was established in the v10.0 validation pass and should be followed for all future runs to keep results comparable across versions.

```
## v[X.Y] Cowork Validation — Full Report

---

### Step 1 — [name] ✅ / ⚠ / ❌
[brief result, 1–3 sentences]

### Step 2 — [name] ✅ / ⚠ / ❌
[brief result; flag any documentation feedback candidates with priority]

... (continue through all 8 standard steps) ...

### Step 8 — Context check (baseline after full v[X.Y] startup load)
[two-table markdown context check]
[narrative on what's loaded and how it lines up with usage estimates]

---

## Summary

**v[X.Y] validation passed / passed with caveats / failed.** [One-line verdict.]

**Documentation feedback candidates (priority level):**
1. [file] — [issue] — [priority]
2. [file] — [issue] — [priority]

**[Any version-specific finding sections, if applicable]**

No edits made. [Handoff statement.]
```

**Status markers:**
- ✅ — passed cleanly, no issues
- ⚠ — passed with low-priority documentation feedback candidates (not blocking)
- ❌ — failed (blocks treating the version as deployable)

**Documentation feedback candidates** should be flagged per the standing rule in `operating-rules.md`. Do not silently work around them. The next Code-side maintenance session addresses them; the version may need a v[N].[N+1] hotfix release before it is treated as deployable.

---

## What to do with findings

- **If everything passes (all ✅):** Report briefly in chat using the format above. No handoff needed unless something actionable was found.
- **If passes with caveats (any ⚠):** Report the full structured output. The maintainer rolls findings into the next release. No hotfix required if all caveats are low-priority.
- **If fails (any ❌):** Report the full structured output. Maintainer triggers a hotfix release before any further deployment of this version.

---

## Do not

- Make any edits to the package. This is a read-only validation.
- Run any real workflow (Daily Report, vendor sourcing, PIM upload, PDP audit, etc.).
- Touch live systems (PIM, Shopify, DAM, SharePoint).
- Write a handoff at the end unless something actionable was found. If everything works, a brief "v[X.Y] validation passed" note in chat is sufficient.
- Confuse this with the documentation feedback loop. This validates a *released* version; the doc-feedback loop updates docs *during* a maintenance session.
