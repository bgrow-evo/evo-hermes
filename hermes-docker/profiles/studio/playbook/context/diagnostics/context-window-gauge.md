# Context Window Gauge

**Runtime applicability:** Cowork-runtime tool. In Claude Code, use the built-in `/context` slash command — it shows the same information natively without loading this file. This file remains required for Cowork users, who do not have a built-in context view. Do not remove this file while Cowork remains the target runtime.

---

Two formats available. Use the context check by default; reserve the gauge for high-fill situations.

---

## Context check (default — no file load needed)

A two-table markdown summary. ~200–300 tokens, no tool call. Use for any routine status read.

**Format:**

| Total used | Available |
|---|---|
| ~Xk / 200k (Y%) | ~Xk (Y%) |

| System | Context files | Conversation | Tool results |
|---|---|---|---|
| ~Xk (Y%) | ~Xk (Y%) | ~Xk (Y%) | ~Xk (Y%) |

Trigger: any time a quick status read is needed, before loading files, or when the evo team member asks for a context check.

---

## HTML gauge (load this file first)

Full visual widget via `show_widget`. ~1–2k tokens including tool call overhead. Reserve for 75%+ fill or when the evo team member explicitly types **"gauge"**.

Load this file (`context/diagnostics/context-window-gauge.md`) only when rendering the HTML gauge — not for the context check.

---

## Warning thresholds (both formats)

- **50%** — awareness checkpoint, no action needed
- **75%** — moderate warning; avoid starting large new tasks
- **85%** — handoff zone; finish current task, write handoff next (~10–15k tokens needed)
- **90%** — critical; stop and write handoff now

---

---

## When to warn (text, in conversation)

- **50%** — awareness checkpoint, no action needed
- **75%** — moderate warning; avoid starting large new tasks
- **85%** — handoff zone; finish current task, write handoff next (~10–15k tokens needed)
- **90%** — critical; stop and write handoff now

---

## Gauge template

**Use verbatim — do NOT call `read_me` first. Replace `[[PLACEHOLDER]]` values only. Recalculate every render.**

```html
<style>
  .cg-bar-row { display: flex; align-items: center; gap: 12px; margin-bottom: 10px; }
  .cg-range { font-size: 15px; font-weight: 500; white-space: nowrap; color: var(--color-text-secondary); }
  .cg-track { flex: 1; position: relative; background: var(--color-background-secondary); border: 0.5px solid var(--color-border-tertiary); border-radius: 6px; height: 18px; overflow: hidden; display: flex; }
  .cg-seg { height: 100%; }
  .cg-tick-red { position: absolute; top: 0; left: 85%; width: 1.5px; height: 100%; background: rgba(229,57,53,0.85); pointer-events: none; }
  .cg-stats { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 6px; }
  .cg-stat { background: var(--color-background-secondary); border: 0.5px solid var(--color-border-tertiary); border-radius: 5px; padding: 4px 8px; font-size: 11px; color: var(--color-text-secondary); white-space: nowrap; display: flex; align-items: center; gap: 5px; }
  .cg-dot { width: 8px; height: 8px; border-radius: 2px; flex-shrink: 0; }
  .cg-stat strong { color: var(--color-text-primary); font-weight: 500; }
  .cg-stat em { color: var(--color-text-tertiary); font-style: normal; }
  .cg-avail { border-style: dashed; }
  .cg-alert { border: 1.5px solid #e53935; background: var(--color-background-danger); border-radius: 6px; padding: 8px 12px; font-size: 12px; color: var(--color-text-danger); margin-bottom: 8px; }
  .cg-footer { font-size: 10px; color: var(--color-text-tertiary); text-align: right; margin-top: 2px; }
</style>
<div class="cg-bar-row">
  <div class="cg-range">[[PCT_LOW]]–[[PCT_HIGH]]%</div>
  <div class="cg-track">
    <div class="cg-seg" style="width:[[SYS_PCT]]%;  background:#6596B5;"></div>
    <div class="cg-seg" style="width:[[CTX_PCT]]%;  background:#759365;"></div>
    <div class="cg-seg" style="width:[[CONV_PCT]]%; background:#CB6754;"></div>
    <div class="cg-seg" style="width:[[TOOLS_PCT]]%; background:#DFBB71;"></div>
    <div class="cg-seg" style="width:[[MARGIN_PCT]]%; background:rgba(211,160,85,0.3);"></div>
    <div class="cg-tick-red"></div>
  </div>
</div>
<div class="cg-stats">
  <div class="cg-stat"><div class="cg-dot" style="background:#6596B5;"></div>System prompt <strong>~[[SYS_K]]k</strong> <em>([[SYS_PCT]]%)</em></div>
  <div class="cg-stat"><div class="cg-dot" style="background:#759365;"></div>Context pack <strong>~[[CTX_K]]k</strong> <em>([[CTX_PCT]]%)</em></div>
  <div class="cg-stat"><div class="cg-dot" style="background:#CB6754;"></div>Conversation <strong>~[[CONV_K]]k</strong> <em>([[CONV_PCT]]%)</em></div>
  <div class="cg-stat"><div class="cg-dot" style="background:#DFBB71;"></div>Tool results <strong>~[[TOOLS_K]]k</strong> <em>([[TOOLS_PCT]]%)</em></div>
  <div class="cg-stat"><div class="cg-dot" style="background:#D4A855; opacity:0.6;"></div>Estimate margin</div>
  <div class="cg-stat cg-avail">Available <strong>~[[AVAIL_K]]k</strong> <em>([[AVAIL_PCT]]%)</em></div>
</div>
[[ALERT_BLOCK]]
<div class="cg-footer">[[MODEL]] · Adaptive Thinking: [[THINKING]] · [[WINDOW]]k token window · Rough estimate</div>
```

## Fill-in guide

- `[[PCT_LOW]]` / `[[PCT_HIGH]]` — midpoint × 0.75 and × 1.25, rounded
- `[[SYS_K]]` / `[[SYS_PCT]]` — system prompt (~6k / 3%)
- `[[CTX_K]]` / `[[CTX_PCT]]` — context files loaded this session
- `[[CONV_K]]` / `[[CONV_PCT]]` — conversation history
- `[[TOOLS_K]]` / `[[TOOLS_PCT]]` — tool results (file reads, bash, screenshots)
- `[[MARGIN_PCT]]` — PCT_HIGH minus midpoint
- `[[AVAIL_K]]` / `[[AVAIL_PCT]]` — window minus all buckets
- `[[ALERT_BLOCK]]` — omit below 85%; at 85%+: `<div class="cg-alert">Approaching handoff threshold — finish current task and write handoff.</div>`; at 90%+: `<div class="cg-alert">Critical — stop and write handoff now.</div>`
- `[[MODEL]]`, `[[THINKING]]`, `[[WINDOW]]` — current session values

## Token size reference

| Source | Approximate tokens |
|---|---|
| System prompt (Cowork overhead) | ~6k |
| Full context pack load (all context/ files) | 15–20k |
| Single medium file read | 1–2k |
| Bash output — short command | 100–300 |
| Screenshot or image | 1–2k |
| Gauge render | ~1k |
| Each conversation exchange | 500–1k |

*These estimates will age — treat as orientation only.*
