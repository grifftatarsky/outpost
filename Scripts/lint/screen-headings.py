#!/usr/bin/env python3
"""A screen's headline is a heading, because the rotor is how a screen is skimmed.

VoiceOver's rotor navigates by heading. A headline drawn at title size with no heading trait is
read out when the cursor happens to reach it and is invisible to every other way of moving around
the screen, so a member using the rotor to skim has nothing to land on and must walk the whole
screen element by element.

Measured on the rig on 2026-09-17, with VoiceOver actually running rather than inferred from the
element tree: `PermissionExplainerView` announced "Notifications" and "Photos" as plain text while
every other screen in the same walk announced "..., Heading". `JoinPromptView` had the same gap.
Both are fixed; this rule is what keeps the next one from landing.

`.heading()` and `.sectionHeading()` in `Theme/Accessibility.swift` both add the trait, and
`SettingsHeaderCard` carries it for every page built out of the settings chrome — so a screen using
any of those already passes.

The check is deliberately loose: it looks for a heading trait anywhere within ten lines of the
title-sized font, which is the modifier chain the headline is written in. It flags a `Text`, never
an `Image` — an SF Symbol drawn at title size is decoration and has nothing to announce.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "Packages/Carpenter/Sources/CarpenterUI"

TITLE_FONT = re.compile(
    r"\.font\(\s*(?:CarpenterFont\.(?:largeTitle|screenTitle)|\.largeTitle|\.title(?:\b|\.))"
)
HEADING = ("heading()", "isHeader")
WINDOW = 10


def flagged(path: pathlib.Path) -> list[tuple[int, str]]:
    lines = path.read_text().splitlines()
    out = []
    for i, line in enumerate(lines):
        if not TITLE_FONT.search(line):
            continue
        window = "\n".join(lines[max(0, i - WINDOW) : i + WINDOW])
        if any(mark in window for mark in HEADING):
            continue
        # An SF Symbol at title size is decoration; only words are announced.
        preceding = "\n".join(lines[max(0, i - 4) : i + 1])
        if "Image(systemName:" in preceding and "Text(" not in preceding:
            continue
        out.append((i + 1, line.strip()))
    return out


def main() -> int:
    problems = []
    for path in sorted(ROOT.rglob("*.swift")):
        for line_number, text in flagged(path):
            problems.append(f"  {path.relative_to(ROOT.parents[2])}:{line_number}: {text}")
    if problems:
        print("\n".join(problems))
    return 0


if __name__ == "__main__":
    sys.exit(main())
