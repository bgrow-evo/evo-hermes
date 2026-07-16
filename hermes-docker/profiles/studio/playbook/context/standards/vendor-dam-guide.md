# Vendor DAM Guide

Tips, quirks, and search strategies for specific vendor DAMs. Add entries as new vendors are tested.

**Always check the Merch Sheet before accessing any vendor DAM** — this is required default behavior, not optional. DAM links and passwords change frequently. The Merch Sheet (Merch Info Master) is the live source of truth for DAM URLs, login credentials, and rep contacts. This guide records what was found previously and is a secondary reference only.

**How to find a brand in the Merch Sheet:**
- Navigate to https://evogear-my.sharepoint.com/personal/hreed_evo_com/Lists/Merch%20Sheet%20All/AllItems.aspx
- The list is paginated/virtualized — use JavaScript DOM search to find the brand row rather than scrolling
- DAM link is a clickable hyperlink in the DAM Links column — extract the `href` via JavaScript rather than reading the display text
- Credentials are in the Login column alongside the DAM link

*Last updated: 2026-05-13*

---

## Arc'teryx — Aprimo (arcteryx.aprimo.com)

**DAM platform:** Aprimo
**Login:** mfields@evo.com — see Merch Sheet for password (confirmed 2026-05-13 via Merch Sheet — always verify in Merch Sheet before use, as passwords may change)
**DAM URL:** https://arcteryx.aprimo.com/login/Account/Login
**Access via:** Merch Sheet → ArcTeryx row → DAM Links → "Arc DAM Product/Marketing" hyperlink

**Login method:** Use JavaScript form fill rather than clicking into fields — the click-then-type approach has intermittently failed due to tab detach timing. Example:
```js
var u = document.querySelector('input[name="Username"]');
var p = document.querySelector('input[name="Password"]');
var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
setter.call(u, 'mfields@evo.com'); u.dispatchEvent(new Event('input', {bubbles:true}));
setter.call(p, '<PASSWORD-FROM-MERCH-SHEET>'); p.dispatchEvent(new Event('input', {bubbles:true}));
document.querySelector('button[type="submit"]').click();
```
Then click the LOG IN button directly if the JS submit doesn't fire.

**SPA search behavior:** The Aprimo DAM is a single-page application. Navigating directly to a search URL renders a blank results page. Always initiate searches via the search icon in the UI — type the term, press Enter, then press Escape to close the dropdown and reveal the full results page. See troubleshooting.md for details.

**Search strategy:**
- Search by base MPN + color code (e.g. `X000010155 001704`) for exact results — 7 items or fewer, easy to work with
- Search by product name (e.g. `Sylan 2 Shoes`) for a broader result set when you don't have the MPN yet
- Do NOT use the full evo MPN with color suffix — returns no results
- Arc'teryx uses internal color codes in filenames (e.g. `001704`) that do not match evo's color suffix
- Confirm match: base MPN in filename + colorway name in filename = correct asset
- **"Men" or "Women" is explicit in the filename** — use this to confirm gender when parent SKU has both

**File naming convention:**
`[Season]_[BaseMPN]_[ArcColorCode]_[ProductName]_[Color]_[Background]_[Market]_[View]_[Modifier].png`

Example: `S26_X000009623_022658_Granville Shoulder Bag_Sea Salt_Neutral_NA_Front-View_white-bg.png`

**Background versions available:**
- `_white-bg` — already on 255 white background (preferred)
- `_Transp` — transparent background, clippable to white (use if no white-bg exists)
- `_Neutral` — natural/studio background (skip if white-bg or Transp exists)

**Asset types:**
- Mannequin — product on mannequin, In Perpetuity rights
- On-Model — lifestyle/on-model shots, Limited Rights Access

**Lowres versions:** Aprimo includes `_Lowres` variants of every file — always skip these, use full-res only.

**Download method:** Use basket → select all for each colorway search → Add to Basket → basket icon → Download All As → Original. Download notification appears within ~30 seconds. Click DOWNLOAD in notification panel — zip goes to default Downloads folder.

**Selective extraction from zip:** Arc'teryx zips contain all versions (white-bg, Transp, Neutral, Lowres). Extract selectively using bash unzip with filename patterns rather than unzipping everything. 722MB zip for 4 colorways (81 files) — full unzip exceeds 45s bash timeout.

**Season codes:** S26 = Spring 2026, F25 = Fall 2025. Heliads in this PO were F25 assets; Granville bags were S26.

---

## Amer Sports DAM (shared: Atomic, Armada, Arc'teryx apparel)

**Login:** content@evo.com — see Merch Sheet for password
**Note:** Arc'teryx bags use Aprimo above; other Amer Sports brands use the shared Amer Sports DAM

---

## Season Equipment

**Full brand name:** Season Equipment (product names appear as "Season [Model] Skis" in the Daily Report)
**DAM:** Unknown — not yet sourced. Check Merch Sheet for DAM link or contact info.

---

## Curious Creatures

**Full brand name:** Curious Creatures (product names appear as "Curious Creatures [Model]" in the Daily Report)
**DAM:** Unknown — not yet sourced. Check Merch Sheet for DAM link or contact info.

---

## Mervin DAM (Bent Metal, Lib Tech, GNU)

**Login:** mervindealer — see Merch Sheet for password

---

## Sunski — evo Bynder (assets.evo.com)

**Status:** Dead end as of 2026-04-28
**Issue:** Merch Sheet entry points to a PDF on evo's Bynder (assets.evo.com) titled "wholesale-media" / `sunski-wholesale-media-assets.pdf`. This PDF was uploaded in October 2021 and contains links to product/lifestyle images — all links are dead/outdated.
**Workaround:** Try Sunski DTC site (sunski.com — confirmed Shopify). Note: closeout colorways are often not present on current DTC site.
**Elastic login:** jstreby@evo.com — see Merch Sheet for password (not yet tested)
**Recommendation:** Hunter Reed should update the Merch Sheet entry for Sunski with a current DAM link or note that assets must come from Elastic or brand contact.

---

## evo Bynder (assets.evo.com) — internal portal

**Purpose:** evo's own internal brand portal, not a vendor DAM. Contains evo brand assets, campaign imagery, lifestyle photos. Some vendors upload PDFs or asset guides here.
**Search behavior:** SPA — URL keyword params are not picked up on load. Must type into search box and submit. Use Document filter + brand name keyword to find vendor-uploaded PDFs.
**Note:** "Searching for Sunski PDF" typed directly into the search box is the correct approach — pulled up the one result immediately.
