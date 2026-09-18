#!/usr/bin/env python3
"""A context menu's preview is drawn outside the hierarchy that themed it.

`.contextMenu { … } preview: { … }` hosts its preview in a container of the system's own, and
**custom environment values do not reach it**. `\\.palette` therefore falls back to its declared
default, which is `Palette(accent: .default, appearance: .dark)` — a dark palette, unconditionally.

So a preview that forgets to re-theme itself renders **dark inside a light app**, and does it
quietly: every colour in it is a real palette colour, the bubbles look right, and only the ground
behind them gives it away. Found on the rig on 2026-09-14, on the rooms list, where the preview of a
conversation sat on black while the app was in light.

The fix is one modifier: `.themed(palette.accent)` inside the preview closure. `themed` derives the
appearance from `\\.colorScheme`, which is trait-backed and *does* cross into the system's container.

This rule is shape-based and meant to be over-eager. It looks at the lines of a `preview:` closure
and asks only whether `.themed(` appears in them. If a preview genuinely needs no palette — it draws
an image and nothing else — say `theme not needed` on one of its lines.
"""
import pathlib
import re
import sys

# Only the multiple-trailing-closure form, which is what `.contextMenu { … } preview: { … }` is.
# A plain `preview: { … }` argument is something else entirely — on the rooms list it is a closure
# that hands back `[Message]`, not a view, and flagging it would teach people to ignore this rule.
OPENS = re.compile(r"^\s*\}\s*preview:\s*\{")
THEMED = re.compile(r"\.themed\(")
EXCUSED = re.compile(r"theme not needed")

ROOTS = [pathlib.Path("Packages/Carpenter/Sources"), pathlib.Path("App")]


def closure(lines, start, column):
    """The lines of the closure whose `{` sits at `column` on `start`, by brace depth.

    Counting from the start of the opening line is wrong: the usual shape is `} preview: {`, whose
    leading brace closes the *actions* closure before this one begins. Count from the brace itself.
    """
    body = []
    depth = 0
    for index in range(start, len(lines)):
        line = lines[index]
        counted = line[column:] if index == start else line
        body.append((index + 1, counted))
        depth += counted.count("{") - counted.count("}")
        if depth <= 0:
            break
    return body


def main():
    findings = []
    for root in ROOTS:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            lines = path.read_text().splitlines()
            for index, line in enumerate(lines):
                opened = OPENS.search(line)
                if not opened:
                    continue
                body = closure(lines, index, opened.end() - 1)
                text = "\n".join(l for _, l in body)
                if THEMED.search(text) or EXCUSED.search(text):
                    continue
                findings.append(
                    f"{path}:{index + 1}: a context menu preview does not re-apply the theme, "
                    f"so it will draw dark inside a light app — add `.themed(palette.accent)`, "
                    f"or say `theme not needed` if it draws no palette colour"
                )

    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
