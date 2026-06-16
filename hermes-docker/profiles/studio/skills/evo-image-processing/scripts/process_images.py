#!/usr/bin/env python3
"""Process vendor product images to the evo PIM spec.

Implements the canonical spec from the playbook's image-standards:
  - Main image: tight-crop bleed, flatten onto white (255 RGB).
  - All images: centered on a 1500x1500 white canvas, JPG quality 95.
  - Numeric-prefix naming (NN_<original>.jpg) drives PIM upload order.
  - Optional ~400px thumbnails for token-cheap visual inspection.

This is mechanics only. Image ORDER and which file is the MAIN shot are human
decisions in the workflow — pass them in via --order / --main.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops

IMG_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp"}


def list_sources(src: Path) -> list[Path]:
    return sorted(
        p for p in src.iterdir()
        if p.is_file() and p.suffix.lower() in IMG_EXTS
    )


def flatten_to_white(im: Image.Image, bg: int) -> Image.Image:
    """Composite any transparency onto a solid background (JPG has no alpha)."""
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        rgba = im.convert("RGBA")
        canvas = Image.new("RGBA", rgba.size, (bg, bg, bg, 255))
        canvas.alpha_composite(rgba)
        return canvas.convert("RGB")
    return im.convert("RGB")


def content_bbox(im: Image.Image, bg: int) -> tuple[int, int, int, int] | None:
    """Bounding box of non-background content.

    Uses the alpha channel when present (most reliable for clean vendor PNGs);
    otherwise diffs against the solid background colour.
    """
    if im.mode in ("RGBA", "LA"):
        alpha = im.convert("RGBA").getchannel("A")
        return alpha.getbbox()
    rgb = im.convert("RGB")
    background = Image.new("RGB", rgb.size, (bg, bg, bg))
    diff = ImageChops.difference(rgb, background)
    return diff.getbbox()


def tight_crop(im: Image.Image, bg: int) -> Image.Image:
    bbox = content_bbox(im, bg)
    return im.crop(bbox) if bbox else im


def fit_to_canvas(im: Image.Image, canvas: int, bg: int) -> Image.Image:
    """Resize to fit within canvas (preserving aspect) and center on white pad."""
    rgb = im if im.mode == "RGB" else im.convert("RGB")
    w, h = rgb.size
    if w == 0 or h == 0:
        raise ValueError("empty image after crop")
    scale = min(canvas / w, canvas / h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    resized = rgb.resize((new_w, new_h), Image.LANCZOS)
    out = Image.new("RGB", (canvas, canvas), (bg, bg, bg))
    out.paste(resized, ((canvas - new_w) // 2, (canvas - new_h) // 2))
    return out


def resolve_order(sources: list[Path], order: str | None) -> list[Path]:
    if not order:
        return sources
    by_name = {p.name: p for p in sources}
    ordered: list[Path] = []
    for name in (n.strip() for n in order.split(",") if n.strip()):
        if name not in by_name:
            sys.exit(f"--order names '{name}' which is not in --src ({list(by_name)})")
        ordered.append(by_name[name])
    # Append any sources not explicitly ordered, so nothing is silently dropped.
    for p in sources:
        if p not in ordered:
            print(f"WARN: '{p.name}' not in --order; appended at end", file=sys.stderr)
            ordered.append(p)
    return ordered


def process(args: argparse.Namespace) -> int:
    src, out = Path(args.src), Path(args.out)
    if not src.is_dir():
        sys.exit(f"--src not a directory: {src}")
    sources = list_sources(src)
    if not sources:
        sys.exit(f"no images found in {src}")
    out.mkdir(parents=True, exist_ok=True)
    thumbs_dir = out / "thumbs"
    if args.thumbs:
        thumbs_dir.mkdir(exist_ok=True)

    ordered = resolve_order(sources, args.order)
    main_name = args.main or ordered[0].name
    if main_name not in {p.name for p in ordered}:
        sys.exit(f"--main '{main_name}' not among sources")

    written = []
    for idx, path in enumerate(ordered, start=1):
        is_main = path.name == main_name
        with Image.open(path) as raw:
            raw.load()
            if is_main:
                cropped = tight_crop(raw, args.bg)
                flat = flatten_to_white(cropped, args.bg)
            else:
                flat = flatten_to_white(raw, args.bg)
            final = fit_to_canvas(flat, args.canvas, args.bg)

        stem = path.stem
        name = f"{idx:02d}_{stem}.jpg"
        dest = out / name
        final.save(dest, "JPEG", quality=args.quality, optimize=True)
        written.append(name)
        tag = " (main)" if is_main else ""
        print(f"{name}{tag}")

        if args.thumbs:
            thumb = final.copy()
            thumb.thumbnail((args.thumb_size, args.thumb_size), Image.LANCZOS)
            thumb.save(thumbs_dir / name, "JPEG", quality=85)

    print(f"\n{len(written)} image(s) -> {out}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Process vendor images to evo PIM spec.")
    p.add_argument("--src", required=True, help="source SKU folder (Original/EB-...)")
    p.add_argument("--out", required=True, help="output folder (Output/EB-...)")
    p.add_argument("--main", help="source filename to treat as the main shot")
    p.add_argument("--order", help="comma-separated source filenames in final order")
    p.add_argument("--canvas", type=int, default=1500, help="square canvas px (default 1500)")
    p.add_argument("--quality", type=int, default=95, help="JPEG quality (default 95)")
    p.add_argument("--bg", type=int, default=255, help="background grey value (default 255=white)")
    p.add_argument("--thumbs", action="store_true", help="also write ~400px thumbnails")
    p.add_argument("--thumb-size", type=int, default=400, help="thumbnail max edge px")
    return p


if __name__ == "__main__":
    sys.exit(process(build_parser().parse_args()))
