#!/usr/bin/env python3
"""Rule 14: a destructive control must name its colour, because a tint beats a role.

`Button(role: .destructive)` reddens the *words*. It does not redden the SF Symbol beside them,
because this app tints its whole view hierarchy accent-green and a label's symbol takes the
inherited tint ahead of the button's role. The result is a control whose text says "Remove" in red
next to a cheerful green glyph — which reads as a mistake, and worse, reads as *safe*.

This has shipped six times: the room swipe action, the room context menu, `DestructiveActionButton`,
the message context menu twice (Withdraw and Hide for me), and the message detail page. Six is
enough. Say the colour: `.tint(palette.destructive)` on the button, or `palette.destructive` on the
symbol — either satisfies this rule, because either is a deliberate answer to the question.

**Only a button that draws a symbol is flagged.** A plain-text button in an `.alert` gets its red
from the system and has no glyph to disagree with it; that is the majority of destructive buttons in
this app and none of them has ever been wrong. The defect needs a `Label`/`Image(systemName:)` for
the tint to land on.

The check is deliberately loose otherwise. It looks for `palette.destructive` anywhere in the
button's own source — from `Button(role: .destructive)` through its closing brace and on past the
comments and chained modifiers that follow it, so a trailing `.tint(…)` counts — rather than parsing
Swift. A loose rule that fires on the real defect beats a precise one nobody finishes writing.

Prints one `path:line: message` per offender and nothing at all when clean.
"""

import pathlib
import re
import sys

ROOTS = ["Packages/Carpenter/Sources/CarpenterUI", "App"]
OPENER = re.compile(r"Button\(\s*role:\s*\.destructive")
DRAWS_A_SYMBOL = re.compile(r"Image\(systemName:|Label\(")


def offenders(path: pathlib.Path) -> list[tuple[int, str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    found = []
    for index, line in enumerate(lines):
        if not OPENER.search(line) or line.lstrip().startswith("//"):
            continue
        # Walk to the button's closing brace by depth.
        depth = 0
        end = index
        for cursor in range(index, len(lines)):
            depth += lines[cursor].count("{") - lines[cursor].count("}")
            end = cursor
            if depth <= 0 and cursor > index:
                break
        # Then keep going through whatever is chained onto that brace. A comment explaining the
        # tint sits between the brace and the `.tint(…)` more often than not, and a fixed number of
        # trailing lines makes the rule fire on exactly the call sites that took the trouble.
        tail = end
        for cursor in range(end + 1, len(lines)):
            stripped = lines[cursor].strip()
            if stripped and not stripped.startswith(("//", ".")):
                break
            tail = cursor
        window = "\n".join(lines[index : tail + 1])
        if not DRAWS_A_SYMBOL.search(window):
            continue
        if "palette.destructive" not in window:
            found.append((index + 1, lines[index].strip()))
    return found


if __name__ == "__main__":
    hits = []
    for root in ROOTS:
        for path in sorted(pathlib.Path(root).rglob("*.swift")):
            if ".build" in path.parts:
                continue
            for line_number, text in offenders(path):
                hits.append(f"{path}:{line_number}: {text}")
    if hits:
        print("\n".join(hits))
        sys.exit(0)
