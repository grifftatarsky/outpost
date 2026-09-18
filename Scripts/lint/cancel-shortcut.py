#!/usr/bin/env python3
"""A sheet's cancel button answers Escape.

SwiftUI binds Escape to the button that says so with .keyboardShortcut(.cancelAction); a toolbar item
placed as .cancellationAction does not declare it. None of the app's nineteen cancel buttons did, on
2026-09-18. What was measured that day, on an iPad simulator: Command-period leaves a sheet with or
without the shortcut — the system does that — and an Escape injected by XCUITest leaves it with
neither, so the iPad does not prove the rule. The Mac is where Escape is how a sheet is left, and it
was not measured, because the screen was locked.
"""
import pathlib
import re
import sys

ITEM = re.compile(r"ToolbarItem\(placement: \.cancellationAction\) \{")

problems = []
for root in ("App", "Packages/Carpenter/Sources"):
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        text = path.read_text()
        for match in ITEM.finditer(text):
            depth, index = 1, match.end()
            while depth and index < len(text):
                depth += {"{": 1, "}": -1}.get(text[index], 0)
                index += 1
            if ".keyboardShortcut(.cancelAction)" not in text[match.end():index]:
                line = text.count("\n", 0, match.start()) + 1
                problems.append(f"{path}:{line}: a cancellation item without .keyboardShortcut(.cancelAction)")

print("\n".join(problems))
sys.exit(1 if problems else 0)
