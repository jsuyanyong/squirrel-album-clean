#!/usr/bin/env python3
"""Generate the app icon and in-app logo from the approved squirrel artwork."""

import colorsys
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "PhotoClear" / "Assets.xcassets"
SOURCE = Path(__file__).resolve().parent / "source_squirrel_logo.webp"


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def artwork_without_border() -> Image.Image:
    """Remove the low-saturation white area connected to the image edges."""
    image = Image.open(SOURCE).convert("RGBA")
    pixels = image.load()
    removable = set()
    queue = deque()

    for x in range(image.width):
        queue.extend(((x, 0), (x, image.height - 1)))
    for y in range(image.height):
        queue.extend(((0, y), (image.width - 1, y)))

    while queue:
        x, y = queue.popleft()
        if (x, y) in removable or not (0 <= x < image.width and 0 <= y < image.height):
            continue
        r, g, b, _ = pixels[x, y]
        _, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if saturation >= 0.35 or value <= 0.78:
            continue
        removable.add((x, y))
        queue.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))

    for x, y in removable:
        pixels[x, y] = (0, 0, 0, 0)
    bounds = image.getbbox()
    if bounds is None:
        raise RuntimeError("supplied artwork became empty after border removal")
    return image.crop(bounds)


def main() -> None:
    artwork = artwork_without_border()

    icon_dir = ASSETS / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon_art = ImageOps.fit(artwork, (1024, 1024), method=Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", icon_art.size, "#f7b34d")
    icon.alpha_composite(icon_art)
    icon.convert("RGB").save(icon_dir / "icon-1024.png", optimize=True)
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })

    logo_dir = ASSETS / "SquirrelLogo.imageset"
    logo_dir.mkdir(parents=True, exist_ok=True)
    for scale, filename in ((1, "squirrel_logo.png"), (2, "squirrel_logo@2x.png"), (3, "squirrel_logo@3x.png")):
        size = 48 * scale
        ImageOps.fit(artwork, (size, size), method=Image.Resampling.LANCZOS).save(
            logo_dir / filename, optimize=True
        )
    write_json(logo_dir / "Contents.json", {
        "images": [
            {"filename": "squirrel_logo.png", "idiom": "universal", "scale": "1x"},
            {"filename": "squirrel_logo@2x.png", "idiom": "universal", "scale": "2x"},
            {"filename": "squirrel_logo@3x.png", "idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    })

    assert artwork.getbbox() == (0, 0, artwork.width, artwork.height)
    print("Generated borderless app icon and in-app logo from approved squirrel artwork")


if __name__ == "__main__":
    main()
