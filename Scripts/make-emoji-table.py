#!/usr/bin/env python3
"""Turn Unicode's emoji-test.txt into the table the picker searches.

Griff ruled 2026-09-14: our own grid, from a **refreshable** Unicode table, searchable by name —
the one thing the system keyboard cannot do. Refreshable is why this is a script rather than a
hand-typed list: when Unicode ships a new set, this is run again and the resource is replaced.

    Scripts/make-emoji-table.py                     # fetches the latest
    Scripts/make-emoji-table.py /tmp/emoji-test.txt # or parses a file already on disk

What it keeps: fully-qualified sequences only, skin-tone variants dropped (the base carries the
meaning and five copies of every person would drown the grid), and the Component group dropped
entirely — a bare skin-tone swatch is not something anybody sends.

The output is JSON rather than generated Swift on purpose: a 1,900-entry Swift literal is slow to
type-check and shows up in the binary as code rather than as data.
"""
import json
import pathlib
import re
import sys
import urllib.request

SOURCE = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
OUT = pathlib.Path("Packages/Carpenter/Sources/CarpenterUI/Resources/emoji.json")

LINE = re.compile(
    r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.+)$"
)


def main() -> int:
    if len(sys.argv) > 1:
        text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    else:
        with urllib.request.urlopen(SOURCE, timeout=60) as response:
            text = response.read().decode("utf-8")

    groups: list[dict] = []
    group = None
    skipped = 0

    for line in text.splitlines():
        if line.startswith("# group:"):
            name = line.split(":", 1)[1].strip()
            if name == "Component":
                group = None
                continue
            group = {"name": name, "emoji": []}
            groups.append(group)
            continue

        if group is None or not line or line.startswith("#"):
            continue

        found = LINE.match(line)
        if not found:
            continue

        _, glyph, _, name = found.groups()
        if "skin tone" in name:
            skipped += 1
            continue

        group["emoji"].append({"e": glyph, "n": name})

    groups = [g for g in groups if g["emoji"]]
    total = sum(len(g["emoji"]) for g in groups)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(groups, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    print(f"{total} emoji in {len(groups)} groups -> {OUT} ({OUT.stat().st_size:,} bytes)")
    print(f"{skipped} skin-tone variants dropped")
    for g in groups:
        print(f"  {len(g['emoji']):4}  {g['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
