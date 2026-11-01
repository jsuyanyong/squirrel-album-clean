#!/usr/bin/env python3
"""Generate a pixel-art squirrel app icon and in-app logo for 松鼠相册整理.

Style: hand-authored 16x16 pixel sprite, upscaled with NEAREST so every pixel
      stays a crisp square (no blending, no anti-aliasing).
Pose: side profile facing RIGHT — head, single eye and nose on the right,
      big bushy tail arcing up on the left.
Outputs land in the same asset paths, so the Xcode project needs no changes.

Swift must render these with .interpolation(.none) or the pixels get blurred.
"""

import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "PhotoClear", "Assets.xcassets"))

GRID = 16

# palette: character -> RGBA
PALETTE = {
    ".": (0, 0, 0, 0),            # transparent
    "O": (70, 36, 20, 255),       # outline
    "B": (224, 138, 62, 255),     # body
    "D": (190, 106, 44, 255),     # body shading
    "C": (252, 238, 208, 255),    # cream belly / cheek
    "E": (48, 28, 16, 255),       # eye
    "W": (255, 253, 246, 255),    # eye shine
    "N": (60, 32, 20, 255),       # nose
    "A": (228, 178, 98, 255),     # acorn nut
    "a": (150, 96, 48, 255),      # acorn cap
}

# 16x16 side-view squirrel facing right: head/eye/nose on the right,
# bushy tail sweeping up on the left.
SPRITE = [
    "................",
    "..........OOOO..",
    ".........OBBBBO.",
    "........OBBBBBBO",
    "...OO....OBCCBBO",
    "..ODDO...OBBBEBO",
    "..ODDDO..OBCCBNO",
    "..ODDDDOOBBBBBBO",
    ".ODDDDDDOBBBBBBO",
    ".ODDDDDDOBBBBBO.",
    ".ODDDDDDDBBBBBO.",
    ".ODDDDDDDBBBBBO.",
    "..ODDDDDDBBBBBO.",
    "..ODDDDDBBBBBO..",
    "...OOOO...OOO...",
    "................",
]


def render_sprite():
    """Rasterize the character map into a 16x16 RGBA image."""
    if len(SPRITE) != GRID or any(len(row) != GRID for row in SPRITE):
        raise SystemExit(
            f"SPRITE must be {GRID}x{GRID}; got "
            f"{len(SPRITE)} rows, widths={[len(r) for r in SPRITE]}"
        )
    img = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(SPRITE):
        for x, ch in enumerate(row):
            if ch not in PALETTE:
                raise SystemExit(f"unknown sprite char {ch!r} at ({x},{y})")
            px[x, y] = PALETTE[ch]
    return img


def ascii_preview(img):
    """Print the sprite as text so the design can be checked without pixels."""
    px = img.load()
    rows = []
    for y in range(img.height):
        rows.append("".join(
            PALETTE_CH.get(px[x, y], "?") for x in range(img.width)
        ))
    return "\n".join(rows)


# reverse lookup so the preview round-trips
PALETTE_CH = {v: k for k, v in PALETTE.items()}


def upscale(img, factor):
    """Integer NEAREST upscale keeps every pixel a crisp square."""
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def main():
    sprite = render_sprite()

    print(f"=== {GRID}x{GRID} sprite ===")
    print(ascii_preview(sprite))

    # distinct colors must survive upscale exactly (proves NEAREST, no blending)
    src_colors = len(sprite.getcolors(maxcolors=1000) or [])

    # ---- app icon: 16 -> 1024 (exact 64x), on an opaque background ----
    icon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)
    BG = (232, 241, 219, 255)      # matches the app's cream/green theme
    icon = Image.new("RGBA", (GRID, GRID), BG)
    icon.alpha_composite(sprite)
    icon_big = upscale(icon, 1024 // GRID)
    icon_big.convert("RGB").save(os.path.join(icon_dir, "icon-1024.png"))
    with open(os.path.join(icon_dir, "Contents.json"), "w", encoding="utf-8") as h:
        json.dump({
            "images": [{"filename": "icon-1024.png", "idiom": "universal",
                        "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }, h, indent=2)

    # ---- in-app logo: transparent, 48 / 96 / 144 (exact 3x / 6x / 9x) ----
    logo_dir = os.path.join(ASSETS, "SquirrelLogo.imageset")
    os.makedirs(logo_dir, exist_ok=True)
    for scale, filename in ((1, "squirrel_logo.png"), (2, "squirrel_logo@2x.png"),
                            (3, "squirrel_logo@3x.png")):
        upscale(sprite, 3 * scale).save(os.path.join(logo_dir, filename))
    with open(os.path.join(logo_dir, "Contents.json"), "w", encoding="utf-8") as h:
        json.dump({
            "images": [
                {"filename": "squirrel_logo.png", "idiom": "universal", "scale": "1x"},
                {"filename": "squirrel_logo@2x.png", "idiom": "universal", "scale": "2x"},
                {"filename": "squirrel_logo@3x.png", "idiom": "universal", "scale": "3x"},
            ],
            "info": {"author": "xcode", "version": 1},
        }, h, indent=2)

    # ---- verification: upscale must not have introduced new colors ----
    big_colors = len(icon_big.getcolors(maxcolors=100000) or [])
    bg_plus_sprite = src_colors          # bg is one flat color + sprite colors
    ok = big_colors <= bg_plus_sprite + 1
    print(f"\ncolors: sprite={src_colors}  upscaled_icon={big_colors}  "
          f"(NEAREST keeps them equal-ish: {'OK' if ok else 'CHECK'})")
    print("wrote app icon + logo to", ASSETS)


if __name__ == "__main__":
    main()
