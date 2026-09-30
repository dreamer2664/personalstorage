#!/usr/bin/env python3
"""Shrink the raw screenshots written by tool/web_shots.py for the repository.

Keeps only the files the README references, converts them to 520 px wide JPEGs (quality 90; the glass
gradients compress far better as JPEG than PNG) and removes the rest.

    pip install pillow
    python tool/compress_screenshots.py
"""
import pathlib
import re

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs/screenshots"
README = (ROOT / "README.md").read_text()
wanted = set(re.findall(r"docs/screenshots/([\w.-]+?)\.(?:png|jpg)", README))

kept = 0
for png in sorted(SHOTS.glob("*.png")):
    if png.stem in wanted:
        img = Image.open(png).convert("RGB")
        h = round(img.height * 520 / img.width)
        img.resize((520, h), Image.LANCZOS).save(SHOTS / f"{png.stem}.jpg", quality=90, optimize=True, progressive=True)
        kept += 1
    png.unlink()
print(f"kept {kept} screenshots, removed the rest; {sum(f.stat().st_size for f in SHOTS.glob('*.jpg')) / 1e6:.1f} MB")
