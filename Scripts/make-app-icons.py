#!/usr/bin/env python3
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

RENDER = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("render-icon")
MARKS = Path("logo_svgs")
ASSETS = Path("App/Carpenter/Assets.xcassets")
SCRATCH = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/outpost-face-icons")

ACCENTS = [
    ("Cobalt", 0x2F62DE),
    ("Verdigris", 0x14766C),
    ("SignalAmber", 0x945D0F),
    ("Oxblood", 0xA5333A),
    ("Aubergine", 0x7048BC),
    ("HangarSlate", 0x546A7E),
    ("OliveDrab", 0x607120),
]

MARK_FILES = [
    ("Full", "outpost-glyph"),
    ("Antenna", "face_logo_base"),
    ("Mailbox", "face_logo_base_no_flag"),
    ("MailboxFilled", "face_logo_base_no_flag_filled"),
]

DRAWN_EXTENT = {
    "outpost-glyph": 83.785,
    "face_logo_base": 77.6,
    "face_logo_base_no_flag": 65.6,
    "face_logo_base_no_flag_filled": 65.6,
}

GLYPH_SHARE = 0.61
DARK_GROUND = 0x12141A
FILL_TARGET = 4.6


def channels(rgb):
    return ((rgb >> 16) & 0xFF) / 255, ((rgb >> 8) & 0xFF) / 255, (rgb & 0xFF) / 255


def luminance(rgb):
    def channel(value):
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = channels(rgb)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    first, second = luminance(a), luminance(b)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)


def darkened(rgb, amount):
    factor = max(0, min(1, 1 - amount))
    r, g, b = channels(rgb)
    return (round(r * factor * 255) << 16) | (round(g * factor * 255) << 8) | round(b * factor * 255)


def fill_carrying_white(rgb):
    swatch, step = rgb, 0.0
    while contrast(0xFFFFFF, swatch) < FILL_TARGET and step < 0.9:
        step += 0.05
        swatch = darkened(rgb, step)
    return swatch


def mark(file):
    source = (MARKS / f"{file}.svg").read_text()
    x, y, w, h = (float(v) for v in re.search(r'viewBox="([^"]+)"', source).group(1).split())
    body = source[source.index('id="path1"') - 30:] if 'id="path1"' in source else source[source.index("<path"):]
    d = re.search(r'\sd="([^"]+)"', body).group(1)
    transform = re.search(r'transform="([^"]+)"', body)
    return (x, y, w, h), d, transform.group(1) if transform else ""


def drawing(file, ground, glyph):
    (x, y, w, h), d, transform = mark(file)
    side = DRAWN_EXTENT[file] / GLYPH_SHARE
    left = x - (side - w) / 2
    top = y - (side - h) / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{left:.4f} {top:.4f} {side:.4f} {side:.4f}">'
        f'<rect x="{left:.4f}" y="{top:.4f}" width="{side:.4f}" height="{side:.4f}" fill="#{ground:06X}"/>'
        f'<path transform="{transform}" fill="#{glyph:06X}" d="{d}"/></svg>'
    )


def render(svg_text, out, px):
    SCRATCH.mkdir(parents=True, exist_ok=True)
    source = SCRATCH / (out.parent.name + ".svg")
    source.write_text(svg_text)
    subprocess.run([str(RENDER), str(source), str(out), str(px), "none", "opaque"], check=True)


def build(name, svg_text):
    folder = ASSETS / f"{name}.appiconset"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    render(svg_text, folder / "ios.png", 1024)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "ios.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")

    preview = ASSETS / f"{name}-Preview.imageset"
    if preview.exists():
        shutil.rmtree(preview)
    preview.mkdir(parents=True)
    render(svg_text, preview / "preview.png", 256)
    (preview / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "preview.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": False},
    }, indent=2) + "\n")
    print(name)


if __name__ == "__main__":
    names = []
    for label, file in MARK_FILES:
        for accent, light in ACCENTS:
            name = f"AppIcon-{label}{accent}"
            build(name, drawing(file, fill_carrying_white(light), 0xFFFFFF))
            names.append(name)
        if label == "Full":
            continue
        for suffix, ground, glyph in (("White", 0xFFFFFF, 0x000000), ("Black", DARK_GROUND, 0xFFFFFF)):
            name = f"AppIcon-{label}{suffix}"
            build(name, drawing(file, ground, glyph))
            names.append(name)
    print()
    print(" ".join(names))
