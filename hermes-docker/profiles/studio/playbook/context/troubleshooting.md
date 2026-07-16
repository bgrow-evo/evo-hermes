# Troubleshooting and Known Pitfalls

Known failure modes, gotchas, and operational edge cases across all workflows. Load when something goes wrong, or when starting a task that has known risks.

**How to document an issue:** Every entry should include — *First documented, Source, Confidence, Status.* Entries without metadata are unverified carry-overs and should be treated with lower confidence until confirmed. Do not add entries silently mid-task — flag as a documentation-improvement candidate first. Entries that prove inaccurate should be corrected with a note, not silently deleted.

**Confidence levels:** High = confirmed by direct observation or explicit team knowledge. Medium = plausible but not directly verified. Low / Needs validation = inferred or unconfirmed — do not act on without checking first.

**Status field:** *Confirmed* = behavior verified to still apply. *Needs re-validation* = previously observed but may have changed; do not drop the operating rule until re-tested. *Archived* = no longer applies (kept for historical context only).

**When Claude encounters a new issue or discovers an existing entry is inaccurate,** it must flag a documentation-improvement candidate per the standing rule in `operating-rules.md`.

---

## Daily Report

**Images menu not visible**
The custom 📸 Images menu hides in the "..." overflow when the Chrome window is narrow. Clicking the overflow opens the Comments panel instead. Expand Chrome to full width before opening the menu. *(Status: Confirmed. Confidence: High.)*

**Command shows no popup (consolidated)**
Script commands occasionally complete without showing a popup, or appear to error. **The Summary tab date is the authoritative success check.** If a script's Summary row already shows today's date, it completed successfully — do not re-run based on a missing popup alone. Re-run only if the Summary date is still yesterday's. Commands are safe to re-run when genuinely needed — no data is lost — but re-running unnecessarily wastes time on slow scripts. This applies to all five scripts, including Script 5 (Descriptions on Hand) which has been specifically observed completing without a popup. *(Status: Confirmed. Confidence: High. Consolidated from two prior near-duplicate entries in v11.5.)*

**ON ORDER takes a long time**
Normal — typically 30–60 seconds. If "Running script" shows with Cancel/Dismiss, just wait. *(Status: Confirmed. Confidence: High.)*

**Detail command is slow**
Normal — processes ~29,000 rows, takes 30–40 seconds. *(Status: Confirmed. Confidence: High.)*

**OAuth popup appears**
First-time only per user. Click Advanced → Go to app (unsafe) → Allow. Does not recur. *(Status: Confirmed. Confidence: High.)*

**PI Report link in Summary tab shows wrong name**
The link uses the imported spreadsheet's name. Rename the imported spreadsheet immediately after import to match the filename: `MissingImagesMatrix_And_MissingDescriptions MM-DD-YYYY`. *(Status: Confirmed. Confidence: High.)*

**File import cannot be automated**
Google Sheets' import dialog renders inside a cross-origin iframe that browser automation cannot access. Manual import is required. Eliminating this step requires either SharePoint delivery of the PI Report or an on-premises data gateway — both require IT engagement and are tracked source-side. *(Status: Confirmed. Confidence: High.)*

**Azure fileserver not reachable by Claude**
The Daily Report xlsx lives at `smb://digitalcontent.evo.local/Missing_Images_and_Descriptions/` which requires VPN or evo_Private WiFi. Claude's sandbox has no network path to this server. The file must be obtained manually by the evo team member — either from the fileserver directly, or once SharePoint delivery is set up, from SharePoint. *(First documented: 2026-04-29. Source: direct observation. Confidence: High. Status: Confirmed.)*

**CORS error when fetching Daily Report data via JavaScript**
Any JavaScript fetch to Google Sheets must run while the browser tab is on a Google domain. Fetches fail when initiated from a brand DTC site tab. *(Status: Confirmed. Confidence: High.)*

---

## Vendor image sourcing

**Brand DTC site or DAM search returns no results using evo's MFN-Color Code**
evo's MFN-Color Code is ideally the brand's MPN, but this is not guaranteed. Product data is manually entered by evo data specialists and entry consistency varies. The value may be a partial, reformatted, or approximate version of the brand's actual part number — or it may not match the brand's searchable ID at all. The correct search term may also differ between the brand's DTC site and their DAM even for the same product.

When a search fails: try product name and colorway instead. If you identify the correct search method for a specific brand, capture it as a documentation-improvement candidate — this information belongs in the Merch Info Master SharePoint free-text guidance column.

*First documented: 2026-04-25. Source: evo team member review. Confidence: High. Status: Confirmed.*

**Images below minimum resolution**
Minimum is 1500x1500px. Remove query parameters and size suffixes from the URL (`?width=300`, `_medium`, `_thumb`) to get the full resolution file. Mark Follow-Up Required if unavailable at minimum size. *(Status: Confirmed. Confidence: High.)*

**Vendor DAM images have wrong colorway despite matching MPN**
Known issue especially with goggle lenses. Cross-check against the vendor DTC site visually. *(Status: Confirmed. Confidence: Medium — periodic recurrence; reverify on specific brands.)*

**Carryover product looks the same but isn't**
Same SKU year-over-year can have a different liner, sole, graphic, or colorway. Do not assume prior-year images are correct. *(Status: Confirmed. Confidence: High.)*

---

## PIM upload

**Images uploaded to wrong level (Product row instead of colorway)**
Caused by using only the parent SKU for the folder name. The Product row applies images to all variants. Always use the full 10-digit child EB-SKU for folder naming. *(Status: Confirmed. Confidence: High.)*

**SKU doesn't appear on Missing Images Report**
Check Item Setup → Web Display. If set to None, the SKU won't appear. Buyers set this to Full to enable. *(Status: Confirmed. Confidence: High.)*

**Shared Alternate Image checkbox**
Never check this. If found checked, deselect it. Always clone detail shots instead. *(Status: Confirmed. Confidence: High.)*

**Hardbound package image does not update after component SKU image change**
When a Hardbound Package is created in the Hardbound Packages Manager in PIM, it ingests whatever product images are available for the component SKUs at that time. Later image changes to those component SKUs do not automatically push to existing hardbound packages. To update a hardbound package image, someone must manually open the Hardbound Packages Manager and reselect the radio button for the desired colorway. This process is currently handled by the Studio Manager. The Digital Content Team does not normally touch hardbound packages — this is considered a buyer/Studio Manager responsibility in PIM.

*First documented: 2026-04-25. Source: evo team member direct knowledge. Confidence: High. Status: Confirmed.*

---

## Browser automation / Cowork

**Cell edit appears to save but value reverts**
The "Saving…" indicator is not sufficient confirmation. After any automated cell edit, click the cell and verify the formula bar value. If wrong, re-enter the value and wait for Saving… to fully clear before moving on. *(Status: Confirmed. Confidence: High.)*

**Status dropdown sets wrong value**
Chip-style status dropdowns can misfire to an adjacent option when clicked programmatically. After setting any status, zoom into the formula bar to confirm the correct value. Re-open the dropdown and select the correct option if needed. *(Status: Confirmed. Confidence: High.)*

**403 error when fetching evo.com pages**
The site blocks non-browser requests. Use Claude in Chrome for browser-rendered pages. For structured data, use the Shopify product JSON endpoint (`/products/[handle].json`) instead of page scraping. *(Status: Confirmed. Confidence: High.)*

**Chrome permission popup for local relay server**
When Claude uses the relay server to download images, one "allow this site to access local services" popup appears per site per session. Must be approved by the user. Does not recur within the same session. *(Status: Confirmed. Confidence: High.)*

**OS-level dialogs (Finder, Save dialog) are inaccessible**
Cowork controls Chrome, not macOS. File pickers, Save dialogs, and Finder windows are outside what Claude can interact with. For image downloads, Claude uses the File System Access API — Claude clicks an injected button, Chrome opens a folder picker, and the user selects the destination folder once. This is the expected one manual step. *(Status: Confirmed. Confidence: High.)*

**Teams posting cannot be reliably automated via browser**
The Teams desktop app is inaccessible to Claude. Web Teams (teams.microsoft.com) is reachable but browser automation of table insertion is unreliable — the built-in table tool adds columns instead of advancing cells when Tab is used, and the Trusted Types security policy blocks HTML injection. The correct automation path is Power Automate's "Post message in a chat or channel" action, which posts formatted content including tables directly via the Microsoft Graph API. Current workaround: human copies A1:C6 from the Summary tab and pastes into the Teams compose box, adds the two links, and clicks Post. Claude should always draft content into the compose box and let the evo team member click Post — never click Post or Send on their behalf in Teams. *(Status: Confirmed. Confidence: High.)*

**Claude in Chrome extension shows no visible logged-out state**
If Claude in Chrome stops responding (tool returns "Claude in Chrome is not connected"), the extension may have been logged out of claude.ai rather than having a connectivity issue. There is no visible badge or indicator in the toolbar unless the extension icon is pinned. **Fix:** Pin the Claude extension to the Chrome toolbar so the icon is always visible. When disconnected, click the icon — it will show a login/reconnect prompt. You may need to re-authorize your account. *(First documented: 2026-05-13. Source: direct observation. Confidence: High. Status: Confirmed.)*

**Google Sheets gviz CSV endpoint triggers a file download**
Never navigate to a URL of the form `https://docs.google.com/spreadsheets/d/[ID]/gviz/tq?tqx=out:csv&sheet=...` — this triggers a file download in the browser, even when navigated to directly. To read sheet data, use the browser tab on the live sheet and interact with it directly (click tabs, use Ctrl+F, navigate to cells). *(First documented: 2026-05-13. Source: direct observation. Confidence: High. Status: Confirmed.)*

**Arc'teryx Aprimo DAM — SPA search results don't render from URL navigation**
The Aprimo DAM is a single-page application. Navigating directly to a search URL (e.g. `arcteryx.dam.aprimo.com/dam/search?q=...`) renders a blank results page. Search results only appear when initiated via the search box in the UI. **Correct approach:** click the search icon, type the search term, press Enter or click "See all results" — then press Escape to close the dropdown and see the full results page rendered behind it. *(First documented: 2026-05-13. Source: direct observation. Confidence: High. Status: Confirmed.)*

**Glob tool returns no results — OneDrive-synced Cowork package (historical)**
When the Cowork package itself was OneDrive-synced, the Glob tool returned empty results against the package folder. Notably observed after enabling "Always Keep On This Device" on 2026-05-01. The behavior appeared tied to mount resolution in cloud-synced folders. The Cowork package has since been moved to a local user-controlled folder; OneDrive paths for the package are deprecated. *(First documented: 2026-05-01. Source: direct observation. Confidence: High. Status: Archived — Cowork package no longer OneDrive-synced. Kept for historical context.)*

**Glob tool returns no results — local connected folders (needs re-validation)**
Glob has historically returned empty results against local connected folders (via `request_cowork_directory`, e.g. `~/Desktop/Editing`), separately from the OneDrive-synced package issue above. The behavior may have been a transient sandbox-bridge / mount-resolution issue, or may still apply. **Operating rule (in effect until re-validated):** use bash (`find /sessions/.../mnt/[folder]/ -type f` or `ls`) as the primary method for directory inspection when accuracy matters. **At task startup, always use bash to find the most recent handoff.** Glob may be used as a secondary check after bash verification. **Re-validation needed (2026-05-13):** with the Cowork package now local-only, test whether Glob is reliable on connected local folders. If verified reliable, this entry can be narrowed or archived. Until then, bash-first remains the operating rule. *(First documented: 2026-04-29. Source: direct observation. Confidence: Medium. Status: Needs re-validation.)*
