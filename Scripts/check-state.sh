#!/bin/bash
#
# What this Mac still holds for the app, and what it cannot see.
#
# Usage: Scripts/check-state.sh

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="$(sed -n 's/^APP_BUNDLE_ID_PREFIX[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r')"
bundle_id="$prefix.carpenter"
container="iCloud.$prefix.outpost"
name="$(sed -n 's/^APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r')"

mark() { [ "$1" -eq 0 ] && printf '  PRESENT  %s\n' "$2" || printf '  clean    %s\n' "$2"; }

echo "$name — local state"
echo

security find-generic-password -s "$bundle_id" -a device.signing >/dev/null 2>&1
mark $? "device key (local to this Mac)"

# Synchronizable items live in iCloud Keychain and behind the app's sandbox group. The CLI usually
# cannot see them even when they are there, so a "clean" here proves nothing.
security find-generic-password -s "$bundle_id" -a identity.keys >/dev/null 2>&1
found=$?
if [ $found -eq 0 ]; then
    echo "  PRESENT  identity (iCloud Keychain)"
else
    echo "  UNKNOWN  identity (iCloud Keychain) — the CLI cannot read sandboxed synchronizable"
    echo "           items, so this is not evidence of absence. The app's own state is the answer:"
    echo "           a welcome screen means gone, \"Add a device\" means still there."
fi

[ -d "$HOME/Library/Application Support/$bundle_id" ]
mark $? "app data ($HOME/Library/Application Support/$bundle_id)"

ls -d "$HOME/Library/Application Support/$bundle_id.persona."* >/dev/null 2>&1
mark $? "debug personas"

[ -d "/Applications/$name.app" ]
mark $? "/Applications/$name.app"

echo
echo "CloudKit — $container"
echo "  This script cannot query it; CloudKit has no shell interface."
echo "  Console: https://icloud.developer.apple.com/dashboard/"
echo
echo "  If iCloud settings show 'carpenter' and not '$name', that is the OLD container"
echo "  (iCloud.$prefix.carpenter) still holding records. The current build writes to"
echo "  $container, which shows up only once it has data in it."
echo "  Both are worth resetting in the Console; only the new one matters going forward."
