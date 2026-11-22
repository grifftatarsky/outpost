#!/usr/bin/env python3
"""Run swift-format's rules over the Swift files named, and fail on any finding.

Only the rules in .swift-format count. The layout findings swift-format's printer adds (Indentation,
AddLines, Spacing and the rest) are dropped, because the house layout is not swift-format's and the
codebase is not reformatted to it. docs/testing.md has the reasoning.

Usage: Scripts/hooks/swift-format-rules.py FILE...
"""

import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
config = root / ".swift-format"
rules = set(json.loads(config.read_text())["rules"])
finding = re.compile(r"^(?P<where>.+?:\d+:\d+): (?:warning|error): \[(?P<rule>\w+)\] (?P<message>.*)$")

files = [name for name in sys.argv[1:] if name.endswith(".swift")]
if not files:
    sys.exit(0)

result = subprocess.run(
    ["xcrun", "swift-format", "lint", "--parallel", "--no-color-diagnostics", "--configuration", str(config), *files],
    capture_output=True,
    text=True,
)
if result.returncode not in (0, 1):
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)

found = sorted({line for line in result.stderr.splitlines() if (m := finding.match(line)) and m["rule"] in rules})
for line in found:
    print(line)
sys.exit(1 if found else 0)
