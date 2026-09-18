#!/usr/bin/env python3
"""A control's label is sentence case, like every other one beside it.

The app's settings rows read *Color*, *App icon*, *Inbox*, *Tags*, *Share my name*, *Blur sensitive
photos*. One read *User Avatars* — title case, and "user", which the copy guide reserves for legal
text and forbids in anything a member reads. It sat among sentence-case neighbours for months and
nobody saw it, which is what a sweep is for and what a rule is for afterwards.

A proper noun keeps its capitals, so the list below is the exception table: Apple's own feature names
("Sensitive Content Warning" is a real iOS setting), the app's own nouns, and the platform's. Add to
it rather than loosening the rule — a name that genuinely is a name is a one-line change here.

Only `title:` labels are checked. Body copy is prose and is the copy guide's business, not a lint's.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2] / "Packages/Carpenter/Sources/CarpenterUI"

PROPER = {
    # The product's own nouns
    "Outpost", "Outposts", "Supporter", "Solo", "Solos", "You",
    # Apple's features and platforms, spelled the way Apple spells them
    "Apple", "Account", "Keychain", "iCloud", "Face", "ID", "App", "Store", "TestFlight",
    "VoiceOver", "Photos", "Messages", "Contacts", "Settings", "Focus", "Dynamic", "Type",
    "Do", "Not", "Disturb", "Mac", "iPhone", "iPad", "Siri", "Shortcuts", "CloudKit", "QR",
    "Live", "Reduce", "Motion", "Sensitive", "Content", "Warning", "Privacy", "Safety",
    # An English word that is capitalised wherever it falls
    "I",
}

LABEL = re.compile(r'title:\s*Text\(\s*"([^"]{2,60})"')
WORD = re.compile(r"[A-Za-z][A-Za-z'’]*")


def flagged(path: pathlib.Path) -> list[tuple[int, str, list[str]]]:
    lines = path.read_text().splitlines()
    out = []
    for i, line in enumerate(lines):
        if "title:" not in line:
            continue
        match = LABEL.search(line) or LABEL.search(" ".join(x.strip() for x in lines[i : i + 3]))
        if not match:
            continue
        words = WORD.findall(match.group(1))
        if len(words) < 2:
            continue
        shouting = [w for w in words[1:] if w[:1].isupper() and w not in PROPER and "'" not in w
                    and "’" not in w]
        if shouting:
            out.append((i + 1, match.group(1), shouting))
    return out


def main() -> int:
    for path in sorted(ROOT.rglob("*.swift")):
        if "Previews" in path.name or "/Debug/" in str(path):
            continue
        for line_number, label, words in flagged(path):
            print(
                f"  {path.relative_to(ROOT.parents[2])}:{line_number}: "
                f'"{label}" — {", ".join(words)}'
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
