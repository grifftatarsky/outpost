#!/bin/bash
# Does a Release build carry anything only a developer should see?
#
# Gating a debug control's *call site* is not enough. The view behind it is still compiled, so its
# words reach the shipped binary and the string catalogue a translator works from — measured
# 2026-09-15, when `strings` on a Release build returned "Blur every photo", "Rotate mailbox share"
# and "Show message delay" even though every one of them was unreachable.
#
# This builds Release and looks for those words in the binary. It is deliberately about *strings*
# rather than reachability: reachability is what `#if DEBUG` on a call site already gives, and this
# is the thing that survives it.
#
# Usage: Scripts/check-release-leaves.sh [simulator-udid]
set -uo pipefail

UDID="${1:-}"
DEST="platform=iOS Simulator,name=outpost-alpha"
if [ -n "$UDID" ]; then DEST="platform=iOS Simulator,id=$UDID"; fi

DERIVED="${DERIVED_DATA:-/tmp/carpenter-release-check}"

echo "building Release…"
if ! xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
    -configuration Release -destination "$DEST" \
    -derivedDataPath "$DERIVED" build >/tmp/release-check-build.log 2>&1; then
    echo "error: the Release build failed. See /tmp/release-check-build.log"
    exit 1
fi

# Find the bundle rather than deriving its name: the product name lives in Branding.xcconfig and
# reading it out of there by hand is one more thing to get wrong.
APP=$(find "$DERIVED/Build/Products/Release-iphonesimulator" -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP" ]; then
    echo "error: no Release .app under $DERIVED/Build/Products/Release-iphonesimulator"
    exit 1
fi
BINARY="$APP/$(basename "$APP" .app)"
if [ ! -f "$BINARY" ]; then
    echo "error: no Release binary at $BINARY"
    exit 1
fi

# Each of these is a control, a launch argument or a screen that exists only for development.
LEAVES=(
    "site-shot"
    "forget-supporter"
    "Blur every photo"
    "Check mailbox"
    "Rotate mailbox share"
    "Show message delay"
    "Demo conversation"
    "Demo Outpost"
    "reset-account"
    "reset-device"
    "quiet-for-audit"
    "clock-ahead-days"
    "--channel"
    "mailbox-refuses"
    "rig-codes"
    "Haptics probe"
    "Style test"
    "Start over"
)

status=0
for leaf in "${LEAVES[@]}"; do
    if strings "$BINARY" 2>/dev/null | grep -qF -e "$leaf"; then
        echo "error: a Release build contains \"$leaf\""
        status=1
    fi
done

if [ "$status" -eq 0 ]; then
    echo "release leaves: clean — none of ${#LEAVES[@]} developer-only strings are in the binary"
fi
exit "$status"
