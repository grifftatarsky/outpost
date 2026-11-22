import json, re, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from extract import AREAS, main as extract, area_of
from swiftcopy import ROOT

def human(stem):
    s = stem.split("+")[0]
    s = re.sub(r"(View|Screens|Sheet|Previews)$", "", s)
    w = re.sub(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", s).strip()
    w = w[:1].upper() + w[1:].lower() if w else stem
    extra = stem.split("+")[1:]
    return w + (" (" + ", ".join(re.sub(r"(?<=[a-z])(?=[A-Z])", " ", e).lower() for e in extra) + ")" if extra else "")

ELEMENTS = [
    (r"\.navigationTitle\(", "title"), (r"header:\s*\{", "heading"), (r"footer:\s*\{", "note under it"),
    (r"\.sectionHeading\(\)", "heading"), (r"SettingsHeaderCard\(", "card"), (r"paragraph:", "card text"),
    (r"message:\s*\{", "message"), (r"\.alert\(", "alert title"), (r"\.confirmationDialog\(", "sheet title"),
    (r"ChoiceRow\(", "choice"), (r"SettingsToggle\(|Toggle\(", "switch"), (r"SettingsRow\(", "row"),
    (r"detail:", "row value"), (r"prompt:|TextField\(", "field placeholder"),
    (r"\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityValue\(", "VoiceOver text"),
    (r"ContentUnavailableView", "empty state"), (r"Button", "button"), (r"Label\s*\{|Label\(", "label"),
    (r"String\(\s*$|localized:", "message"),
]
def element_of(src, line):
    lines = src.split("\n")
    here = lines[line - 1] if 0 < line <= len(lines) else ""
    window = "\n".join(lines[max(0, line - 4):line])
    for pat, name in ELEMENTS:
        if re.search(pat, here): return name
    for pat, name in ELEMENTS:
        if re.search(pat, window): return name
    return "text"

def plural(name, n):
    if n == 1: return name
    irregular = {"VoiceOver": "VoiceOver labels", "card text": "card texts", "text": "texts", "switch": "switches",
                 "empty-state text": "empty-state texts", "alert message": "alert messages", "row value": "row values"}
    return irregular.get(name, name + "s")

def where_of(body, heading, screen, component, els=None):
    place = f"the {screen} {'piece' if component else 'screen'}"
    if re.search(r"\.alert\(", body): return f"An alert on {place}"
    if re.search(r"\.confirmationDialog\(", body): return f"A confirmation sheet on {place}"
    if re.search(r"ContentUnavailableView", body): return f"What {place} shows when there is nothing to list"
    if re.search(r"SettingsHeaderCard\(", body): return f"The card at the top of {place}"
    if re.search(r"\.navigationTitle\(", body) and els and all(e in ("Screen title", "Button") for e in els):
        return f"The top bar of {place}"
    if re.search(r"\.navigationTitle\(", body): return f"{place[0].upper()}{place[1:]}, with its title"
    if heading: return f"The “{heading}” part of {place}"
    return f"Part of {place}"

def sentence(body, src, strings, screen, heading, note, component):
    if note and re.search(r"localized:", body) and not re.search(r"Text\(", body):
        return f"Shown by the app: {note[0].lower() + note[1:]}."
    counts = {}
    for s_ in strings:
        e = el_of(s_, src).lower().replace("voiceover", "VoiceOver")
        counts[e] = counts.get(e, 0) + 1
    def phrase(k, n):
        if n > 1: return f"{n} {plural(k, n)}"
        if k == "VoiceOver": return "a VoiceOver label"
        if k == "text": return "text"
        return ("an " if k[0] in "aeiou" else "a ") + k
    parts = [phrase(k, n) for k, n in counts.items()]
    listed = ", ".join(parts[:-1]) + (" and " if len(parts) > 1 else "") + parts[-1] if parts else "text"
    els = [el_of(s_, src) for s_ in strings]
    return f"{where_of(body, heading, screen, component, els)}: {listed}."

CONSTRUCTORS = [
    (r"\.navigationTitle\(", {"": "Screen title"}),
    (r"SettingsToggle\(|Toggle\(", {"title": "Switch", "detail": "Switch detail", "": "Switch"}),
    (r"SettingsHeaderCard\(", {"title": "Card title", "paragraph": "Card text", "": "Card text"}),
    (r"ChoiceRow\(", {"title": "Choice", "detail": "Choice detail", "": "Choice"}),
    (r"SettingsRow\(", {"title": "Row", "detail": "Row value", "value": "Row value", "": "Row"}),
    (r"ActionProblem\(|\.alert\(|Alert\(", {"title": "Alert title", "message": "Alert message", "": "Alert title"}),
    (r"\.confirmationDialog\(", {"": "Sheet title", "message": "Sheet message"}),
    (r"ContentUnavailableView", {"": "Empty-state text", "title": "Empty-state title", "description": "Empty-state text"}),
    (r"\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityValue\(", {"": "VoiceOver"}),
    (r"TextField\(|SecureField\(|prompt:", {"": "Placeholder"}),
    (r"header:\s*\{", {"": "Heading"}),
    (r"footer:\s*\{", {"": "Footnote"}),
    (r"Button\s*\(|Button\s*\{|Button\(role|Label\(|\bLink\(", {"": "Button"}),
]
def indent(line): return len(line) - len(line.lstrip())

def el_of(s, src):
    role = (s.get("role") or "").lower()
    if "voiceover" in role: return "VoiceOver"
    lines = src.split("\n"); n = (s.get("line") or 0) - 1
    if not (0 <= n < len(lines)): return "Message" if "localized" in role else "Text"
    here = lines[n]
    after = "\n".join(lines[n:n + 4])
    label = re.match(r"\s*(\w+):", here)
    label = label.group(1) if label else ""
    for pat, labels in CONSTRUCTORS:
        if re.search(pat, here):
            return labels.get(label, labels.get("", "Text"))
    if re.search(r"\.sectionHeading\(\)", "\n".join(lines[n:n + 3])): return "Heading"
    frontier = indent(here) if here.strip() else 999
    for k in range(n - 1, max(-1, n - 40), -1):
        line = lines[k]
        if not line.strip() or indent(line) >= frontier: continue
        frontier = indent(line)
        if re.search(r"^\s*(var|func|case|private|public|let|struct|init)\b|COPY END", line): break
        if re.search(r"\}\s*label:\s*\{", line): return "Button"
        for pat, labels in CONSTRUCTORS:
            if re.search(pat, line):
                return labels.get(label, labels.get("", "Text"))
    m = re.search(r"\.font\((?:CarpenterFont)?\.?(\w+)", after)
    if m:
        f = m.group(1)
        if f.startswith("title") or f == "largeTitle": return "Title"
        if f in ("headline", "sectionHeading"): return "Heading"
        if f in ("footnote", "caption", "caption2"): return "Footnote"
        if f == "rowTitle": return "Row"
    if "String(localized" in here or "localized:" in here or re.search(r"String\(\s*$", lines[n - 1] if n else ""): return "Message"
    return "Text"

def build(new_ids):
    source_cache = {}
    slides = []
    data = extract()
    order = {k: i for i, (k, _, _) in enumerate(AREAS)}
    for area, screens in data.items():
        for stem, chunks in screens.items():
            file = chunks[0]["file"]
            full = next(ROOT.glob(f"**/{file}"), None) if not file.startswith("App/") else ROOT / file
            if full is None:
                cands = list(ROOT.glob(f"Packages/Carpenter/Sources/{file}"))
                full = cands[0] if cands else None
            src = full.read_text() if full and full.exists() else ""
            component = "/Components/" in file or "/Presentation/" in file or file.startswith("Carpenter") and "/Screens/" not in file
            screen = human(stem)
            areas = []
            last_heading = None
            for c in chunks:
                m = re.search(r"COPY BEGIN %s \[([^\]]+)\]" % c["id"], src)
                status = m.group(1) if m else c.get("status")
                a = src.find("COPY BEGIN " + c["id"]); b = src.find("COPY END " + c["id"])
                body = src[a:b] if a >= 0 and b > a else ""
                heading = next((s["text"] for s in c["strings"] if s.get("role") in ("Section heading", "Header", "Screen title", "Title")), None)
                note = next((s.get("note") for s in c["strings"] if s.get("note")), None)
                k = "area"
                ctx = sentence(body, src, c["strings"], screen, heading or last_heading, note, component)
                if heading: last_heading = heading
                areas.append({"id": c["id"], "status": status, "context": ctx, "kind": k, "new": c["id"] in new_ids,
                              "strings": [{"i": i, "text": s["text"], "role": s.get("role"), "when": s.get("when"),
                                           "line": s.get("line"), "el": el_of(s, src)} for i, s in enumerate(c["strings"])],
                              "file": file, "line": c.get("line")})
            slides.append({"key": stem, "name": screen, "area": area, "file": file, "component": component,
                           "areas": areas, "new": any(x["new"] for x in areas)})
    slides.sort(key=lambda s: (order.get(s["area"], 99), s["name"]))
    return slides

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    new = set(json.load(open(sys.argv[2]))) if len(sys.argv) > 2 else set()
    out.mkdir(parents=True, exist_ok=True)
    slides = build(new)
    json.dump(slides, open(out / "slides.json", "w"), ensure_ascii=False, indent=1)
    print(len(slides), "slides;", sum(len(s["areas"]) for s in slides), "areas;", sum(1 for s in slides if s["new"]), "with new copy")
