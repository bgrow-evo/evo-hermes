# References

All system URLs, file paths, column maps, SKU formats, and lookup tables.

---

## Key systems and URLs

| System | URL / Location |
|---|---|
| PIM (on VPN or evo_Private WiFi) | `http://172.17.70.43/` |
| PIM Image Manager (per SKU) | `http://172.17.70.43/productImages/Editor.aspx?ProductId={ParentSKU}` |
| PIM Upload Landing Page | `http://172.17.70.43/productImages/` — drag EB-SKU folders here to bulk upload |
| PIM Product Manager | `http://172.17.70.43/products/Editor.aspx?ProductId={ParentSKU}` |
| Daily Report | https://docs.google.com/spreadsheets/d/1hiQ4WNclu6j_nH-TraL3Mx5NSzQUmpQ99Cda4bVrFmI/edit |
| PO Tracker | https://docs.google.com/spreadsheets/d/1mU1zY_B_HM3Rk0SOuW_n6cQZn6v7LxBNBjxAPhdEoKU/edit |
| Merch Sheet / Merch Info Master (ski/snow/apparel) | https://evogear-my.sharepoint.com/personal/hreed_evo_com/Lists/Merch%20Sheet%20All/AllItems.aspx |
| Bike Merch Sheet | SharePoint: evogear-my.sharepoint.com — nhines_evo_com — "Bike Vendor Contact" |
| Image Change Requests | `https://evogear.sharepoint.com/sites/DigitalContentRequests` |
| evo Partner Standards (links to both PDFs below) | https://www.evo.com/partners |
| evo Content Requirements PDF (vendor image standard) | https://static.evo.com/content/evergreen/evo-content-requirements-wntr_21.pdf |
| evo Routing Guide PDF (delivery format, p.7) | https://static.evo.com/content/partners/2022-10-20_evo_routing_guide.pdf |
| Bynder (vendor portal) | Vendor image delivery; most brands don't use it |
| Imageye browser extension | https://www.imageye.net/ — use to extract images from brand DTC sites |
| Azure Fileserver (Edits) | `smb://digitalcontent.evo.local/Images/Photo_FY26/Post-Production To Edit` — **VPN or evo_Private WiFi required; not reachable by Claude's sandbox** |
| Photoshop Actions | `smb://digitalcontent.evo.local/Images/Photoshop_Templates_and_Actions/Photoshop Actions` — **VPN or evo_Private WiFi required** |
| Daily Report xlsx location | `smb://digitalcontent.evo.local/Missing_Images_and_Descriptions/` — **VPN or evo_Private WiFi required; not reachable by Claude's sandbox** |
| Local Cowork package path (Mac) | Local user-controlled folder; on this machine: `~/Documents/Claude/Cowork`. Path may vary by user. OneDrive paths are deprecated for the package itself. |

**PIM notes:** Legacy in-house system, pre-2010, no API. Requires VPN or evo_Private WiFi. Saves automatically. Images uploaded to PIM overnight go live on evo.com the following morning.

---

## Daily Report column reference

### ON HAND tab (one row per matrix value / colorway)

| Column | Field | Notes |
|---|---|---|
| A | Notes | Write your name to claim; additional notes |
| B | Status dropdown | See status list below |
| C | Parent | 6-digit parent SKU |
| D | Product Name | Use to infer brand |
| E | MatrixValue | Colorway or size value (the missing variant) |
| F | DOLR | Date of last receipt |
| G | OnHand/OnOrder | Which locations have stock |
| O | OnHand | Units on hand |
| P | OnHandValue | Dollar value on hand |
| Q | OnOrder | Units on order |
| R | OnOrderValue | Dollar value on order |

**Prioritization guidance — when scanning NEW rows for unclaimed work:** Do not rely on DOLR alone. Weigh all of the following together: DOLR (recency of receipt), on-hand quantity (col O), on-hand value (col P), on-order quantity (col Q), on-order value (col R). A row with a recent DOLR, multiple units on hand, and more on order is a stronger priority than a single-unit old receipt. Rows with no DOLR but high inventory value may still be high priority. Use judgment across all five signals.

### Status dropdown options (col B)
NEW | Searching/Processing In Progress | Vendor Images Available on DAM | Vendor Images Available on Brand Site | Order to Shoot in Studio | Ordered into Studio | All Images Uploaded to PIM | Follow-Up Required | Contacted Brand | Store-Only - Ask Buyer to Turn Off Web Display | Vendor Images Exist but Unavailable Need to Contact Brand | Needs SKU Check | Ready for Post Production | Unavailable to order | Studio Awaiting Samples | Images Available in PIM | Shooting | Awaiting SKU Check | Order for in-studio SKU check | Ordered for in-studio sku check

### ON ORDER tab

The ON ORDER tab tracks SKUs on order without images. Column structure may differ from ON HAND — verify on first use each session.

**"Ship Date" column interpretation:** The value shown is not the raw PO ship date. It is PO ship date + 10 calendar days, representing the expected arrival date at evo. An additional dock-to-stock processing period (receiving, check-in) occurs after arrival and is not captured in this column. This varies significantly by season: roughly 4 days during slow periods, up to 10+ days during peak receiving in late summer/fall ahead of winter holiday sales. When assessing urgency, treat the Ship Date value as "expected arrival" and factor in that images may need to be ready before that date to avoid a gap at go-live.

**Notes column (col A) — free text, not a dropdown.** Use to claim rows and track status. Convention: write your name when starting work on a SKU; update or append a status note when done or if leaving incomplete. Example: `Dan — in progress` or `Dan — uploaded to PIM 2026-04-28`. This column may be converted to a dropdown in the future — if so, update this entry.

**Claiming and updating:** Same intent as ON HAND col A — write your name to claim, update when complete or handing off. Because it's free text, any note can be added alongside the name.

**Calculating brand or PO value:** TotalValue (col 17) is evo's COGS — what evo paid for the inventory. To get the full value of a brand or PO arriving in a given period, sum TotalValue across all rows matching that brand name (substring match in Product Name, since there is no separate brand column — Product Name = Brand Name + Model Name) and/or PO number. Do not use OnOrderValue alone; TotalValue is the correct field for prioritization comparisons.

### Missing Images Matrix Detail tab (child SKU grain)
Access via gviz endpoint:
`https://docs.google.com/spreadsheets/d/[ID]/gviz/tq?tqx=out:csv&sheet=Missing%20Images%20Matrix%20Detail`

Column structure: Notes | EB-SKU (evoParent-Child) | Product Name | Color | MFN-Color Code (MPN) | UPC | Year | Season | PO # | PO Type | ...

Column E = MFR SKU — sort A-Z to match vendor image filenames by part number.

---

## PO Tracker column reference

| Col | Field | Notes |
|---|---|---|
| A | Status | Blank = up for grabs; Completed; Partially Completed - All Available Done |
| B | Currently Assigned To | Write your name when claiming |
| C | Last Assigned To | Move name here when done |
| D | Brand | |
| E | PO # / Sheet Link | |
| F | Go Live | |
| G | Last Asset Check Date | Orange = needs check (2+ weeks old) |
| H | Rows | Number of SKUs |
| I | Images Location | Key field — DAM, Website, Merch Sheet, link, credentials, or search instructions |

---

## SKU and image matrix reference

### SKU format
- **Parent SKU:** 6-digit number (e.g. `233512`)
- **Child SKU / EB-SKU:** `EB-[ParentSKU]-[ChildSuffix]` (e.g. `EB-233512-1001`) — always use the full 10-digit format for folder naming and PIM upload
- **Critical:** uploading with only the parent SKU sends images to the Product row, applying them to ALL variants

### Getting the child EB-SKU
The ON HAND tab shows only the 6-digit parent SKU. Go to the Missing Images Matrix Detail tab, filter by parent SKU. Any one child SKU for that colorway works for folder naming.

### Image matrix defaults by category
- Most products: Color matrix
- Skis and products where color/graphic varies by size (some snowboards, wakeboards): Size matrix
- **Warning:** Image Matrix = Size on a single-size product breaks the size selector on the PDP — use Color instead
- IT has not provided a definitive category list; always verify before uploading

### File naming accepted by PIM
- UPC: `191253685745.jpg`
- MFR SKU + color: `111222-ABC.jpg`
- evo SKU: `EB-233512-1001.jpg` (preferred)
