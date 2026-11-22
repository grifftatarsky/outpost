#!/usr/bin/env python3
"""Checks over what is staged for a commit: only the lines and files a commit adds, never the rest.

    staged.py whitespace     trailing whitespace and merge markers on added lines
    staged.py large          a staged file over LARGE_FILE_BYTES
    staged.py secrets        a credential, a signing file, the Team ID or an account email
    staged.py secrets --tree     the credential shapes and signing files over every tracked file
    staged.py secrets --history  the same over every commit's changes, on every branch
"""

import pathlib
import re
import subprocess
import sys

LARGE_FILE_BYTES = 512 * 1024

CREDENTIAL_SHAPES = [
    "AKIA[0-9A-Z]{16}",
    "-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "xox[baprs]-[0-9A-Za-z-]{10,}",
    "gh[pousr]_[0-9A-Za-z]{30,}",
    "github_pat_[0-9A-Za-z_]{40,}",
    "sk-[A-Za-z0-9]{32,}",
    "sk-ant-[a-z0-9]+-[A-Za-z0-9_-]{32,}",
    "AIza[0-9A-Za-z_-]{35}",
    "[rs]k_live_[0-9A-Za-z]{20,}",
    "eyJ[A-Za-z0-9_-]{20,}[.][A-Za-z0-9_-]{20,}[.]",
]
ACCOUNT_EMAIL = "[A-Za-z0-9._%+-]+[@](icloud|me|mac|privaterelay[.]appleid)[.]com"
SIGNING_FILES = re.compile(
    r"(\.(p8|p12|pfx|mobileprovision|provisionprofile|cer|der|pem|key|keystore|jks)|(^|/)\.env)$", re.I
)
PROJECT = "App/Carpenter.xcodeproj/project.pbxproj"

root = pathlib.Path(
    subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, errors="replace").stdout


def staged_paths() -> list[str]:
    return [p for p in git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split("\0") if p]


def added_lines() -> dict[str, list[tuple[int, str]]]:
    lines: dict[str, list[tuple[int, str]]] = {}
    path, number, old_left, new_left = None, 0, 0, 0
    hunk = re.compile(r"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
    diff = git("diff", "--cached", "-U0", "--no-color", "--no-ext-diff", "--diff-filter=ACMR")
    for line in diff.splitlines():
        if old_left or new_left:
            if line.startswith("-"):
                old_left -= 1
            elif line.startswith("+"):
                if path:
                    lines.setdefault(path, []).append((number, line[1:]))
                number += 1
                new_left -= 1
        elif line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif match := hunk.match(line):
            old_left = int(match.group(1) or 1)
            number = int(match.group(2))
            new_left = int(match.group(3) or 1)
    return lines


def report(findings: list[str], why: str) -> int:
    if not findings:
        return 0
    print(why)
    for finding in findings:
        print("  " + finding[:300])
    return 1


def whitespace() -> int:
    findings = []
    for path, lines in added_lines().items():
        if path.endswith((".patch", ".diff")):
            continue
        markers = [(n, t) for n, t in lines if re.match(r"(<{7}|>{7}|\|{7})( |$)", t)]
        if markers:
            markers += [(n, t) for n, t in lines if t == "======="]
        findings += [f"{path}:{n}: merge marker" for n, t in sorted(markers)]
        for number, text in lines:
            trailing = len(text) - len(text.rstrip(" \t"))
            markdown_break = path.endswith(".md") and text.endswith("  ") and trailing == 2
            if trailing and not markdown_break:
                findings.append(f"{path}:{number}: trailing whitespace")
    return report(findings, "error: whitespace or a merge marker on a line this commit adds:")


def large() -> int:
    findings = []
    for path in staged_paths():
        size = git("cat-file", "-s", f":{path}").strip()
        if size.isdigit() and int(size) > LARGE_FILE_BYTES:
            findings.append(f"{path}: {int(size) // 1024} KB")
    return report(findings, f"error: a staged file is over {LARGE_FILE_BYTES // 1024} KB (SKIP=large-files to commit it anyway):")


def team_id() -> str | None:
    match = re.search(r"DEVELOPMENT_TEAM = ([A-Z0-9]{10});", git("show", f"HEAD:{PROJECT}") or git("show", f":{PROJECT}"))
    return match.group(1) if match else None


def secrets_staged() -> int:
    shapes = [re.compile(shape) for shape in CREDENTIAL_SHAPES]
    personal = [re.compile(ACCOUNT_EMAIL)]
    own_email = git("config", "user.email").strip()
    if own_email:
        personal.append(re.compile(re.escape(own_email), re.I))
    team = team_id()
    findings = [f"{path}: a signing or key file" for path in staged_paths() if SIGNING_FILES.search(path)]
    for path, lines in added_lines().items():
        for number, text in lines:
            if any(shape.search(text) for shape in shapes):
                findings.append(f"{path}:{number}: shaped like a credential")
            if any(pattern.search(text) for pattern in personal):
                findings.append(f"{path}:{number}: an account email address")
            if team and team in text and path != PROJECT:
                findings.append(f"{path}:{number}: the Apple Team ID, which belongs only in {PROJECT}")
    return report(findings, "error: this commit adds something that should not be published:")


def credential_pattern() -> str:
    return "|".join(f"({shape})" for shape in CREDENTIAL_SHAPES)


def secrets_tree() -> int:
    findings = git("grep", "-I", "-n", "-E", credential_pattern(), "--", ".").splitlines()
    findings += [f"{path}: a signing or key file" for path in git("ls-files", "-z").split("\0") if path and SIGNING_FILES.search(path)]
    return report(findings[:40], "error: something shaped like a credential is in the working tree:")


def secrets_history() -> int:
    log = git("log", "--all", "-E", "-G", credential_pattern(), "--format=commit %h %s", "--name-only")
    signing = git("log", "--all", "--format=commit %h %s", "--name-only", "--diff-filter=A")
    findings = [line for line in log.splitlines() if line]
    current = ""
    for line in signing.splitlines():
        if line.startswith("commit "):
            current = line
        elif line and SIGNING_FILES.search(line):
            findings.append(f"{current}: {line}, a signing or key file")
    return report(findings[:40], "error: a commit in the history adds or removes something shaped like a credential:")


def main(argv: list[str]) -> int:
    check = argv[1] if len(argv) > 1 else ""
    if check == "whitespace":
        return whitespace()
    if check == "large":
        return large()
    if check == "secrets" and argv[2:3] == ["--tree"]:
        return secrets_tree()
    if check == "secrets" and argv[2:3] == ["--history"]:
        return secrets_history()
    if check == "secrets":
        return secrets_staged()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
