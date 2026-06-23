---
name: evo-image-processing
description: "Process vendor product images to evo PIM spec (tight crop, white-flatten main, 1500x1500 JPG q95, numeric-prefix ordering, thumbnails) and package PIM-ready output as a ZIP. Use during the evo photo Image Editing & Processing step and when packaging output for upload."
version: 1.0.0
author: evo studio
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [images, pillow, photo-workflow, evo, pim, batch, zip]
    related_skills: [studio-daily-pipeline]
---

# evo Image Processing

Deterministic batch image processing for the evo photo workflow. Wraps Pillow so
you do not hand-write per-image code. Always defer to the canonical spec in
`playbook/context/standards/image-standards.md` and the image order in
`playbook/context/standards/pim-category-ordering.md` — this skill implements the
mechanics, not the ordering decisions.

## Spec implemented (image-standards)

- **Main image only:** tight-crop bleed, flatten to white background (255 RGB).
- **All other images:** flattened onto white (JPG has no alpha), used as-is otherwise.
- Resize to a **1500×1500** canvas, centered, white padding.
- Output **JPG, quality 95**.
- **Numeric-prefix naming:** `01_<original>.jpg`, `02_…` — drives PIM upload order.
- Optional **thumbnails** (~400px) for token-cheap visual inspection via the Read tool.

## Tools (run with system python3 in this container)

`scripts/process_images.py` — process one SKU folder:

```bash
python3 scripts/process_images.py \
  --src  "<Original/EB-XXXXXX-XXXX>" \
  --out  "<Output/EB-XXXXXX-XXXX>" \
  --main "<main-source-filename>" \
  --order "fileA.png,fileB.png,fileC.png" \
  --thumbs
```

- `--main` names the source file to treat as the main shot (white-flatten + tight
  crop). Omit only if there is genuinely no white-bg/Transp candidate.
- `--order` is the confirmed image order (comma-separated source filenames). Omit
  to fall back to alphabetical — but **image order requires human confirmation**
  (see the workflow); inspect thumbnails first, propose, then pass `--order`.
- `--thumbs` writes `<out>/thumbs/NN_<name>.jpg` at ~400px. Read those, not the
  full-res source, to decide shot type.
- Other flags: `--canvas 1500`, `--quality 95`, `--bg 255`.

`scripts/package_zip.py` — build the PIM-ready ZIP:

```bash
python3 scripts/package_zip.py \
  --src "<brand Output dir or daily work dir>" \
  --out "/opt/data/outbox/studio/<YYYY-MM-DD>/<brand>_pim-ready.zip" \
  --manifest "/opt/data/outbox/studio/<YYYY-MM-DD>/MANIFEST.md"
```

Only files matching `NN_*.jpg` are packaged; the script warns about any unsequenced
files so nothing is silently dropped. `--manifest <file>` (optional) bundles that file
at the **zip root** — write the manifest *before* zipping if you want it included. The
script prints a summary (folders, file counts, total size).

## Workflow

1. Inspect source thumbnails → decide shot types → propose order to a human.
2. After confirmation, run `process_images.py` per SKU with `--main` and `--order`.
3. Review outputs (read the thumbs) for bad crops.
4. Package the brand's `Output/` tree with `package_zip.py` into the outbox.
5. Hand the ZIP to a human for PIM upload (you do not upload).

## Limits

- Clean-source only (white-bg PNG / transparent RGBA). Non-white, non-transparent
  backgrounds need manual Photoshop clipping — flag the SKU and route per the
  workflow's "Complex main image clipping" section. Do not fake a clip.
