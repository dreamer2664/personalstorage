#!/usr/bin/env python3
"""Generate every launcher icon from assets/branding/icon_master.png.

    pip install pillow
    python tool/make_icons.py

iOS   : square, opaque (the OS applies the squircle mask) -> AppIcon.appiconset/*
Android: rounded-square legacy icons -> mipmap-*/ic_launcher.png
Web   : PWA icons (plain + maskable) and favicon -> web/
"""
import json
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/branding/icon_master.png"


def square(master, px):
    return master.convert("RGB").resize((px, px), Image.LANCZOS)


def rounded(master, px, radius_ratio=0.22):
    img = square(master, px).convert("RGBA")
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, px * 4 - 1, px * 4 - 1), radius=int(px * 4 * radius_ratio), fill=255)
    img.putalpha(mask.resize((px, px), Image.LANCZOS))
    return img


def maskable(master, px):
    """PWA maskable icon: artwork inside the central 80% 'safe zone' on a matching background."""
    base = master.convert("RGB")
    bg = base.resize((1, 1), Image.LANCZOS).resize((px, px))
    inner = int(px * 0.8)
    bg.paste(base.resize((inner, inner), Image.LANCZOS), ((px - inner) // 2, (px - inner) // 2))
    return bg


def main():
    master = Image.open(MASTER)
    assert master.size[0] == master.size[1], "master must be square"

    # iOS ------------------------------------------------------------------------------------
    iconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((iconset / "Contents.json").read_text())
    for entry in contents["images"]:
        size = float(entry["size"].split("x")[0]) * int(entry["scale"].rstrip("x"))
        square(master, round(size)).save(iconset / entry["filename"], optimize=True)
    print(f"iOS: {len(contents['images'])} icons")

    # Android --------------------------------------------------------------------------------
    for density, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        rounded(master, px).save(out, optimize=True)
    print("Android: 5 densities")

    # Web / PWA ------------------------------------------------------------------------------
    icons = ROOT / "web/icons"
    for px in (192, 512):
        rounded(master, px).save(icons / f"Icon-{px}.png", optimize=True)
        maskable(master, px).save(icons / f"Icon-maskable-{px}.png", optimize=True)
    rounded(master, 64).save(ROOT / "web/favicon.png", optimize=True)
    print("Web: icons + favicon")


if __name__ == "__main__":
    main()
