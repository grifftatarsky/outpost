#!/usr/bin/env python3
"""Every sheet goes through sizedSheet, because macOS sizes a sheet to its content.

A List, a ScrollView or a TextEditor has no natural height. On iPhone that is fine: a sheet is as
tall as the screen allows. On a Mac the sheet asks its content how big to be, is told nothing, and
collapses — on 2026-09-18 the notifications explainer arrived as a Continue button floating over the
window with nothing above it, and the new-post sheet did the same. sizedSheet gives the Mac a form
size and changes nothing on iPhone or iPad. A bare .sheet( is the way to reintroduce it.
"""
import pathlib
import re
import sys

HELPER = "SizedSheet.swift"
BARE = re.compile(r"\.sheet\(")

problems = []
for root in ("App", "Packages/Carpenter/Sources"):
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        if path.name == HELPER:
            continue
        for number, line in enumerate(path.read_text().splitlines(), start=1):
            if BARE.search(line):
                problems.append(f"{path}:{number}: {line.strip()}")

print("\n".join(problems))
sys.exit(1 if problems else 0)
