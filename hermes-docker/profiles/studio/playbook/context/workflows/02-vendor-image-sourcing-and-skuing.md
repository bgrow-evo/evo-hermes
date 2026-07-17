# Vendor Image Sourcing and SKUing Workflow

Load when identifying work, claiming rows or POs, locating vendor images, matching images to SKUs/colorways, creating EB-SKU folders, or downloading source images.

**Workflow status:** Beta — initial test successful; more testing in progress across brands and scenarios.

**Also load:** `standards/image-standards.md`. Load `context/cowork-tool-limitations.md` if using browser automation or the local relay server.

---

## Identify work

**From PO Tracker (preferred starting point for On Order / Dropship):**
- Open PO Tracker — pick POs with blank status in col A (up for grabs)
- Check col I for asset location (DAM, Website, Merch Sheet, direct link, credentials)
- Check in with Digital Asset Coordinator for priorities, embargoes, or side projects
- Check POs with orange-highlighted Last Asset Check Date (2+ weeks old)
- On individual PO sheets: click "Check for updates" button in cell A1 if present — reconciles static snapshot against current reality, removes already-completed SKUs. Always run first.

**From Daily Report (On Hand stragglers):**
- ON HAND tab → scan ALL rows, not just NEW status. The goal is to find anything unclaimed and workable.
- **Skip:** status = "Follow-Up Required" (assets known unavailable or already attempted)
- **Skip:** status = "Store-Only - Ask Buyer to Turn Off Web Display"
- **Skip:** status = "Searching/Processing In Progress" (already claimed by someone)
- **Skip:** rows with a name already in col A (claimed)
- **Work:** everything else — NEW or any other status with no name in col A and no blocking flag
- Write your name to claim, change status to Searching/Processing In Progress
- When re-assigning rows from another team member: after editing col A, click the cell and verify the name in the formula bar — Google Sheets edits via browser automation can fail to save if the session closes before the write completes

**From Daily Report (On Order tab):**
- ON ORDER tab → col A is free text (not a dropdown) — write your name to claim when starting work on a SKU
- Update col A with a status note when done or if leaving incomplete (e.g. `[your name] — uploaded to PIM YYYY-MM-DD`)
- The column may be converted to a dropdown in the future — check references.md if behavior changes

**Prioritizing ON HAND work:**
Do not rely on DOLR alone. Weigh all five signals together:
1. **DOLR** (col F) — recency of receipt; newer = higher urgency
2. **On-hand quantity** (col O) — more units sitting without images = more urgent
3. **On-hand value** (col P) — higher dollar value on shelf = higher urgency
4. **On-order quantity** (col Q) — more units incoming = compounding urgency
5. **On-order value** (col R) — total dollar exposure across current + incoming stock

A row with a recent DOLR, multiple units on hand, and more on order is a stronger priority than a single-unit old receipt. A row with no DOLR but high inventory value may still be a priority. Use judgment across all five signals, not just DOLR.

Also:
- Skip items with "Follow-Up Required" and existing notes (already tried and flagged)
- Skip "Store-Only - Ask Buyer to Turn Off Web Display" items
- Focus on NEW items with no name in col A (unclaimed)

**Ski package SKUs — flag before claiming:**
Product names containing "Skis + [Brand] Ski Bindings" (e.g. "Blizzard Black Pearl 97 Skis + Look Pivot 12 GW Ski Bindings") are ski package SKUs — skis physically pre-mounted with bindings. These are NOT standard single-product rows. Sourcing requires finding images for both the ski and the binding and compositing them for the specific mounted combination. Do not claim a ski package SKU without assessing the sourcing approach first.

**Ski package SKUs vs. hardbound packages — key distinction:**

- **Ski package SKUs** — skis sold pre-mounted with bindings. Ski bindings are drilled into ski bases — once mounted, the ski and binding are a single inseparable unit. These products get their own dedicated parent SKU in the catalog. Image sourcing requires finding images for both the ski and the binding and compositing them for the specific mounted combination. Recognition pattern: product name contains "Skis + [Brand] Ski Bindings."
- **Hardbound packages** — programmatically created in PIM's Hardbound Packages module by combining pre-existing individual SKUs. No physical mounting; the component products already exist in the catalog independently. Can include various combinations (e.g. snowboard + bindings, goggles + helmet). Distinct from ski package SKUs in both physical form and catalog structure. Handle according to standard SKU/image workflow.

**Updating status in bulk:**
The status column uses dropdown chip formatting. Clicking a chip opens the dropdown editor rather than selecting the cell. To bulk-update:
- Use Edit > Find and replace (Cmd+Shift+H) to replace one status value with another across a range
- Or use keyboard arrow keys to select cells without triggering dropdowns, then paste

---

## Set up folder structure

**Connect the Editing folder first.** All source images and EB-SKU folders live on the editor's local machine. Before creating any folders or downloading any files, confirm the Editing folder is connected. The default path is `~/Desktop/Editing` unless the editor uses a different location — ask if unknown. If not already connected, use `request_cowork_directory` with that path. This must happen before the Pull images section or the file system won't be accessible.

Folder structure is **per-editor preference** — no single required convention across the team. When Claude creates folders, ask the editor which structure they prefer first.

Preferred pattern:
```
YYYY-MM-DD/
  [BrandName]/
    Original/
      EB-XXXXXX-XXXX/    ← source/vendor images; one folder per colorway
    Output/
      EB-XXXXXX-XXXX/    ← Photoshop batch output; one folder per colorway
```

"Original" sorts before "Output" alphabetically, which makes the brand folder easy to navigate. If the editor already uses "Input" instead of "Original," keep whichever is established — the key is one consistent term.

Optional variation when working On Hand and On Order on the same day:
```
YYYY-MM-DD/
  On Hand/[BrandName]/Original/EB-XXXXXX-XXXX/
  On Order/[BrandName]/Original/EB-XXXXXX-XXXX/
```

All editing folders live on the editor's **local machine** — NOT on OneDrive or any shared drive. Never download source images to `Cowork/work/Editing/` — vendor image files are too large for OneDrive storage. Always download directly to `~/Desktop/Editing/` (or the editor's local equivalent).

---

## Pull images

### Source priority
**Always check the Merch Sheet first — even for known brands.** DAM links change frequently. Arc'teryx alone has changed DAMs multiple times. Never go directly to a DAM URL from memory or from the vendor DAM guide without first confirming the current link in the Merch Sheet. The vendor DAM guide records what was found previously — the Merch Sheet is the live source of truth.

**Headless/unattended runs (Hermes scheduler):** the Merch Sheet is a SharePoint list; a browser hits Microsoft sign-in under the scheduler. Read it via Graph as hermes-ai instead: `skills/studio-daily-pipeline/scripts/read_merch_sheet.py` (`--columns` to inspect, `--filter <brand>` for a brand's rows). A 403 means hermes-ai lost read access to the list — record as a blocker, don't retry. The browser is still used for the DAM sites themselves, with the URL + credentials taken from the sheet output.

**On Hand stragglers:**
1. Vendor DAM — check Merch Sheet DAM Links column for URL (always a clickable hyperlink — click it, don't try to parse the URL from text) and Login column for credentials
2. Brand DTC site — only if it's the brand's own site, not a third-party retailer; Shopify only — see JSON method below

**PO Tracker:**
- Check col I for asset location; credentials may be in col I directly

**Closeout POs:** Closeout colorways are systematically harder to source — vendors deprioritize updating DAMs and DTCs for discontinued product. Flag early if assets aren't found.

### Finding images on brand DTC sites
**Confirm platform before attempting JSON method.** The `/products/[handle].json` endpoint is Shopify-specific — check the site footer or page source to confirm Shopify first. Non-Shopify brands (Magento, custom builds, BigCommerce, enterprise platforms) do not have this endpoint.

Shopify brand sites expose structured product data at `/products/[handle].json`. This gives image URLs, variant/colorway mappings, and metadata in one clean request — no page scraping, no 403 risk. Use this as the first approach for confirmed Shopify brand sites.

For sites without accessible JSON:
- Use Imageye browser extension (shows highest resolution first); filter by product name
- Get full resolution: open image in new tab, remove query params after file extension (e.g. `?width=300`), remove size suffixes (`_medium`, `_thumb`)
- Minimum: 1500x1500px; mark Follow-Up Required if unavailable

**Using evo's MPN to search vendors:**
evo's MPN (MFN-Color Code column) is entered manually and does not directly correspond to the brand's own part number format. Do not search vendor DAMs or DTC sites using evo's MPN as-is — it will often return no results.

Instead, use it as a starting point: examine a few actual files from the brand to identify their naming pattern, then determine which characters from evo's MPN (if any) map to the brand's identifier. For example, the brand's internal code might be a subset of evo's MPN — you may need to strip leading or trailing characters to find the matching segment. Some brands use a completely different numbering system and the MPN is not useful for DAM search at all.

**Finding the child EB-SKU / MPN in the Matrix Detail tab:**
The Missing Images Matrix Detail tab contains one row per child SKU. Search by "EB-[ParentSKU]" (e.g. "EB-276695") to find all child rows for a parent. **Important:** this tab has row groups that may be collapsed by default. If a Ctrl+F search returns 0 results for a SKU that clearly exists in the ON HAND tab, the rows are grouped/hidden — the find function only searches visible rows in Google Sheets. Expand grouped rows by clicking the "+" expand button on the left side of the row number bar before searching. *(First documented: 2026-05-13. Confidence: High.)*

**Search strategy:**
1. Look at real files or search results from the brand to understand their naming convention
2. Identify which portion of evo's MPN (if any) maps to the brand's code
3. Search by that derived code + colorway name, or by product name + colorway if no MPN mapping exists
4. Confirm colorway match using UPC as backup
5. Product name search is a fallback — verify season carefully to avoid wrong-year assets

### Image download workflow (Cowork browser automation)
When Claude downloads images from a brand's website:
1. Claude opens the brand product page in Chrome and reads the product JSON (`/products/[handle].json` on Shopify)
2. Image URLs and variant/colorway mappings are extracted from the JSON — one clean request, no page scraping
3. MPN and UPC from the product JSON are cross-checked against the Missing Images Matrix Detail tab to confirm correct colorway before downloading
4. Claude injects a button onto the page and clicks it via browser automation
5. Chrome opens a folder picker — the user selects the destination folder (e.g. `Desktop/Editing/YYYY-MM-DD/[Brand]`) once
6. JavaScript fetches each image from the brand CDN and writes it directly to the selected folder, creating EB-SKU subfolders automatically
7. Claude verifies all files landed correctly via bash before marking the step done

File naming: `01_BrandName-ProductName-Color-1.jpg` — numeric prefix preserves brand's original image order; original brand filename preserved after prefix.

### Image selection rules (applies to all brands, all products)

**Background priority — always apply in this order:**
1. White background (`_white-bg`, `255 RGB`, already on white) — preferred
2. Transparent background (`_Transp`, clipped, can be placed on white) — use if no white-bg exists
3. Natural / neutral background — only if no white or transparent version exists for that view

**Main image rule:** The main image (front or front-angle shot) must be on a white background for PIM. If the vendor provides a white-bg version, use it. If not, background removal is required for the main image only.

**Duplicates:** When a DAM provides multiple background versions of the same shot, download selectively — do not download all versions. Skip Lowres, skip neutral background where white-bg or Transp exists. If bash selective extraction is needed, use zip filename patterns to extract only the preferred versions.

**Deleting unwanted files:** Use bash `rm` to delete files. If it fails with "Operation not permitted", call `allow_cowork_file_delete` with the file path — user approves the permission prompt once per folder per session, then deletion works normally. No manual workaround needed.

**After download:** Set the Daily Report status (col B) to **"Vendor Images Available on Brand Site"**. This is the correct status after images are sourced from a brand's DTC site and downloaded, before Photoshop batch and PIM upload.

**Before processing — confirm processing method.** After images are sourced and downloaded, always ask the evo team member: "Do you want to run Photoshop batch processing on these, or should I process them in this session?" Do not assume. Processing in Cowork (Python/Pillow) is faster for this session; Photoshop batch gives the team member direct control and visibility. The team member decides.

**Close browser tabs when done.** When a DAM session or brand DTC tab is no longer needed, close it. Don't leave vendor DAM windows open after sourcing is complete — close the tab before moving on to the next step. Claude can only close tabs it opened in the current session — tabs from a prior session must be closed manually in Chrome.

See `context/cowork-tool-limitations.md` for full technical details and fallback relay server approach.

### Mark unavailable
- On-hand Daily Report: set status to Follow-Up Required
- PO Tracker: mark unavailable in the sheet

---

## Getting the child EB-SKU for folder naming

The ON HAND tab has only the 6-digit parent SKU. Go to the Missing Images Matrix Detail tab (gviz endpoint in `references.md`), filter by parent SKU. Any one child SKU for that colorway works for folder naming.

Format: `EB-[ParentSKU]-[ChildSuffix]` e.g. `EB-233512-1001`

**Critical:** uploading with only the parent SKU sends images to the Product row, applying them to ALL variants. Always use the full 10-digit child SKU.
