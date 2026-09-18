#!/usr/bin/env python3
"""A URL in an xcconfig is cut off at its first double slash, silently.

`APP_X = https://example.com/y` assigns `https:` — the rest is a comment — and the app then holds a
URL with no host, which builds, lints and launches. It opens nothing. Every scheme-bearing value has
to be written with $(SLASH), and this asserts that every one of them still names a host.
"""
import pathlib
import re
import sys
from urllib.parse import urlparse

ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*:")

def main() -> int:
    problems = []
    for path in sorted(pathlib.Path("Config").glob("*.xcconfig")):
        lines = path.read_text().splitlines()

        # Two passes. An xcconfig is resolved by the build system, not read top to
        # bottom, so $(SLASH) is allowed to be defined below the line that uses it —
        # and a one-pass reader flags the correct file. It did, on the first run.
        variables = {}
        for line in lines:
            match = ASSIGN.match(line)
            if match:
                variables[match.group(1)] = match.group(2).split("//", 1)[0].rstrip()

        for number, line in enumerate(lines, start=1):
            match = ASSIGN.match(line)
            if not match:
                continue
            name, raw = match.group(1), match.group(2)
            value = raw.split("//", 1)[0].rstrip()
            if not SCHEME.match(value):
                continue
            expanded = value
            for _ in range(8):
                grown = expanded
                for key, other in variables.items():
                    grown = grown.replace(f"$({key})", other)
                if grown == expanded:
                    break
                expanded = grown
            if not urlparse(expanded).netloc:
                problems.append(
                    f"{path}:{number}: {name} has a scheme and no host — it reads as "
                    f"{expanded!r}. Write the slashes as $(SLASH)$(SLASH)."
                )
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
