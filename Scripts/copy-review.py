#!/usr/bin/env python3
"""Copy review markers: every piece of copy in the docs and the app sits between a pair of them.

    COPY BEGIN <id> [<status>]
    COPY END <id>

in whatever comment the file takes (`//`, `#`, `<!-- -->`). The id is eight hex digits, unique across
the repository. The status is one of the three below, and only a person moves it forward.

    copy-review.py check            fail on an unpaired, nested, duplicated or misspelled marker
    copy-review.py report           count chunks by status, and by file for what is still open
    copy-review.py list [STATUS]    every chunk with that status (default: NEEDS HUMAN REVIEW)
    copy-review.py new-id           an id nothing uses yet, for wrapping new copy by hand
"""
import collections
import pathlib
import re
import secrets
import signal
import subprocess
import sys

STATUSES = ("NEEDS HUMAN REVIEW", "HUMAN REVIEWED, UNVERIFIED", "HUMAN REVIEWED & VERIFIED")
MARKER = re.compile(r"COPY (BEGIN|END) ([0-9a-f]{8})\b(.*)")
STATUS = re.compile(r"^ \[(" + "|".join(re.escape(s) for s in STATUSES) + r")\]")

root = pathlib.Path(__file__).resolve().parent.parent


def files():
    listed = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard"], cwd=root, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    for name in listed:
        path = root / name
        if path.resolve() == pathlib.Path(__file__).resolve() or not path.is_file():
            continue
        try:
            yield name, path.read_text().splitlines()
        except (UnicodeDecodeError, OSError):
            continue


def scan():
    chunks = []
    problems = []
    for name, lines in files():
        open_chunk = None
        for number, line in enumerate(lines, start=1):
            for match in MARKER.finditer(line):
                kind, ident, rest = match.groups()
                where = f"{name}:{number}"
                if kind == "BEGIN":
                    status = STATUS.match(rest)
                    if not status:
                        problems.append(f"{where}: {ident} has no status, or one that is not {' | '.join(STATUSES)}")
                    if open_chunk:
                        problems.append(f"{where}: {ident} begins inside {open_chunk['id']}, which has not ended")
                    open_chunk = {"id": ident, "file": name, "line": number, "status": status.group(1) if status else None}
                    chunks.append(open_chunk)
                elif not open_chunk or open_chunk["id"] != ident:
                    problems.append(f"{where}: {ident} ends, but {open_chunk['id'] if open_chunk else 'nothing'} is open")
                else:
                    open_chunk = None
        if open_chunk:
            problems.append(f"{name}:{open_chunk['line']}: {open_chunk['id']} never ends")
    seen = collections.defaultdict(list)
    for chunk in chunks:
        seen[chunk["id"]].append(f"{chunk['file']}:{chunk['line']}")
    for ident, places in seen.items():
        if len(places) > 1:
            problems.append(f"{ident} is used {len(places)} times: {', '.join(places)}")
    return chunks, problems


def main(argv):
    command = argv[1] if len(argv) > 1 else "check"
    chunks, problems = scan()
    if command == "check":
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1 if problems else 0
    if command == "report":
        counts = collections.Counter(chunk["status"] for chunk in chunks)
        for status in STATUSES:
            print(f"{counts[status]:6d}  {status}")
        print(f"{len(chunks):6d}  chunks")
        open_by_file = collections.Counter(c["file"] for c in chunks if c["status"] == STATUSES[0])
        if open_by_file:
            print()
            for name, count in sorted(open_by_file.items()):
                print(f"{count:6d}  {name}")
        return 1 if problems else 0
    if command == "list":
        wanted = " ".join(argv[2:]) or STATUSES[0]
        if wanted not in STATUSES:
            print(f"unknown status {wanted!r}; one of: {' | '.join(STATUSES)}", file=sys.stderr)
            return 2
        for chunk in chunks:
            if chunk["status"] == wanted:
                print(f"{chunk['file']}:{chunk['line']}  {chunk['id']}")
        return 0
    if command == "new-id":
        taken = {chunk["id"] for chunk in chunks}
        while (ident := secrets.token_hex(4)) in taken:
            pass
        print(ident)
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main(sys.argv))
