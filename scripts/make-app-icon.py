#!/usr/bin/env python3
"""Build the macOS and Windows app icons from the Xiaohei account avatar.

Usage: python3 scripts/make-app-icon.py [path-to-square-avatar.png]
Requires Pillow and macOS iconutil.
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("avatar", nargs="?", type=Path, default=RESOURCES / "AppIcon.png")
    args = parser.parse_args()
    with Image.open(args.avatar) as avatar:
        if avatar.width != avatar.height:
            parser.error("the source avatar must be square")
        icon = avatar.convert("RGBA")

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
    icon.resize((256, 256), Image.Resampling.LANCZOS).save(
        RESOURCES / "AppIcon.ico", sizes=[(size, size) for size in sizes]
    )


if __name__ == "__main__":
    main()
