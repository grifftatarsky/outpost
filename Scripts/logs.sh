#!/bin/bash
#
# What the app is saying.
#
#   Scripts/logs.sh              — this Mac, last 10 minutes
#   Scripts/logs.sh live         — this Mac, as it happens
#   Scripts/logs.sh device       — launch on a connected iPhone with its console attached
#   Scripts/logs.sh devices      — list connected devices
#
# Categories: pairing, sync, identity.
#
# `log stream --device` is legacy and does not see modern iOS devices. The way to read an iPhone's
# output is to launch the app with `devicectl --console`, which attaches to it — so `device` starts
# the app for you rather than watching one you started by hand.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="$(sed -n 's/^APP_BUNDLE_ID_PREFIX[[:space:]]*=[[:space:]]*//p' "$root/Config/Branding.xcconfig" | tr -d '\r')"
bundle_id="$prefix.carpenter"
PRED="subsystem == \"$bundle_id\""

case "${1:-recent}" in
    live)
        exec log stream --predicate "$PRED" --style compact
        ;;
    devices)
        xcrun devicectl list devices
        ;;
    device)
        # Column 3 is the identifier. Not counted from the right: the Model column contains
        # spaces, so NF-2 lands in the middle of "iPhone 16 (iPhone17,3)".
        udid="${2:-$(xcrun devicectl list devices 2>/dev/null \
            | awk '/connected/ {print $3; exit}')}"
        if [ -z "$udid" ]; then
            echo "No connected device. Plug the iPhone in and trust this Mac." >&2
            exit 1
        fi
        echo "Launching $bundle_id on $udid with the console attached."
        echo "Drive the app; output appears here. Ctrl-C to stop."
        exec xcrun devicectl device process launch \
            --device "$udid" --console --terminate-existing "$bundle_id"
        ;;
    *)
        exec log show --last "${2:-10m}" --predicate "$PRED" --style compact
        ;;
esac
