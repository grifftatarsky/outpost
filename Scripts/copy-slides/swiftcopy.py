import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ["App", "Packages/Carpenter/Sources"]
MARK = re.compile(r"COPY (BEGIN|END) ([0-9a-f]{8})\b(?: \[([^\]]+)\])?")

def literals(text, base=0):
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if text[i] == '"':
            multi = text.startswith('"""', i)
            q = '"""' if multi else '"'
            j = i + len(q); out = []; ph = {}
            while j < n:
                if text.startswith("\\(", j):
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if text[k] == "(": depth += 1
                        elif text[k] == ")": depth -= 1
                        elif text[k] == '"':
                            k = text.find('"', k + 1)
                        k += 1
                    expr = text[j + 2:k - 1].strip()
                    name = "app name" if expr == "Branding.displayName" else expr.split("(")[0].split(".")[-1].strip()
                    ph[name] = expr
                    out.append("{" + name + "}"); j = k; continue
                if text[j] == "\\" and j + 1 < n:
                    out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(text[j + 1], text[j + 1])); j += 2; continue
                if text.startswith(q, j): break
                out.append(text[j]); j += 1
            rendered = "".join(out)
            if multi:
                rendered = rendered[1:] if rendered.startswith("\n") else rendered
                lines = rendered.split("\n")
                ind = min((len(x) - len(x.lstrip(" ")) for x in lines if x.strip()), default=0)
                rendered = "\n".join(x[ind:] for x in lines).rstrip()
            rendered = re.sub(r"\^\[([^\]]*)\]\(inflect: true\)", r"\1", rendered)
            yield (base + i, base + j + len(q), text[i + len(q):j], rendered, ph, multi)
            i = j + len(q); continue
        i += 1

def chunks(text):
    open_ = None
    for m in MARK.finditer(text):
        if m.group(1) == "BEGIN":
            open_ = (m.group(2), m.group(3), text.find("\n", m.end()) + 1)
        elif open_ and open_[0] == m.group(2):
            yield open_[0], open_[1], open_[2], text.rfind("\n", 0, m.start()) + 1
            open_ = None

def to_swift(rendered, ph, indent=None):
    names = dict(ph)
    names.setdefault("app name", "Branding.displayName")
    parts = re.split(r"(\{[^{}]+\})", rendered)
    out = []
    for p in parts:
        m = re.fullmatch(r"\{([^{}]+)\}", p)
        if m and m.group(1) in names:
            out.append("\\(" + names[m.group(1)] + ")")
            continue
        seg = p.replace("\\", "\\\\")
        if indent is None:
            seg = seg.replace('"', '\\"').replace("\n", "\\n")
        seg = re.sub(r"\bOutpost\b", "\\\\(Branding.displayName)", seg)
        out.append(seg)
    body = "".join(out)
    if indent is not None:
        lines = body.split("\n")
        body = "\n" + "\n".join((indent + l).rstrip() if l.strip() else "" for l in lines) + "\n" + indent
    return body
