#!/usr/bin/env python3
"""Apply a batch from the copy slideshow to the source.

    apply.py EXPORT            show what the batch would change
    apply.py EXPORT --write    change the source

EXPORT is the directory an export of the slideshow's database was written to: `edits/` holds one
document per string Griff changed (`<chunk>-<index>`) or per note (`<chunk>-note`), and `screens/`
one per screen he marked done, naming its chunks.
"""
import collections
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from swiftcopy import ROOT, chunks, literals, to_swift

REVIEWED = "HUMAN REVIEWED, UNVERIFIED"


def documents(folder):
    if not folder.is_dir():
        return {}
    found = {}
    for path in sorted(folder.glob("*.json")):
        document = json.loads(path.read_text())
        found[path.stem] = document.get("data", document)
    return found


def source_for(rel):
    for base in ("Packages/Carpenter/Sources", "App", ""):
        path = ROOT / base / rel
        if path.exists():
            return path
    for path in ROOT.glob(f"**/{rel}"):
        return path
    raise FileNotFoundError(rel)


def set_status(text, chunk, status):
    return re.sub(
        r"(COPY BEGIN " + chunk + r") \[[^\]]+\]", lambda m: f"{m.group(1)} [{status}]", text, count=1)


def main():
    export = pathlib.Path(sys.argv[1])
    write = "--write" in sys.argv
    edits = documents(export / "edits")
    screens = documents(export / "screens")

    notes = {key[:-5]: doc for key, doc in edits.items() if key.endswith("-note") and doc.get("note", "").strip()}
    changes = [doc for key, doc in edits.items() if not key.endswith("-note") and doc.get("proposed") != doc.get("original")]
    finished = {chunk for doc in screens.values() if doc.get("done") for chunk in doc.get("chunks", [])}

    by_file = collections.defaultdict(list)
    removals = []
    for doc in changes:
        if not doc.get("proposed", "").strip():
            removals.append(doc)
        else:
            by_file[doc["file"]].append(doc)

    applied, missing, reviewed = [], [], set()
    touched = {}
    for rel, docs in by_file.items():
        path = source_for(rel)
        text = touched.get(path) or path.read_text()
        regions = {cid: (begin, end) for cid, _, begin, end in chunks(text)}
        plan = []
        for doc in docs:
            if doc["chunk"] not in regions:
                missing.append((rel, doc, "its chunk is no longer in the file"))
                continue
            begin, end = regions[doc["chunk"]]
            taken = {step[0] for step in plan}
            found = [
                literal for literal in literals(text[begin:end], begin)
                if literal[3].strip() == doc["original"].strip() and literal[0] not in taken
            ]
            if not found:
                missing.append((rel, doc, "the original words are not in the chunk"))
                continue
            start, stop, _, _, placeholders, multi = found[0]
            if multi:
                line_start = text.rfind("\n", 0, start) + 1
                indent = re.match(r"\s*", text[line_start:start]).group(0) + "    "
                literal = '"""' + to_swift(doc["proposed"], placeholders, indent=indent) + '"""'
            else:
                literal = '"' + to_swift(doc["proposed"], placeholders) + '"'
            plan.append((start, stop, literal, doc))
        for start, stop, literal, doc in sorted(plan, key=lambda step: -step[0]):
            text = text[:start] + literal + text[stop:]
            applied.append((rel, doc, literal))
            reviewed.add(doc["chunk"])
        touched[path] = text

    for chunk in finished:
        if chunk in notes or any(doc["chunk"] == chunk for doc in removals):
            continue
        reviewed.add(chunk)
    sources = [
        *ROOT.glob("App/**/*.swift"), *ROOT.glob("App/**/*.plist"), *ROOT.glob("Config/*.xcconfig"),
        *ROOT.glob("Packages/Carpenter/Sources/**/*.swift"),
    ]
    for path in list(dict.fromkeys(list(touched) + sources)):
        text = touched.get(path) or path.read_text()
        changed = text
        for chunk in reviewed:
            if f"COPY BEGIN {chunk} " in changed:
                changed = set_status(changed, chunk, REVIEWED)
        if changed != text or path in touched:
            touched[path] = changed

    print(f"{len(applied)} change(s) to words, {len(reviewed)} chunk(s) to mark {REVIEWED}")
    for rel, doc, literal in applied:
        print(f"  {rel} [{doc['chunk']}] {doc['original'][:60]!r} -> {doc['proposed'][:60]!r}")
    if removals:
        print(f"\n{len(removals)} removal(s) to make by hand (the code around them has to go too):")
        for doc in removals:
            print(f"  {doc['file']}:{doc.get('line')} [{doc['chunk']}] {doc['original'][:80]!r}")
    if notes:
        print(f"\n{len(notes)} note(s):")
        for chunk, doc in notes.items():
            print(f"  [{chunk}] {doc.get('file', '')}: {doc['note']}")
    if missing:
        print(f"\n{len(missing)} change(s) not found:")
        for rel, doc, why in missing:
            print(f"  {rel} [{doc['chunk']}] {why}: {doc['original'][:60]!r}")

    if write:
        for path, text in touched.items():
            if text != path.read_text():
                path.write_text(text)
        print("\nwritten")
    else:
        print("\nnothing written; add --write")


if __name__ == "__main__":
    main()
