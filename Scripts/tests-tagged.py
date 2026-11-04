#!/usr/bin/env python3
"""Print a regular expression for `swift test --filter` or `--skip` that matches every test carrying a tag.

Usage: Scripts/tests-tagged.py TAG
"""

import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1] / "Packages/Carpenter/Tests/CarpenterKitTests"
declaration = re.compile(r"^(\s*)(?:@MainActor\s+)?(?:@Suite(?:\(.*\))?\s+)?(?:private\s+)?(?:final\s+)?(?:struct|class|enum|actor|extension)\s+(\w+)")
function = re.compile(r"\bfunc\s+(\w+)\s*\(")


def tagged(text: str, tag: str) -> bool:
    return any(re.search(rf"\.{tag}\b", group) for group in re.findall(r"\.tags\(([^)]*)\)", text))


def patterns(tag: str) -> list[str]:
    found = []
    for path in sorted(root.glob("*.swift")):
        stack: list[tuple[int, str]] = []
        pending_suite = pending_test = None
        for line in path.read_text().splitlines():
            if pending_test is not None:
                pending_test += line
            if (m := re.match(r"^(\s*)\}\s*$", line)) and stack and stack[-1][0] == len(m.group(1)):
                stack.pop()
                continue
            if m := declaration.match(line):
                indent = len(m.group(1))
                stack = [entry for entry in stack if entry[0] < indent] + [(indent, m.group(2))]
                if pending_suite or (line.lstrip().startswith("@Suite") and tagged(line, tag)):
                    found.append(r"\." + "/".join(name for _, name in stack) + "/")
                pending_suite = None
                if line.count("{") <= line.count("}"):
                    stack.pop()
                continue
            if line.lstrip().startswith("@Suite"):
                pending_suite = tagged(line, tag)
            elif line.lstrip().startswith("@Test"):
                pending_test = line
            if pending_test is not None and (m := function.search(line)):
                if tagged(pending_test, tag):
                    found.append(r"\." + "/".join(name for _, name in stack) + "/" + m.group(1) + r"\(")
                pending_test = None
    return sorted(set(found))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    matched = patterns(sys.argv[1])
    if not matched:
        sys.exit(f"error: no test or suite carries .tags(.{sys.argv[1]})")
    print("|".join(matched))
