#!/usr/bin/env python3
"""Build Resources/AppIcon.icns from the Xiaohei front V14 transparent PNG.

Usage:
    python3 scripts/make-app-icon.py <path-to-xiaohei-front-v14.png>

The icon is Xiaohei's head on a brand blue (#3B82F6, Tailwind blue-500) macOS squircle.
Requires Pillow and macOS `iconutil`.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BLUE = (59, 130, 246, 255)


def make_icon(src: Image.Image, size: int) -> Image.Image:
    scale = 4  # supersample the squircle edge
    big = size * scale
    bg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    pad = round(big * 0.055)
    ImageDraw.Draw(bg).rounded_rectangle([pad, pad, big - pad, big - pad], radius=round(big * 0.225), fill=BLUE)
    bg = bg.resize((size, size), Image.LANCZOS)

    head = src.crop(src.getbbox())
    target_w = round(size * 0.70)
    target_h = round(head.height * target_w / head.width)
    head = head.resize((target_w, target_h), Image.LANCZOS)
    x = (size - target_w) // 2
    y = (size - target_h) // 2 + round(size * 0.01)
    bg.alpha_composite(head, (x, y))
    return bg


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    src = Image.open(sys.argv[1]).convert("RGBA")
    out = ROOT / "Resources" / "AppIcon.icns"
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for sz in (16, 32, 128, 256, 512):
            make_icon(src, sz).save(iconset / f"icon_{sz}x{sz}.png")
            make_icon(src, sz * 2).save(iconset / f"icon_{sz}x{sz}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
        preview = ROOT / "out" / "qa" / "xiaohei" / "app-icon-512.png"
        preview.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(iconset / "icon_512x512.png", preview)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
