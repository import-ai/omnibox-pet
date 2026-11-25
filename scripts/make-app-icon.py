#!/usr/bin/env python3
"""Build the macOS and Windows app icons from the Xiaohei account avatar.

Usage: python3 scripts/make-app-icon.py [path-to-square-avatar.png]
Requires Pillow and macOS iconutil.
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"


def make_icon(avatar: Image.Image) -> Image.Image:
    size = 1024
    padding = round(size * 0.055)
    artwork = avatar.resize((size - 2 * padding,) * 2, Image.Resampling.LANCZOS)
    mask = Image.new("L", artwork.size)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, artwork.width - 1, artwork.height - 1),
        radius=round(size * 0.225),
        fill=255,
    )
    icon = Image.new("RGBA", (size, size))
    icon.paste(artwork, (padding, padding), mask)
    return icon


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("avatar", nargs="?", type=Path, default=RESOURCES / "AppIcon.png")
    args = parser.parse_args()
    with Image.open(args.avatar) as avatar:
        if avatar.width != avatar.height:
            parser.error("the source avatar must be square")
        icon = make_icon(avatar.convert("RGBA"))

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale, suffix in ((1, ""), (2, "@2x")):
                pixels = size * scale
                icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(
                    iconset / f"icon_{size}x{size}{suffix}.png"
                )
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES / "AppIcon.icns")],
            check=True,
        )

    sizes = (16, 20, 24, 32, 40, 48, 64, 128, 256)
    icon.save(RESOURCES / "AppIcon.ico", sizes=[(size, size) for size in sizes])


if __name__ == "__main__":
    main()
