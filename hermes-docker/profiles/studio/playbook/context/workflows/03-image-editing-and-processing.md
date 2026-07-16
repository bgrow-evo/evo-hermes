# Image Editing and Processing Workflow

Load when processing sourced images before PIM upload.

**Workflow status:** Beta — Python/Pillow shell-based processing confirmed working (2026-04-29) for clean-source vendor images (white-bg PNG or transparent RGBA). Confirmed operations: per-edge bleed detection, tight crop, white background flatten, resize to 1500×1500 canvas, JPG quality 95 output, thumbnail generation for visual inspection, and numeric-prefix file renaming. Complex clipping (non-white, non-transparent source backgrounds) still routes to manual Photoshop post-production. Photoshop automation via Cowork is Alpha — untested.

**Position in pipeline:** Runs after vendor image sourcing and before PIM upload.

**Connect the Editing folder first.** Source images live on the editor's local machine. Before doing any work, confirm the Editing folder is connected. The default path is `~/Desktop/Editing` unless the editor uses a different location — ask if unknown. If not already connected, use `request_cowork_directory` with that path. Never work from a Cowork working folder — vendor image files are too large for shared storage.

**Folder structure:** Source images live under `Original/EB-XXXXXX-XXXX/` within the brand's daily folder. Photoshop batch output goes to `Output/EB-XXXXXX-XXXX/`. See `context/workflows/02-vendor-image-sourcing-and-skuing.md` ("Set up folder structure") for the full setup pattern.

---

## Image order

**Always check `context/standards/pim-category-ordering.md` first** for the correct image order for the product category. Do not ask the evo team member about image order without checking this file first. If the category is not listed or the product type is ambiguous, raise it as a documentation-improvement candidate per `context/operating-rules.md` and ask for clarification.

**Image order always requires a human confirmation step.** Claude cannot reliably determine shot type (baseline white-bg, on-model, lifestyle, detail) from vendor filenames alone — filenames are inconsistent across brands and do not always reflect content. Visual inspection of each file is required before assigning a numeric prefix. Propose a mapping to the evo team member for confirmation before renaming any files.

**Visual inspection process:** To inspect images without consuming excessive context tokens, first generate thumbnails via Python/Pillow (resize to ~400px, flatten to white background, save as JPG to a temp `thumbs/` folder in the outputs directory). Then read each thumbnail using the Read tool. This is significantly more token-efficient than reading full-resolution source files. Thumbnails are sufficient for determining shot type (baseline vs. on-model vs. lifestyle).

**When listing SKUs for the evo team member to check:** Always list in ascending numerical order by SKU number, since folder views in Finder and Windows Explorer sort by name. This makes it easy for the user to locate each folder in sequence.

**Baseline shots go first.** Baseline (white background, not on-model, not lifestyle) product shots are ordered before on-model and lifestyle shots, per category rules. When in doubt about whether a shot is baseline or on-model, inspect it visually.

---

## Standard batch processing

- Photoshop actions location: `smb://digitalcontent.evo.local/Images/Photoshop_Templates_and_Actions/Photoshop Actions`
- File > Scripts > Image Processor — select correct action, output to `Output/` folder
- Review every output image for weird crops
- **Only the main image needs white background (255 RGB)** — all other images go through as-is from vendor

---

## Output folder location

Processed output files go directly to `[Brand]/Output/[EB-SKU]/` within the daily work folder (e.g. `2026-05-13/ArcTeryx/Output/EB-276695-1014/`). This is where the evo team member can see and review them in Finder. Do not place output files in a separate `thumbs/` folder or in the Cowork outputs directory.

---

## Numeric prefix naming

Output files are named with a two-digit numeric prefix indicating image order: `01_[original filename].jpg`, `02_[original filename].jpg`, etc. The prefix drives PIM upload order. Original vendor filename is preserved after the prefix.

---

## Image order review process

1. Process all images to the Output folder with proposed numeric prefixes based on the PIM Photo Guide (`context/standards/pim-category-ordering.md`).
2. Tell the evo team member the proposed order and ask them to open the Output folder in Finder to review.
3. Wait for confirmation or reorder instructions before proceeding to PIM upload.
4. If reordering is needed: rename the files by changing the numeric prefix only (e.g. `01_` → `03_`). Do not reprocess.

Always check `pim-category-ordering.md` before proposing an order — do not propose an order from memory or intuition alone. Raise any gap (product type not covered) as a documentation-improvement candidate per `context/operating-rules.md`.

---

## Processing spec

These specs apply regardless of the tool used (Photoshop batch or Python/Pillow). For the canonical image standards see `context/standards/image-standards.md` and the PIM Photo Guide digest in `context/standards/pim-category-ordering.md`.

- **Main image only:** flatten to white background (255 RGB). All other images go through as-is from vendor.
- Resize to 1500×1500px canvas, centered, white padding
- Output as JPG, quality 95
- Skip Lowres variants
- For the main image, the Transp version is preferred (clips cleaner) when no white-bg version is available; a neutral/tabletop background image is used as the main only when neither white-bg nor Transp exists, and the white-background flatten is applied during processing.

---

## Complex main image clipping (when white background requires manual work)

1. SKU up ALL images in batch first
2. Create folder: `YYYY-MM-DD_BrandName`
3. Upload to fileserver: `Photo_FY26 > Post Production to Edit > Vendor-Provided Images > On Hand / On Order`
4. Message post production lead and pause — wait for green light before proceeding

---

## Image standards (summary — full rules in `standards/image-standards.md`)

- Main image only: white background 255 RGB
- All other images: used as-is from vendor
- Minimum resolution: 1500x1500px (Photoshop action resizes to this on output)
- No lifestyle as main; no tech drawings; no renders (rare manager exceptions)
- On-model: non-rec crop, except eBG, Oyuki, unisex multi-model (full-rec)
- Shopify recommends 2048x2048; our 1500x1500 clears zoom threshold but is below recommended — worth revisiting
