# PIM Upload and Image Ordering Workflow

Load after images have been sourced and processed, when uploading EB-SKU folders to PIM, ordering images, auditing colorways, or marking work complete.

**Workflow status:** Beta — core upload and image ordering confirmed working for bags category (2026-04-29, 4 SKUs). Not yet tested across all category types, hardgoods, matrix products, packages, or edge-case image-order scenarios.

**Position in pipeline:** Runs after image editing and processing. Images uploaded to PIM overnight go live on evo.com the following morning.

**PIM notes:** Legacy in-house system, pre-2010, no API. Requires VPN or evo_Private WiFi. Saves automatically.

---

## Pre-upload QA (human validation required before upload)

**Folder access — required step:** Claude cannot access local folders (e.g. `~/Desktop/Editing/...`) without explicit permission each session. Before running any file inspection or upload, always call `request_cowork_directory` with the Output folder path and wait for the evo team member to approve. Do not assume the folder is accessible — always request it explicitly, even if it was connected in a prior session. Example path: `~/Desktop/Editing/2026-04-28/ArcTeryx/Output`. Unless the folder has already been added to the evo team member's saved allowed folders in Claude Desktop (exact feature name TBD — update this note when confirmed), this prompt is required every session.



Before uploading to PIM, Claude lists all files in each EB-SKU Output folder via bash and presents an audit list for human review. Upload does not proceed until the evo team member confirms.

**Claude's output for each SKU:**
- EB-SKU and product name + color
- Local folder path
- Numbered file list in order, with angle/shot type annotation for each file
- Confirmation that files are JPGs and expected resolution (1500×1500)
- Any flags — unexpected filenames, missing angles, sequence gaps, wrong file count

**Human reviews and confirms** the list looks correct before upload proceeds. If anything looks off, fix files locally before uploading.

**If visual inspection is needed (backup approaches, in order of speed):**
1. Open the Output folder in Finder — fastest, no tools needed
2. Use Quick Look in Finder (spacebar) to preview images in sequence
3. Ask Claude to open a local browser preview via browser automation

Filename review is sufficient when files came through the standard editing/processing step with numeric prefixes. Visual inspection is a fallback for ambiguous filenames or suspected editing errors.

---

## Upload to PIM

- Navigate to `http://172.17.70.43/productImages/` (the landing page, not the per-SKU editor)
- Drag 5–10 EB-SKU folders from Finder directly onto the page
- **Folder names must be the full 10-digit EB-SKU** (e.g. `EB-233512-1001`)
- Why: uploading with only the parent SKU (e.g. `EB-233512`) sends images to the Product row, applying them to ALL variants
- Watch for green confirmation box (bottom right)
- **After upload, refresh the PIM home page to confirm the parent SKUs appear in the queue.** The home page does not auto-refresh — it may require a manual reload or clicking into the window to show newly uploaded SKUs. Claude can take a screenshot to confirm without asking the evo team member.
- **The PIM home queue shows one row per parent SKU**, regardless of how many colorways were uploaded. evoTrip SKUs frequently appear in the queue because that team does not click Save — ignore them. PIM saves and goes live regardless; the SKUs just linger in the queue until someone adjusts something or clicks Save for them. Digital Content periodically clears them out as a courtesy. Confirm the expected parent SKU IDs appear before proceeding to ordering.
- **Wait approximately 1 minute before clicking into any SKU** — PIM needs time to process the folders and render image thumbnails. Clicking in too fast will result in broken thumbnails. Wait longer if uploading a large number of images or if PIM appears backlogged.
- **Broken thumbnails cannot be fixed by a standard page refresh.** You must clear cache and hard reload via Chrome Developer Tools (DevTools → Network tab → right-click Reload → "Empty Cache and Hard Reload"). Do not click into SKUs until confident processing is complete.

**Why folder drag-and-drop is the only viable upload method:**
PIM has a `fileUpload` file input that accepts multiple individual files, but it only works if the filename is exactly the EB-SKU (e.g. `EB-263894-1007.jpg`). This cannot accommodate multiple images per SKU — duplicate filenames are not possible. Our standard multi-image naming convention (`EB-263894-1007_01-Front-View.jpg` etc.) does not work with the file input. Folder drag-and-drop is the only method that supports our full workflow.

**Claude cannot perform the folder drag-and-drop** — this is an OS-level action originating from Finder, outside the browser. The evo team member must drag the folders. Claude handles all steps after upload (navigation, image ordering, saving).

---

## Order images in PIM

- Drag images to correct order per category rules in `standards/pim-category-ordering.md`
- Most interesting colorway to top of image matrix; black/gray/white to bottom

**Confirm image order with the evo team member before moving to the next colorway.** Do not proceed to the next colorway row or click Save until the current colorway's order has been reviewed and approved.

### Primary color and Pattern dropdowns

Each colorway row has a **Primary** color dropdown and a **Pattern** dropdown. These feed the PLP filters on evo.com and must be filled out for any colorway that doesn't already have them set.

**Always check existing colorways** on the parent SKU first to see what values are already set — use those as a consistency reference before filling in new colorways.

**Primary color options:** Black, Blue, Brown, Gold, Gray, Green, Khaki, Orange, Pink, Purple, Red, Silver, White, Yellow

**Pattern options:** Stripe, Plaid, Solid, Graphic Print, All Over Print, Color Block, Camo

Select based on visual inspection of the product. When in doubt, confirm with the evo team member before selecting.

### Colorway row ordering (matrix row order)

The order of colorway rows in PIM determines the default variant shown on the PLP. The top row is the default; if that colorway is out of inventory, the next row shows instead.

**Rules:**
1. **New colorways go to the top** — drag newly uploaded colorway rows above all existing colorways. Among multiple new colorways, put the brightest, most eye-catching, or most unique one at the very top.
2. **Product row is always 2nd to last** — just above Deleted. Images in the Product row are shared across ALL colorways and appear BEFORE images in any color row below the Product row. If Product row is above a color row, those shared images show first for that color — which is usually wrong. Always drag Product row to 2nd to last position.
3. **Deleted row is always last** — never drag anything below Deleted except images being deleted.
4. **New colorways always appear below the Product row** when first created in PIM. They must be dragged up above all existing colorways as part of the ordering step.

**⚠️ CRITICAL — PIM saves every action instantly and automatically:**
- Every drag or move commits immediately — there is no undo
- The Save button does NOT gate commits — it is not functioning as designed (bug report filed with IT)
- Clicking Save is still best practice — it returns you to the home page and clears the SKU from the uploaded queue
- If you open a SKU and don't touch anything → it stays in the uploaded queue
- If you open a SKU and move anything → it drops off the queue automatically, whether or not you click Save
- **Never make a move in PIM unless you are certain it is correct**

---

## Mark complete and clean up

- On-hand Daily Report: set col B to "All Images Uploaded to PIM"
- PO Tracker: set col A to "Completed"; move name from col B to col C

**Clean up intermediate files after confirmed PIM upload:**
- Source zip files from vendor DAMs (e.g. the Aprimo download zip) can be deleted once PIM upload is verified and images are live or confirmed queued
- Delete via bash `rm`; call `allow_cowork_file_delete` first if permission is needed
- Do not delete EB-SKU source folders until PIM upload is confirmed — keep them as a recovery fallback until images are verified live

**Close any remaining browser tabs** opened during this workflow (DAM sessions, PIM image editor tabs) once work on a batch is complete.

---

## Hardgoods — image matrix set to Size

When the matrix is Size (e.g. skis):
1. Drop parent EB-SKU folder → images land in Product field
2. Duplicate main image for each size → drag to each size field
3. Move Product bar to the very bottom
4. Verify detail image order in Product field
5. Save

---

## PIM best practices checklist

- [ ] All images dropped (front, side, back, details)?
- [ ] Main image has 255 white background?
- [ ] Correctly cropped per PIM Photo Guide for this category?
- [ ] On-model images non-rec (except evo Brand, Oyuki, and unisex imagery — those are full rec for all images)?
- [ ] Unisex apparel: all models included; main features multiple models if available?
- [ ] Images in correct order per category?
- [ ] Image matches colorway description in PIM?
- [ ] No 3D rendered, vector illustration, or tech pack imagery? (Exception requires manager approval)
- [ ] Templates used where required (skis, snowboards, ski poles, skateboards/longboard completes, surfboards, wakeboards, wakesurf, SUP boards)? Template hidden in final image?
- [ ] For skis/snowboards that vary by size and color — does each size/color combination have its own image?
- [ ] Detail images cloned (NOT Shared Alternate Image)?
- [ ] Correct image matrix selected?
- [ ] Most interesting colorway at top; black/white/gray at bottom?
- [ ] All images associated before end of day?
- [ ] When uploading a new colorway — audited all existing colorways on this parent SKU?

---

## Image change requests

When an issue requires re-editing (wrong crop, wrong color, needs background removal):
1. Go to `https://evogear.sharepoint.com/sites/DigitalContentRequests`
2. Photo Request → Image Change Request → +New
3. Fill in SKU, issue category, specific notes → Save

Fix directly in PIM (no ticket needed) if the issue is only reordering or deleting images.
