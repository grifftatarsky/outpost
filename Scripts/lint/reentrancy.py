#!/usr/bin/env python3
"""A nil check and the assignment that makes it false, with an `await` in between.

An actor is **reentrant**. Between a `guard x == nil else { return }` and the `x = …` that makes it
false, every `await` hands the actor to whoever else is waiting — and a second caller walks straight
past a check that is about to stop being true. Both then do the whole thing.

`CloudKitEntrySync.start()` had exactly this: a nil check on the engine, two awaits, then the
assignment. Two callers reach it concurrently in the ordinary case — `AppSession.syncDevices` brings
the engine up in one task while the first `sync()` reaches `refresh()` in another — and the result
would be two `CKSyncEngine`s, one of them orphaned but alive with a live delegate.

The fix is to hold the in-flight work as a `Task` and have the second caller await it, so "start
returned" means "the engine is up" for everybody.

Deliberately shape-based rather than clever: it reads Swift as lines, and it is meant to be
over-eager rather than exhaustive. A site that has genuinely thought about it says
`reentrancy considered` on one of the lines between the two.
"""
import pathlib
import re
import sys

CHECK = re.compile(r"^\s*(?:guard|if)\s+(?:let\s+\w+\s*=\s*)?(?:self\.)?(\w+)\s*(?:==|!=)\s*nil")
WINDOW = 40


def scan(roots: list[str]) -> list[str]:
    findings: list[str] = []
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.swift")):
            if ".build" in str(path):
                continue
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
            for index, line in enumerate(lines):
                match = CHECK.match(line)
                if not match:
                    continue
                name = match.group(1)
                assign = re.compile(rf"^\s*(?:self\.)?{re.escape(name)}\s*=[^=]")
                saw_await = False
                for offset in range(index + 1, min(index + WINDOW, len(lines))):
                    body = lines[offset]
                    if "await" in body:
                        saw_await = True
                    if "reentrancy considered" in body:
                        break
                    if saw_await and assign.match(body):
                        findings.append(
                            f"{path}:{index + 1}: `{line.strip()}` is separated from "
                            f"`{body.strip()}` (line {offset + 1}) by an await"
                        )
                        break
    return findings


if __name__ == "__main__":
    roots = sys.argv[1:] or ["Packages/Carpenter/Sources", "App"]
    found = scan(roots)
    for line in found:
        print(line)
    sys.exit(1 if found else 0)
