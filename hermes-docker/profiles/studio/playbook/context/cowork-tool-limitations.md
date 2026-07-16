# Cowork Tool Capabilities and Limitations

Load when a task depends on browser automation, local files, image downloading, or technical limits of Cowork.

**Environment note:** The Digital Content Team and Photo Studio work on macOS. All file system paths, OS dialog references, and folder picker behavior in this document apply to macOS unless otherwise noted. Tool versions are listed where relevant — check dates to assess whether a limitation may have been resolved.

---

## What Claude Cowork can and cannot do

*This document covers Claude Cowork capabilities and limitations unless otherwise noted. Behavior may differ in Claude Code or Claude.ai Chat. Last reviewed: 2026-05-07. Cowork capabilities evolve — limitations listed here may change. Re-review when Anthropic announces product updates. Per-entry dates are shown only where the date itself is meaningful (e.g., a behavior change or workaround discovery).*

### Claude Cowork can
- **Read and write files** in any folder connected to Cowork (Cowork, Desktop, Downloads, etc.) via bash — macOS file paths apply
- **Browse websites and interact with web page content** — navigate, click, read, run JavaScript inside browser tabs (using Claude in Chrome extension)
- **Inject temporary UI onto web pages** — adding a button or overlay works the same way browser extensions do. It is not a security attack. It disappears on page refresh.
- **Click injected buttons** via browser automation — simulated clicks are recognised as user gestures by the browser, which allows triggering privileged APIs like folder pickers
- **Fetch Google Sheets data via JavaScript** from within a Google-domain browser tab, bypassing the CORS restriction that blocks fetches from brand DTC site tabs
- **Access the Daily Report directly via browser** — Claude always has browser access to the Daily Report (Google Sheets) and should never tell the evo team member that it cannot access it. Navigate directly to the URL in `references.md` and interact via browser automation. Do not ask the user to make edits that Claude can make itself.
- **Run a local relay server** — see below
- **Access a connected default folder automatically** — if the Cowork folder is set as the default/selected folder in Claude Desktop (macOS app), new tasks start with that folder already connected. Confirm at task start that Claude reports the expected folder path before reading or writing files.

### Claude Cowork cannot
- **Rely on Glob alone for file discovery in connected folders** — The Glob tool may return no results even when files are present. This has been observed in connected folders (via `request_cowork_directory`, e.g. `~/Desktop/Editing`) and was previously observed against the Cowork package when it was OneDrive-synced (notably after enabling "Always Keep On This Device" on 2026-05-01). The behavior appears tied to mount resolution in cloud-synced or sandbox-bridged folders. **Operating rule:** when accuracy matters (handoffs, version checks, package reviews, cross-file documentation updates), prefer bash-based checks (`find`, `ls`, `grep`) first. Glob may still be used as a secondary convenience check, but do not rely on Glob alone in Cowork unless it has been verified against bash results in the current folder/task. *(Originally confirmed 2026-04-29; cloud-sync interaction observed 2026-05-01.)*
- **Interact with macOS-level dialogs** — macOS folder picker, macOS Save dialog, Finder windows. These sit above the browser layer and are invisible to Claude's tools.
- **Interact with Chrome's own UI** — permission popups, download dialogs, the Chrome toolbar. Same reason: above the page layer.
- **Fetch files from the internet via bash** — Claude's sandbox only reaches an allowlist (npm, GitHub, Anthropic, etc.). Brand CDNs and most external sites are blocked.
- **Access evo's Azure fileserver or VPN-only resources** — The Azure fileserver (`smb://digitalcontent.evo.local`) and any other resources requiring VPN or evo_Private WiFi are unreachable from Claude's Linux sandbox. These can only be accessed from a local machine that is on VPN or evo_Private WiFi. This affects: the Daily Report xlsx, the Editing folder, Photoshop Actions, and PIM (which requires VPN).
- **Control what happens if you navigate away mid-task** — switching tabs or clicking Back during a download sequence will interrupt it
- **Delete files in connected folders** — Deletion requires explicit permission. If `rm` fails with "Operation not permitted", call the `allow_cowork_file_delete` tool with the file path — the user will see a permission prompt, and once approved, deletion works normally via bash. This applies to all connected folders (the Cowork package and user-connected folders such as `~/Desktop/Editing`). The `⚠️ DELETE THESE FILES.txt` workaround is no longer needed. *(Updated 2026-04-28 — previously documented as a permanent limitation; correct tool discovered)*
- **Set macOS Finder tags (color labels)** — `xattr` is a macOS-only tool not available in the Linux sandbox. Cannot programmatically tag files Red/Yellow/etc. in Finder.
- **Open full-screen previews intentionally** — avoid triggering full-screen/lightbox views in any browser application as they take over the user's entire display. Use side panel previews or thumbnail views only.
- **Trigger downloads from DAMs with auth-token-protected URLs** — Aprimo and similar enterprise DAMs protect asset URLs with session tokens. Direct JS fetch of image URLs is blocked. Use the DAM's native basket/download flow instead, then move the resulting zip to the Cowork folder for processing.
- **Search SPAs (Single Page Apps) via URL keyword params** — Bynder, Aprimo, and similar SPA-based DAMs require interacting with the search box directly; keyword params in the URL are not picked up on load. Always type into the search field and submit.
- **Close tabs from prior tasks** — Claude can only close browser tabs it opened in the current task. Tabs left open from a previous task are not accessible and must be closed manually in Chrome.
- **Check for open tabs at task start** — Before opening any browser tabs, check for tabs already open from the current task and close any that are no longer needed. Required at the start of every task that uses the browser.

---

## Image download method — File System Access API (preferred)

*Confirmed working as of 2026-04-24 on macOS with Chrome. Uses the browser's File System Access API.*

1. Claude opens the brand product page in Chrome and fetches the product JSON (`/products/[handle].json` on Shopify) — one clean request, no page scraping
2. Image URLs and variant/colorway mappings are extracted from the JSON
3. MPN and UPC from the JSON are cross-checked against the Missing Images Matrix Detail tab to confirm correct colorway
4. Claude injects a button onto the page and clicks it via browser automation
5. Chrome opens a folder picker (OS-level dialog) — the user selects the destination folder once (e.g. `Desktop/Editing/YYYY-MM-DD/[Brand]`)
6. JavaScript fetches each image from the brand CDN and writes it directly to the selected folder, creating EB-SKU subfolders automatically
7. Claude verifies all files landed correctly via bash before marking the step done

**File naming:** `01_BrandName-ProductName-Color-1.jpg` — numeric prefix preserves the brand's original image order; full original filename preserved after the prefix.

**The one step requiring user action:** navigating the OS folder picker in step 5 and clicking Select. Claude handles everything else.

---

## Image download fallback — local relay server

*Fallback method. Tested on macOS with Chrome as of 2026-04-24. Behavior may differ on other browsers or OS versions.*

If the File System Access API is unavailable, Claude can fall back to a local relay server:

- Claude starts a temporary, private HTTP server on `127.0.0.1` (your machine only — not reachable from the internet)
- JavaScript in the browser fetches images from the brand CDN and POSTs them to the relay server
- The relay server writes the files to disk
- **Limitation:** Chrome blocks HTTP connections from HTTPS pages (Private Network Access policy) and shows a one-time permission popup — "allow this site to access local services" — that the user must approve. If dismissed, the relay approach fails.
- The relay server disappears when the session ends

---

## Browser window rule

Claude cannot open new browser windows — only new tabs. Claude also cannot detect which Chrome window is active or newly created, and cannot take control of or see into existing Chrome windows or tabs that it did not create. Claude only has visibility into tabs within its own MCP tab group for the current session.

**Known conflict — single monitor + split screen:** When Cowork and Chrome are side by side on one monitor, clicking back into Cowork to type shifts focus away from Chrome. This means the "open a fresh window, then say window is open" approach may not reliably land Claude's new tab in the right window.

**Current best workaround:** Accept that Claude works in whatever window Chrome last had focus on, and verify after tab creation that it landed in the right place. If it lands in the wrong window, close it and try again after clicking into the correct Chrome window.

**To start a browser session:**
1. The evo team member opens a fresh Chrome window and clicks into it
2. The evo team member confirms "window is open" in chat (this will shift focus to Cowork)
3. Claude creates a new tab — it will attempt to land in the most recently active Chrome window
4. Always close tabs when done. When the last tab in a session is closed, the group is auto-removed.

---

## Google Sheets — browser automation rules

*Confirmed behavior as of 2026-04-24 using Claude in Chrome on macOS.*

- **Fetch data:** JavaScript fetches to Google Sheets must run from a tab on a Google domain. Fetches initiated from a brand DTC site tab will fail with a CORS error.
- **Edit cells:** After any cell edit via browser automation (names, status dropdowns), wait for the "Saving…" indicator to clear, then click the cell and verify the value in the formula bar. "Saving…" appearing is not sufficient confirmation — the write can fail if the session navigates or closes before completing.
- **Status dropdown chips:** The chip-style status dropdowns in the Daily Report can misfire to an adjacent option when multiple selections are made in sequence. Always confirm the formula bar value after setting a dropdown via automation.

---

## Claude can act without requiring the evo team member to perform the action

Claude often has the ability to take actions directly (screenshots, navigation, reading page state, bash commands) without needing the evo team member to do it manually. Before asking the evo team member to perform an action, check whether Claude can do it independently. Only ask for direct human action when it is genuinely required (e.g. folder drag-and-drop into PIM, approving folder access, entering passwords). Approval from the evo team member is still required before consequential actions — but the action itself should be Claude's where possible.

---

## Google Sheets — find and navigation

- **Do not use Ctrl+F to search in Google Sheets** — the keystroke may type directly into the active cell instead of opening the find bar, corrupting cell data. Use the Name Box (cell reference field) to navigate to a known row, or scroll manually. When searching for specific rows, search by SKU/parent ID rather than brand name, as multiple brands may share similar names.
- **Resize the browser window if tabs or UI are hard to see** — a larger window makes tab navigation and sheet column visibility easier. Claude can prompt for this when needed.

---

## Rule application within a session

Claude can read a rule and still fail to apply it later in the same session. This is a known behavioral limitation — not a documentation gap. It has been observed in the following ways:

- Using Glob as the sole file-discovery method on the connected Cowork folder immediately after reading the rule requiring bash-first verification and not relying on Glob alone
- Stopping a file search at a subfolder and reporting results as complete, despite a rule requiring full-tree search

**What this means for session design:** Rules that govern tool selection and file inspection are most reliably followed when they are surfaced at the decision point — not just present somewhere in the loaded context. When a rule is critical and the failure cost is high (incorrect reporting, missed files, wrong tool used), consider restating it in the prompt or task step where it applies, rather than relying on Claude to recall it from earlier in the session.

**Mitigation already in place:** The standing rules in `operating-rules.md` include explicit bash-first and full-tree-search requirements. These are repeated here as a signal that they must be actively applied, not passively held.

---

## Flagging rule

Before making repeated or bulk requests to brand websites, evo systems (PIM, Daily Report, PO Tracker), Google Sheets, or anything while on VPN — describe what you're about to do and wait for a go-ahead. This prevents accidental rate-limiting, IP blocks, or unintended data changes.
