#!/usr/bin/env python3
"""The one admin tool trust and safety needs on the dev Mac: add somebody to the deny list.

    Scripts/denylist.py add <fingerprint>      # the 64-hex SHA-256 from a report
    Scripts/denylist.py remove <fingerprint>
    Scripts/denylist.py list

The list lives at Packages/Carpenter/Sources/CarpenterKit/Resources/denylist.json and ships inside
the app (trust and safety decision D5). Nothing fetches it: a change here reaches members with the
next build, and until then their own block is the remedy.

A fingerprint is what a report carries — "Sender fingerprint (SHA-256 of their identifier)" — and
what `DenyList.fingerprint(of:)` computes. The file never holds an identifier itself, only the
hash, so it names nobody to anybody who does not already hold their key.

The date is bumped on every change; the settings footer shows it, so a member can see how old the
list they are relying on is.
"""

import datetime
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILE = ROOT / "Packages/Carpenter/Sources/CarpenterKit/Resources/denylist.json"
FINGERPRINT = re.compile(r"^[0-9a-f]{64}$")


def load() -> dict:
    return json.loads(FILE.read_text(encoding="utf-8"))


def save(data: dict) -> None:
    data["updated"] = datetime.date.today().isoformat()
    data["fingerprints"] = sorted(set(data["fingerprints"]))
    FILE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in {"add", "remove", "list"}:
        print(__doc__, file=sys.stderr)
        return 2

    data = load()
    command = argv[1]

    if command == "list":
        print(f"version {data['version']}, updated {data['updated']}, {len(data['fingerprints'])} entries")
        for entry in data["fingerprints"]:
            print(entry)
        return 0

    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    fingerprint = argv[2].strip().lower()
    if not FINGERPRINT.match(fingerprint):
        print("error: a fingerprint is 64 hex characters — the SHA-256 a report carries", file=sys.stderr)
        return 2

    entries = set(data["fingerprints"])
    if command == "add":
        if fingerprint in entries:
            print("already listed")
            return 0
        entries.add(fingerprint)
    else:
        if fingerprint not in entries:
            print("not listed")
            return 0
        entries.remove(fingerprint)

    data["fingerprints"] = sorted(entries)
    save(data)
    print(f"{command}ed; {len(entries)} entries, updated {data['updated']}. Ship a build.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
