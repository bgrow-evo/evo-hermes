# Image Standards

Load when evaluating source images, Photoshop output, PIM upload readiness, or customer-facing image quality.

---

## Official evo image standards documents

Both documents are linked at [evo.com/partners](https://www.evo.com/partners). These are the authoritative vendor-facing standards, but they are dated and may not reflect current internal practice exactly. Treat them as reference — reconciliation with current workflow is a backlog item.

- **evo Content Requirements (vendor standard):** https://static.evo.com/content/evergreen/evo-content-requirements-wntr_21.pdf
- **evo Routing Guide (includes delivery format standards, p.7):** https://static.evo.com/content/partners/2022-10-20_evo_routing_guide.pdf

**Known discrepancies between official docs and current practice:**
- Official delivery format specifies **2000×2000px or greater**; current internal workflow produces **1500×1500px**. The 1500×1500 clears the Shopify zoom threshold but is below both the official standard and Shopify's recommended 2048×2048. Needs team decision on whether to update the Photoshop action output target.
- Official file naming includes angle descriptors: `191253685745-(Front, Side, Back, Detail).jpg`, `111222-ABC-Front.jpg`, `EB-13555-1001-Front.jpg`. Current PIM file naming in `references.md` does not include angle descriptors. Both formats are accepted by PIM.
- Official photography standards specify category-specific requirements (outerwear on ghost mannequin, clothing/swimwear on-model full-length + layflats, bike detail shots, etc.) that are partially but not fully captured in `standards/pim-category-ordering.md`.

---

## Terminology

- **Baseline:** Basic product photography on a white background. Not on-model, not lifestyle, not location. Baseline shots are the primary candidates for main images in PIM. Vendor filenames do not reliably distinguish baseline from on-model — visual inspection is required.
- **Non-recognizable (non-rec) crop:** A crop applied to on-model images used as the main image, such that the model's face is not recognizable. The crop line falls just below the nose and above the mouth. Never crop through a hood or any physical part of the product — if the crop line would intersect a product element, bring it down to just below that element instead. See also: full-rec exceptions below.
- **Full-rec:** Fully recognizable crop — model's face is visible. Allowed for all images (including main) for eBG, Oyuki, and unisex multi-model shoots.

---

## Current working standards

These reflect current internal practice. Where they conflict with the official documents above, flag for team review before changing workflow.

- **Main image only:** white background 255 RGB. All other images used as-is from vendor.
- **Minimum resolution:** 1500x1500px. Pull the highest available from the vendor; the Photoshop action resizes to 1500x1500 on output. *(Note: official standard is 2000×2000 — see above.)*
- **No lifestyle as main image; no tech drawings; no renders.** Manager exceptions are rare.
- **On-model:** non-rec crop required any time an on-model image is used as the main image. Exceptions: eBG, Oyuki, and unisex multi-model shoots (full-rec allowed for all images including main).
- **Non-recognizable (non-rec) crop — definition:** The crop line falls just below the nose and above the mouth, so the model's face is not recognizable. Exception: never crop through a hood or any physical part of the product — if the nose/mouth crop line would intersect a hood or other product element, bring the crop down to just below that element instead. This standard applies universally across all product categories.

---

## Image matrix defaults by category

IT has not provided a definitive list. Always verify before uploading.

- **Most products:** Color matrix
- **Skis, and products where color/graphic varies by size** (some snowboards, wakeboards): Size matrix
- **Single-size products:** Do not use Size matrix — it may affect the size selector on the PDP. Use Color instead. *(Needs validation — see troubleshooting.md.)*

---

## File naming

See `context/references.md` for file naming formats accepted by PIM.
