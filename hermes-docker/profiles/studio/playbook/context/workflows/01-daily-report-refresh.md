# Daily Report Refresh

Load when running the morning Daily Report refresh. This workflow covers the refresh process only — running the import and scripts, verifying output, and posting to Teams. This is a dedicated morning task performed by one evo team member.

> **Scope boundary — this is Workflow #1 only.**
> This workflow ends when the Daily Report is refreshed and posted to Teams.
> **Working off the report** (prioritizing rows, claiming SKUs, sourcing images) is Workflow #2 — start of `02-vendor-image-sourcing-and-skuing.md`. Do not begin that work in a Workflow #1 session without explicit confirmation.
> If the report has already been run today, a request to "find something to work on" or "find a priority on the report" means opening the existing report and scanning for unclaimed NEW rows — not running the refresh again.

**Workflow status:** Production — confirmed working; tested repeatedly. Manual steps (file import, Sheet ID, OAuth) are unchanged; Claude automates from CONFIG paste onwards.

---

## What the Daily Report is

A master Google Sheet that tracks missing product images and descriptions across On Hand, On Order, and Dropship inventory. Updated each morning by running five Google Apps Script sync functions against a freshly imported Excel export from the PI Report system. Output is the team's daily work queue.

---

## Step-by-step execution

### Before starting
- Expand Chrome to full width — the custom 📸 Images menu hides in "..." overflow on narrow windows, and clicking that area opens Comments instead
- Have the xlsx file ready in your Cowork folder

### Import the xlsx (manual)
- File is at: `smb://digitalcontent.evo.local/Missing_Images_and_Descriptions/MissingImagesMatrix_And_MissingDescriptions MM-DD-YYYY.xlsx`
- **VPN required:** The Azure fileserver (`digitalcontent.evo.local`) is only reachable via VPN or evo_Private WiFi from your local machine. Claude's sandbox has no network path to this server and cannot access the file directly.
- Import via File > Import > Upload > Browse in a new blank Google Sheet
- **Do NOT sort On Order data**
- **Do NOT copy over On Hand statuses or notes from the previous day**
- Rename the new spreadsheet immediately to match the filename — the PI Report link in the Summary tab uses this name
- **Set sharing permissions:** After importing, open Share → set "Anyone with the link" to **Editor**. This ensures the team can edit the report.
- Why manual: Google Sheets' import dialog renders inside a cross-origin iframe that browser automation cannot access. VPN access from Claude's sandbox is also unavailable.

### Get the Sheet ID (manual)
- Copy the Sheet ID from the imported spreadsheet's URL

### OAuth (first time only)
- If Google shows "This app isn't verified" → Advanced → Go to app (unsafe) → Allow
- One-time per user, does not recur

### Paste Sheet ID
- Navigate to CONFIG tab, paste Sheet ID into B2

### Run all five commands
Open the 📸 Images menu and run in order, waiting for each popup before proceeding:
1. Check new ON HAND images
2. Check missing images ON ORDER *(slowest — up to 60 seconds, normal)*
3. Update Missing Images Matrix Detail *(processes ~29,000 rows, 30–40 seconds, normal)*
4. Dropship check
5. Descriptions on Hand

After each popup: dismiss it, then run the next command. If a command errors or shows no popup, **check the Summary tab first** — if that row already shows today's date, the script completed successfully and does not need to be re-run. Only re-run if the Summary date is still yesterday's. No data is lost on retry if re-running is genuinely needed.

### Verify and post
- Navigate to Summary tab — all five rows should show today's date with checkmarks in column D
- Navigate to teams.microsoft.com → Teams → Digital Content → Report channel
- **Draft the post and show it to the evo team member for review before posting. Always type content into the Teams compose box and let the evo team member click Post — never click Post or Send on their behalf in Teams.**
- **Table format:** Copy cells A1:C6 from the Summary tab — this preserves the table format and green "(new)" text. Typing the content manually does not replicate the formatting. Claude can navigate back to the Sheet and select the cells; the evo team member pastes into Teams.
- After the table, add:
```
⭐Daily Report: https://docs.google.com/spreadsheets/d/1hiQ4WNclu6j_nH-TraL3Mx5NSzQUmpQ99Cda4bVrFmI/edit
PI Report: [link to today's imported PI Report spreadsheet]
```
- This is a new top-level post, not a reply to yesterday's thread.

---

## Data structure

### Tab grain
- **ON HAND tab** — one row per Matrix Value (almost always color, occasionally size). Each row = one colorway. Exception: some products like certain snowboards have color vary by size.
- **Missing Images Matrix Detail tab** — child SKU grain. Use to get: (1) full 10-digit EB-SKU for folder naming, (2) MPN (column: MFN-Color Code) and UPC for matching vendor images.
- Access Detail tab via gviz endpoint: `gviz/tq?tqx=out:csv&sheet=Missing%20Images%20Matrix%20Detail`

---

## How the scripts work (for troubleshooting)

**checkNewOnHandImages:** Key = Parent + Product Name + MatrixValue. New rows: writes NEW to col B. Existing rows: syncs inventory columns only — never touches col B or col A. Dropped rows: greyed then batch-deleted. Sorts by Product Name after.

**checkMissingImagesOnOrder:** New rows: writes `new (M/dd)` to col A + green background (clears next day). Ship dates synced. Sorted by ship date. Filtered by cutoff month (CONFIG!B4).

**updateMissingImagesMatrixDetail:** Full clear-and-rewrite each run. New rows: `new (M/dd)` in bold green text in col A. Dropped rows deleted immediately. Sorted by Go Live Date then PO #.

**dropshipCheck:** Col B (Assigned To) never touched. New rows: `new (M/dd)` in green text. Dropped rows deleted immediately.

**checkDescOnHand:** Tracks missing descriptions. Col B (manual notes) preserved. New rows: `new (M/dd)` in green text. Sorted by date of last receipt.

**PO Tracker auto-stamp:** Runs on edit. When col A (Status) changes to Completed on SSA, Bike, Hardgoods, or Softgoods tabs, stamps today's date in col O (Completed Date) if empty.

**Check for updates button (individual PO sheets):** Reconciles the static PO sheet snapshot against current reality, removing SKUs that already have images. Always run first when opening a PO sheet.

---

## Automation gaps and options

**What Claude can automate today:** Steps 4–6 (CONFIG paste, all five commands, popup handling, Summary verification, Teams post formatting).

**What requires manual action:**
1. File import — cross-origin iframe blocks browser automation
2. OAuth — one-time, OS-level popup

**Options to eliminate manual steps:** ask IT whether the PI Report can export directly to SharePoint, or whether they can install the on-premises data gateway. Either eliminates the manual import step. (Full strategic analysis is maintained source-side; not part of the deployable package.)

**Teams posting note:** Cannot be automated via the Teams desktop app. Browser automation via teams.microsoft.com works for navigation and opening the compose box, but inserting a properly formatted table reliably is not achievable via typing or Teams' built-in table tool — Tab creates new columns instead of exiting the table, and the Trusted Types security policy blocks HTML injection.

**Recommended automation path:** Use the Microsoft Teams API via Power Automate. Power Automate has a native "Post message in a chat or channel" action that posts rich formatted content — including proper tables — directly via the Graph API, no browser required. Once Power Automate is in use for the Daily Report import (SharePoint delivery path), the Teams post becomes a single additional step in the same flow at zero extra complexity. This is the correct long-term solution.

**Current workaround:** Human posts manually. The evo team member should copy cells A1:C6 from the Summary tab (preserves table format and green text), paste into Teams compose box, then add the two links below and click Post.
