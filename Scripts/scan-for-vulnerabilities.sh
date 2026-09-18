#!/bin/bash
# The three checks that stand in for an outside reviewer's first hour.
#
# Griff ruled on 2026-09-14 that the crypto gets a written brief and no commissioned review, on the
# reasoning that the source will be open and a scan runs before TestFlight. The scan did not exist —
# CI ran the two suites, the branding lint and the builds, and nothing else. This is it.
#
# None of these reads a protocol. They catch what a person would not think to look at:
#   1. Dependencies  — code this project did not write and cannot see advisories for.
#   2. Static analysis — what the compiler can prove about memory and nil without running anything.
#   3. Secrets — a key, token or credential committed by accident, anywhere in the history.
#
# Usage: Scripts/scan-for-vulnerabilities.sh [simulator-udid]
set -uo pipefail

UDID="${1:-}"
DEST="platform=iOS Simulator,name=outpost-alpha"
if [ -n "$UDID" ]; then DEST="platform=iOS Simulator,id=$UDID"; fi

status=0
fail() { echo "error: $1"; status=1; }

# ---------------------------------------------------------------- 1. dependencies

echo "== dependencies"
remote=$(grep -c "XCRemoteSwiftPackageReference" App/Carpenter.xcodeproj/project.pbxproj || true)
resolved=$(find . -name "Package.resolved" -not -path "*/.build/*" | head -5)

if [ "$remote" -ne 0 ]; then
    fail "the Xcode project has $remote remote package reference(s). This project has had none, "\
"which is why this check is a count rather than an advisory lookup. Once there is a dependency, "\
"this needs to become a real advisory check."
elif [ -n "$resolved" ]; then
    fail "a Package.resolved exists, so something is being fetched: $resolved"
else
    echo "  none — no remote package references and no Package.resolved."
    echo "  Every line that ships is either this project's or Apple's."
fi

# ---------------------------------------------------------------- 2. static analysis

echo "== static analysis"
if xcodebuild analyze -workspace Carpenter.xcworkspace -scheme Carpenter \
    -destination "$DEST" -derivedDataPath "${DERIVED_DATA:-/tmp/carpenter-analyze}" \
    >/tmp/analyze.log 2>&1; then
    found=$(grep -E "warning:" /tmp/analyze.log | grep -vE "AppIntents|Metadata extraction" | sort -u)
    if [ -n "$found" ]; then
        echo "$found"
        fail "the analyzer reported the warnings above. Answer each or record why it stands."
    else
        echo "  clean."
    fi
else
    fail "the analyze build failed. See /tmp/analyze.log"
fi

# ---------------------------------------------------------------- 3. secrets

echo "== secrets"
# Shapes rather than words: a credential that matters has a recognisable form, and grepping for the
# word "password" finds copy about passwords instead.
SHAPES='(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[0-9A-Za-z-]{10,}|gh[pousr]_[0-9A-Za-z]{30,}|sk-[A-Za-z0-9]{32,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.)'

working=$(git grep -I -n -E "$SHAPES" -- . 2>/dev/null | head -20)
if [ -n "$working" ]; then
    echo "$working"
    fail "something shaped like a credential is in the working tree."
else
    echo "  working tree: clean."
fi

# The history matters as much: a key removed in a later commit is still published once the source is.
history=$(git rev-list --all | head -500 | xargs -I{} git grep -I -l -E "$SHAPES" {} -- 2>/dev/null | head -5)
if [ -n "$history" ]; then
    echo "$history"
    fail "something shaped like a credential appears in the history. Removing it in a later commit "\
"does not unpublish it once the source is open — it has to be rotated."
else
    echo "  history: clean across the last 500 commits."
fi

echo
if [ "$status" -eq 0 ]; then
    echo "vulnerability scan: clean"
else
    echo "vulnerability scan: FAILED"
fi
exit "$status"
