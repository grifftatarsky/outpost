#!/usr/bin/env python3
"""Swift carries no comments but the ones a tool reads.

19,000 lines of comments were deleted on 2026-09-12 because they described fixes no longer in the
build. By 2026-09-19, 326 had been written again, every one by Claude, and Griff asked for them gone
and for it to stop. What survives is `// MARK:`, `swift-tools-version` and the five markers the
lints read as mechanism. Anything worth keeping goes in docs/, never above a line. The one note
Griff asked for by name, on 2026-09-19, is listed in REQUESTED by its exact words: why the app's old
names stay in Branding.swift.
"""
import pathlib
import re
import sys

REQUESTED = {
    "Packages/Carpenter/Sources/CarpenterKit/Branding.swift": {
        "// Every name this app has shipped under. Recovery keys saved under an old name must keep opening,"
        " so a rename adds here and never removes.",
    },
}

ALLOWED = re.compile(
    r"^//\s*(MARK:|swift-tools-version|cross-fade only|divides regions|intentionally empty"
    r"|reentrancy considered)"
)
STRING_OPEN = re.compile(r'(#*)("""|")')


def comment_spans(src):
    spans, stack = [], []
    i, n = 0, len(src)
    while i < n:
        top = stack[-1] if stack else None
        if top and top[0] == "str":
            _, hashes, multi = top
            if src.startswith("\\" + "#" * hashes + "(", i):
                stack.append(["interp", 0])
                i += 2 + hashes
                continue
            if hashes == 0 and src[i] == "\\":
                i += 2
                continue
            closer = ('"""' if multi else '"') + "#" * hashes
            if src.startswith(closer, i):
                stack.pop()
                i += len(closer)
                continue
            i += 1
            continue
        if top and top[0] == "interp":
            if src[i] == "(":
                top[1] += 1
            elif src[i] == ")":
                if top[1] == 0:
                    stack.pop()
                    i += 1
                    continue
                top[1] -= 1
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j == -1 else j
            spans.append((i, j))
            i = j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            spans.append((i, j))
            i = j
            continue
        m = STRING_OPEN.match(src, i)
        if m:
            stack.append(("str", len(m.group(1)), m.group(2) == '"""'))
            i = m.end()
            continue
        i += 1
    return spans


problems = []
for root in ("App", "Packages/Carpenter/Sources", "Packages/Carpenter/Tests"):
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        if ".build" in path.parts:
            continue
        source = path.read_text()
        for start, end in comment_spans(source):
            text = source[start:end].strip()
            if not ALLOWED.match(text) and text not in REQUESTED.get(str(path), set()):
                line = source.count("\n", 0, start) + 1
                problems.append(f"{path}:{line}: {text.splitlines()[0][:100]}")

print("\n".join(problems))
sys.exit(1 if problems else 0)
