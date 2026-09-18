#!/bin/bash
#
# Puts a Mac back to "never ran this app".
#
# Local state only. **It cannot clear iCloud** — see the note this prints at the end, because the
# one thing worse than a dirty test is a test you believe is clean.
#
# What it removes:
#   1. The running app, and the built copies under DerivedData and /Applications.
#   2. Application Support containers — the log, the state file, every debug persona, the mailbox.
#   3. Keychain items: the identity, the device key, and every epoch secret.
#
# Usage: Scripts/reset-device.sh [--dry-run]

set -uo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
container="$(sed -n 's/^APP_ICLOUD_CONTAINER[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r')"
bundle_id="$(sed -n 's/^APP_BUNDLE_ID_PREFIX[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r').carpenter"
display_name="$(sed -n 's/^APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r')"

say() { printf '%s\n' "$*"; }
run() {
    if [ "$DRY" -eq 1 ]; then
        say "  would: $*"
    else
        "$@" >/dev/null 2>&1
    fi
}

say "Resetting $display_name ($bundle_id)"
[ "$DRY" -eq 1 ] && say "(dry run — nothing will be removed)"

say ""
say "1. Quitting the app"
run osascript -e "tell application \"$display_name\" to quit"
run pkill -x "$display_name"

say "2. Removing built and installed copies"
run rm -rf "/Applications/$display_name.app"
for path in "$HOME/Library/Developer/Xcode/DerivedData"/Carpenter-*; do
    [ -e "$path" ] && run rm -rf "$path"
done

say "3. Removing local data"
run rm -rf "$HOME/Library/Application Support/$bundle_id"
for path in "$HOME/Library/Application Support/$bundle_id.persona."*; do
    [ -e "$path" ] && run rm -rf "$path"
done
run rm -rf "$HOME/Library/Application Support/$bundle_id.debug-mailbox"
run rm -rf "$HOME/Library/Containers/$bundle_id"
run rm -rf "$HOME/Library/Caches/$bundle_id"
run defaults delete "$bundle_id"

say "4. Removing Keychain items"
# The identity is synchronizable, so deleting it here deletes it from every device on this Apple
# Account. That is the point: a second device holding the identity is exactly what makes a "fresh"
# test not fresh. Epoch secrets are per room and per epoch, so this loops until none are left.
for service in "$bundle_id" "$bundle_id.persona."*; do
    while security delete-generic-password -s "$service" >/dev/null 2>&1; do
        [ "$DRY" -eq 1 ] && break
    done
done
if [ "$DRY" -eq 1 ]; then
    say "  would: delete every generic password for services matching $bundle_id*"
fi

say ""
say "Local state gone. Two things this cannot do:"
say ""
say "  1. The identity lives in iCloud Keychain and is sandboxed — the CLI cannot reach it."
say "     Use the app's own debug menu: ⋯ -> Wipe this device's real account."
say "     Do it with only ONE device installed, or the other syncs it back."
say ""
say "  2. CloudKit records: Console -> ${container/\$(APP_BUNDLE_ID_PREFIX)/com.microgpt} -> Development -> Reset Environment."
say "     https://icloud.developer.apple.com/dashboard/"
say ""
say "Order: in-app wipe, then CloudKit reset, then this script, then reinstall."
