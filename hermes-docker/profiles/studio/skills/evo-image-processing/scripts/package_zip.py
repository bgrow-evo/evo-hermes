#!/usr/bin/env python3
"""Package PIM-ready processed images into a ZIP for human upload.

PIM-ready files are the numeric-prefixed JPGs (NN_*.jpg) produced by
process_images.py. This script zips a brand's Output tree (or any dir tree),
excludes thumbnails, prints a manifest, and warns about any image files that
were never sequenced so nothing is silently shipped or dropped.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

SEQ_RE = re.compile(r"^\d{2,}_.+\.jpe?g$", re.IGNORECASE)
IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp"}


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def main() -> int:
    ap = argparse.ArgumentParser(description="Zip PIM-ready output for upload.")
    ap.add_argument("--src", required=True, help="dir tree to package (brand Output/ or daily dir)")
    ap.add_argument("--out", required=True, help="destination .zip path")
    ap.add_argument("--include-thumbs", action="store_true", help="include thumbs/ (default: excluded)")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.is_dir():
        sys.exit(f"--src not a directory: {src}")
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    packaged: list[Path] = []
    unsequenced: list[Path] = []
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        if not args.include_thumbs and "thumbs" in p.relative_to(src).parts:
            continue
        if SEQ_RE.match(p.name):
            packaged.append(p)
        elif p.suffix.lower() in IMG_EXTS:
            unsequenced.append(p)

    if not packaged:
        sys.exit(f"no PIM-ready (NN_*.jpg) files found under {src}")

    total = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in packaged:
            arc = p.relative_to(src)
            zf.write(p, arc)
            total += p.stat().st_size

    print(f"ZIP: {out}")
    print(f"files: {len(packaged)}  uncompressed: {human(total)}")
    by_dir: dict[str, int] = {}
    for p in packaged:
        by_dir[str(p.relative_to(src).parent)] = by_dir.get(str(p.relative_to(src).parent), 0) + 1
    for d, n in sorted(by_dir.items()):
        print(f"  {d}: {n}")
    if unsequenced:
        print(f"\nWARN: {len(unsequenced)} image file(s) NOT sequenced (excluded from ZIP):", file=sys.stderr)
        for p in unsequenced:
            print(f"  {p.relative_to(src)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
