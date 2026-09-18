#!/usr/bin/env python3
"""Strip the Inkscape working files down to the artwork they actually draw, and
fill in the colourways that are recolours rather than drawings.

    python3 Scripts/optimise-logos.py

Reads `logo_svgs/{full,icon,wordmark}/` and writes `Design/logos/{full,icon,wordmark}/`.

WHY STRIPPING IS NOT OPTIONAL
Each working file carries every accent panel as a separate layer with all but one set to
`display:none`, plus editing scaffolding and Inkscape's own document state. That is the
right way to keep the set editable and the wrong thing to ship: the hidden panels are most
of the bytes, and a renderer that does not honour `display:none` — NSImage is one — draws
the lot stacked (Build Decision D44).

WHAT IS DRAWN AND WHAT IS DERIVED
Every file is an `Outlines` path, optionally sitting over a `panel, <accent>` path. That
makes the missing colourways a recolour of one layer rather than new artwork, so they are
generated here instead of being drawn and kept in step by hand:

  wordmark_<accent>.svg        the wordmark drawn in the accent
  icon_<accent>_hollow.svg     the hollow icon outlined in the accent
  outpost_<accent>_hollow.svg  the whole lockup drawn in the accent, no panel
  outpost_plain_<variant>      the full lockup with the panel dropped — outline only

The accent value comes from the panel of that accent's own drawing, so it can never drift
from the artwork. It is one value per accent: the panel is the same colour in the light and
dark lockups, and only the outline changes between them.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG = "http://www.w3.org/2000/svg"
INKSCAPE = "http://www.inkscape.org/namespaces/inkscape"
SODIPODI = "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"

ET.register_namespace("", SVG)

SOURCE = Path("logo_svgs")
OUT = Path("Design/logos")

ACCENTS = [
    "cobalt",
    "verdegris",
    "signal_amber",
    "oxblood",
    "aubergine",
    "hangar_slate",
    "olive_drab",
]


def hidden(element) -> bool:
    return "display:none" in element.get("style", "").replace(" ", "")


def prune_hidden(element) -> None:
    """Remove `display:none` subtrees, depth first.

    Must run before anything inspects the drawing. A search for "the panel" over the raw tree
    otherwise finds another accent's hidden copy, which is how the first attempt at recolouring
    silently did nothing.
    """
    for child in list(element):
        if hidden(child):
            element.remove(child)
        else:
            prune_hidden(child)


def label_of(element) -> str:
    return element.get(f"{{{INKSCAPE}}}label", "").strip()


def find(root, predicate):
    for element in root.iter():
        if predicate(element):
            return element
    return None


def outlines_of(root):
    return find(root, lambda e: label_of(e) == "Outlines")


def panel_of(root):
    return find(root, lambda e: label_of(e).startswith("panel,"))


def fill_of(element) -> str | None:
    match = re.search(r"fill:\s*(#[0-9a-fA-F]{6})", element.get("style", ""))
    return match.group(1) if match else None


def set_fill(element, colour: str) -> None:
    style = element.get("style", "")
    if re.search(r"fill:\s*#[0-9a-fA-F]{6}", style):
        element.set("style", re.sub(r"fill:\s*#[0-9a-fA-F]{6}", f"fill:{colour}", style))
    else:
        element.set("style", f"fill:{colour};{style}" if style else f"fill:{colour}")


def strip(element) -> None:
    """Drop editor-only elements and bookkeeping, depth first."""
    for child in list(element):
        tag = child.tag
        if tag.startswith(f"{{{SODIPODI}}}") or tag.startswith(f"{{{INKSCAPE}}}"):
            element.remove(child)
            continue
        if tag == f"{{{SVG}}}metadata":
            element.remove(child)
            continue
        strip(child)

    for name in list(element.attrib):
        if name.startswith(f"{{{INKSCAPE}}}") or name.startswith(f"{{{SODIPODI}}}"):
            del element.attrib[name]
    if element.get("style") == "display:inline":
        del element.attrib["style"]


def load(source: Path):
    """Parsed, with hidden layers gone. Labels survive so callers can find layers."""
    root = ET.parse(source).getroot()
    prune_hidden(root)
    return root


def write(root, destination: Path) -> int:
    strip(root)
    for name in ("width", "height"):
        if name in root.attrib:
            del root.attrib[name]
    root.set("viewBox", root.get("viewBox", "0 0 512 512"))

    out = ET.tostring(root, encoding="unicode")
    out = re.sub(r"\s*\n\s*", " ", out)
    out = re.sub(r"\s{2,}", " ", out)
    out = '<?xml version="1.0" encoding="UTF-8"?>\n' + out.strip() + "\n"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(out)
    return len(out.encode())


def accent_colours() -> dict[str, str]:
    """Each accent's value, read from its own drawing's panel."""
    colours = {}
    for accent in ACCENTS:
        root = load(SOURCE / "full" / f"outpost_{accent}_light.svg")
        panel = panel_of(root)
        if panel is None or fill_of(panel) is None:
            sys.exit(f"no panel colour in outpost_{accent}_light.svg")
        colours[accent] = fill_of(panel)
    return colours


def main() -> None:
    if not (SOURCE / "full").is_dir():
        sys.exit(f"expected {SOURCE}/full — run from the repository root")

    colours = accent_colours()
    before = after = 0
    drawn = derived = 0

    # ── drawn: everything the owner made, stripped and copied through ────────
    for folder in ("full", "icon", "wordmark"):
        for svg in sorted((SOURCE / folder).glob("*.svg")):
            # The source carries one typo; the shipped name is spelled correctly.
            name = svg.name.replace("workdmark_", "wordmark_")
            size = write(load(svg), OUT / folder / name)
            before += svg.stat().st_size
            after += size
            drawn += 1

    # ── derived: the wordmark in each accent ─────────────────────────────────
    for accent, colour in colours.items():
        root = load(SOURCE / "wordmark" / "wordmark_black.svg")
        set_fill(outlines_of(root), colour)
        after += write(root, OUT / "wordmark" / f"wordmark_{accent}.svg")
        derived += 1

    # ── derived: the hollow icon in each accent ──────────────────────────────
    for accent, colour in colours.items():
        root = load(SOURCE / "icon" / "icon_white_hollow.svg")
        set_fill(outlines_of(root), colour)
        after += write(root, OUT / "icon" / f"icon_{accent}_hollow.svg")
        derived += 1

    # ── derived: the lockup drawn in the accent ──────────────────────────────
    # For dark grounds. The drawn dark lockup is a near-white outline over an
    # accent panel, which reads as a bright slab in the middle of the mark; this
    # gives the accent to the structure itself and drops the panel, so the accent
    # *is* the mark rather than its backing. Same reasoning as Build Decision D52.
    for accent, colour in colours.items():
        root = load(SOURCE / "full" / f"outpost_{accent}_light.svg")
        set_fill(outlines_of(root), colour)
        panel = panel_of(root)
        for parent in root.iter():
            if panel in list(parent):
                parent.remove(panel)
                break
        after += write(root, OUT / "full" / f"outpost_{accent}_hollow.svg")
        derived += 1

    # ── derived: the plain lockups, panel dropped ────────────────────────────
    # The onboarding mark is the lockup with nothing behind it, and there is no drawn
    # plain pair. Derived from cobalt rather than drawn so it cannot fall out of step
    # with the outlines (Build Decision D44).
    for variant in ("light", "dark"):
        root = load(SOURCE / "full" / f"outpost_cobalt_{variant}.svg")
        panel = panel_of(root)
        for parent in root.iter():
            if panel in list(parent):
                parent.remove(panel)
                break
        after += write(root, OUT / "full" / f"outpost_plain_{variant}.svg")
        derived += 1

    print(f"{drawn} drawn, {derived} derived -> {OUT}/{{full,icon,wordmark}}/")
    print(f"sources {before:,} bytes -> output {after:,} bytes")


if __name__ == "__main__":
    main()
