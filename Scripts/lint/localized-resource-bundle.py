#!/usr/bin/env python3
"""A `LocalizedStringResource` built from a bare literal reads the wrong catalogue.

`Text("…")` without `bundle: .module` is already caught, by a grep in `lint-branding.sh`. This is the
same defect one type over, and that grep cannot see it: a string literal coerced to a
`LocalizedStringResource` inside a package resolves against `Bundle.main` — the *app's* catalogue —
so the string is never extracted from the package, never translated, and ships in English for ever.
Invisibly, because the English build looks perfect.

It had swallowed nine strings by the time anybody looked: *Messages*, *Solos*, *Rooms*, the four
empty states of the rooms list and its three search prompts. Found by reading, in the verification
design pass on 2026-09-09, not by any check.

**`LocalizedStringKey` is deliberately not covered.** A key carries no bundle by design — the bundle
is supplied where it is drawn, `Text(key, bundle: .module)`, which several screens do correctly. A
rule that flagged it would be telling the truth about the type and a lie about the code.

The fix at a call site is `LocalizedStringResource.module("…")`, which is in `ModuleStrings.swift`
and is the only construction this accepts.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
# The package only. In the app target the main bundle *is* the right one, and
# `RoomsFocusFilter` is correct as written.
SOURCES = ROOT / "Packages" / "Carpenter" / "Sources"

TYPE = "LocalizedStringResource"
# A declaration whose value is one: `var x: LSR {`, `func f() -> LSR {`, `let x: LSR = …`.
OPENS_BLOCK = re.compile(rf"(:|->)\s*{TYPE}\s*\{{")
INLINE_ASSIGNMENT = re.compile(rf":\s*{TYPE}\s*=\s*(.+)$")
# What a correctly built one looks like, however it is spelt.
BLESSED = re.compile(rf"\.module\(|{TYPE}\s*\(")


def offending_literal(fragment: str) -> bool:
    """Whether this fragment introduces a bare string literal that is not built through a helper."""
    stripped = fragment.strip()
    if not stripped or stripped.startswith("//"):
        return False
    if '"' not in stripped:
        return False
    return not BLESSED.search(stripped)


def check(path: pathlib.Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not any(TYPE in line for line in lines):
        return []

    problems: list[str] = []
    depth = 0
    inside = False
    # A helper call left open on an earlier line: `.module(` and its string on the next one, which
    # is what a sentence long enough to wrap looks like. The literal is blessed by the call above
    # it, and a checker that could not see that would flag every long string in the file.
    open_call = 0

    for number, line in enumerate(lines, start=1):
        if open_call > 0:
            open_call += line.count("(") - line.count(")")
            if open_call <= 0:
                open_call = 0
            if inside:
                depth += line.count("{") - line.count("}")
                if depth <= 0:
                    inside = False
            continue

        if BLESSED.search(line):
            open_call = max(0, line.count("(") - line.count(")"))

        if not inside:
            # A stored property or a default argument, all on one line.
            assignment = INLINE_ASSIGNMENT.search(line)
            if assignment and offending_literal(assignment.group(1)):
                problems.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")

            if OPENS_BLOCK.search(line):
                inside = True
                depth = line.count("{") - line.count("}")
                continue
        else:
            if offending_literal(line):
                problems.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                inside = False

    return problems


def main() -> int:
    found: list[str] = []
    for path in sorted(SOURCES.rglob("*.swift")):
        found.extend(check(path))

    for problem in found:
        print(problem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
