#!/bin/bash
#
# Everything CI runs, run on this Mac, ending in a short digest of what failed.
#
# Every step runs even when an earlier one fails, so one run finds every kind of fault at once: a
# package suite that does not compile says nothing about whether the app does. The full output of
# each step is kept as a log. The digest keeps only the errors, the failed tests, and the warnings in
# files this branch changed; it is printed at the end and copied to the clipboard, so it can be
# pasted straight back into the session that asked for the run.
#
# Usage: Scripts/check-all.sh [simulator-name]    (default: outpost-alpha)

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

simulator="${1:-outpost-alpha}"
logs="${TMPDIR:-/tmp}/carpenter-check"
digest="$logs/digest.txt"
rm -rf "$logs"
mkdir -p "$logs"

base="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)"
changed="$( [ -n "$base" ] && git diff --name-only "$base" HEAD -- '*.swift' )"

{
    printf 'branch %s at %s\n' "$(git rev-parse --abbrev-ref HEAD)" "$(git rev-parse --short HEAD)"
    xcodebuild -version 2>/dev/null | head -1
    [ -n "$(git status --porcelain)" ] && printf 'the working tree has uncommitted changes\n'
} >"$digest"

summary=()
failed=0

faults() {
    python3 - "$1" "$2" "$changed" <<'PY'
import re
import sys

log, outcome = sys.argv[1], sys.argv[2]
changed = [path for path in sys.argv[3].splitlines() if path]
lines = open(log, errors="replace").read().splitlines()

header = re.compile(r"^(/\S+?):\d+:\d+: (error|warning): ")
continues = re.compile(r"^(\s|\d|\||\[#|:)")
test_fault = re.compile(
    r"recorded an issue|Test run with .* failed|Suite .* failed|error: -\[|Test Case .* failed|"
    r"Executed \d+ tests?, with [1-9]|Fatal error|Assertion failed|Precondition failed|"
    r"unexpected signal|crashed|\*\* (BUILD|TEST) FAILED \*\*|Testing failed:|"
    r"The following build commands failed|Undefined symbols|^ld: |^error: (?!SwiftCompile)"
)

out, seen = [], set()
index = 0
while index < len(lines):
    line = lines[index]
    match = header.match(line)
    if match:
        path, kind = match.group(1), match.group(2)
        block = [line]
        index += 1
        while index < len(lines) and continues.match(lines[index]) and len(block) < 25:
            block.append(lines[index])
            index += 1
        mine = any(path.endswith("/" + name) for name in changed)
        wanted = mine if kind == "warning" else outcome == "failed"
        if wanted and line not in seen:
            seen.add(line)
            out.extend(block)
        continue
    if outcome == "failed" and len(line) < 400 and test_fault.search(line) and line not in seen:
        seen.add(line)
        out.append(line)
        index += 1
        taken = 0
        while (
            index < len(lines) and taken < 8 and len(lines[index]) < 400
            and not re.match(r"^\S*\s*(Test|Suite)\b|^\s*$", lines[index])
            and not header.match(lines[index])
        ):
            out.append(lines[index])
            index += 1
            taken += 1
        continue
    index += 1

if not out and outcome == "failed":
    out = [line for line in lines[-40:] if len(line) < 400]
print("\n".join(out[:200]))
if len(out) > 200:
    print(f"… {len(out) - 200} more lines in {log}")
PY
}

run() {
    local name="$1"
    shift
    printf '%-18s' "$name"
    local started=$SECONDS
    if "$@" >"$logs/$name.log" 2>&1; then
        printf 'passed   %4ss\n' $((SECONDS - started))
        summary+=("passed   $name")
        local warnings
        warnings="$(faults "$logs/$name.log" passed)"
        [ -n "$warnings" ] && printf '\n=== %s passed, with warnings in files this branch changed ===\n%s\n' \
            "$name" "$warnings" >>"$digest"
        return 0
    fi
    printf 'FAILED   %4ss   %s\n' $((SECONDS - started)) "$logs/$name.log"
    summary+=("FAILED   $name")
    failed=1
    { printf '\n=== %s ===\n' "$name"; faults "$logs/$name.log" failed; } >>"$digest"
    return 1
}

skip() {
    printf '%-18sskipped  (%s)\n' "$1" "$2"
    summary+=("skipped  $1 ($2)")
}

package_suite() { (cd Packages/Carpenter && swift test); }
build_for() {
    xcodebuild build -workspace Carpenter.xcworkspace -scheme Carpenter -destination "$1" \
        CODE_SIGNING_ALLOWED=NO -quiet
}
app_suite() {
    xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter \
        -destination "platform=iOS Simulator,name=$simulator" -only-testing:CarpenterTests -quiet
}

run package-suite package_suite
run lint ./Scripts/lint-branding.sh
run copy-markers python3 Scripts/copy-review.py check
run build-macos build_for "platform=macOS"
if run build-ios build_for "generic/platform=iOS Simulator"; then
    run app-suite app_suite
    run release-leaves ./Scripts/check-release-leaves.sh
else
    skip app-suite "the iOS build failed"
    skip release-leaves "the iOS build failed"
fi

{
    printf '\n=== summary ===\n'
    printf '%s\n' "${summary[@]}"
} >>"$digest"

printf '\n'
cat "$digest"
printf '\nFull logs: %s\n' "$logs"
if command -v pbcopy >/dev/null; then
    pbcopy <"$digest"
    printf 'The digest is on the clipboard.\n'
fi
exit $failed
