#!/bin/bash
#
# Pull Carpenter/Outpost diagnostics off every connected device without a console.
#
# The app mirrors its own unified-log lines (subsystem com.microgpt.carpenter) into
# Documents/diagnostics.log at the end of each sync (see DiagnosticsExport). This script retrieves
# that file from each connected iPhone/iPad over the development tunnel — no root, no prompt — and
# dumps the Mac app's live log too. Output lands in /tmp/dec-logs/.
#
# Usage:
#   scripts/pull-device-logs.sh            # all connected devices + this Mac
#   scripts/pull-device-logs.sh --mac-min 15   # widen the Mac log window (default 10 min)

set -euo pipefail

BUNDLE_ID="com.microgpt.carpenter"
APP_GROUP="group.com.microgpt.carpenter"
SUBSYSTEM="com.microgpt.carpenter"
OUT="/tmp/dec-logs"
MAC_MIN=10

while [ $# -gt 0 ]; do
  case "$1" in
    --mac-min) MAC_MIN="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT"

echo "== connected devices =="
DEVJSON="$OUT/devices.json"
xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true

# Emit "name<TAB>udid" for each connected iOS/iPadOS device.
DEVICES="$(python3 - "$DEVJSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for x in d.get("result", {}).get("devices", []):
    name = x.get("deviceProperties", {}).get("name")
    tunnel = x.get("connectionProperties", {}).get("tunnelState")
    plat = x.get("hardwareProperties", {}).get("platform", "")
    udid = x.get("hardwareProperties", {}).get("udid", "")
    if name and tunnel == "connected" and plat in ("iOS", "iPadOS"):
        print(f"{name}\t{udid}")
PY
)"

if [ -z "$DEVICES" ]; then
  echo "  (none — plug in / trust a device, or run it from Xcode once)"
else
  echo "$DEVICES" | sed 's/\t/  →  /'
fi

# Pull from each device. Copying the Documents directory is the form devicectl accepts; the file
# we want is diagnostics.log inside it.
while IFS=$'\t' read -r NAME UDID; do
  [ -z "${NAME:-}" ] && continue
  SAFE="$(echo "$NAME" | tr ' /' '__')"
  DEST="$OUT/$SAFE"
  rm -rf "$DEST"; mkdir -p "$DEST"
  echo
  echo "== $NAME ($UDID) =="
  if xcrun devicectl device copy from \
      --device "$UDID" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source Documents \
      --destination "$DEST" >/dev/null 2>"$DEST/.err"; then
    LOG="$DEST/Documents/diagnostics.log"
    [ -f "$LOG" ] || LOG="$(/usr/bin/find "$DEST" -name diagnostics.log -print -quit 2>/dev/null || true)"
    if [ -n "${LOG:-}" ] && [ -f "$LOG" ]; then
      cp "$LOG" "$OUT/$SAFE.log"
      echo "  saved $OUT/$SAFE.log ($(wc -l < "$OUT/$SAFE.log" | tr -d ' ') lines)"
    else
      echo "  connected, but no diagnostics.log yet — run the app and trigger a sync, then re-run."
    fi
  else
    echo "  could not read the app container:"
    sed 's/^/    /' "$DEST/.err" 2>/dev/null | tail -3
  fi

  # The notification service extension is a separate process, so the app's export cannot see it —
  # `OSLogStore(scope: .currentProcessIdentifier)` stops at the process boundary. It writes its own
  # file into the App Group container, which is a different devicectl domain. This is the log that
  # answers "did the bell arrive, and could the extension decrypt it".
  GDEST="$DEST-group"
  rm -rf "$GDEST"; mkdir -p "$GDEST"
  if xcrun devicectl device copy from \
      --device "$UDID" \
      --domain-type appGroupDataContainer \
      --domain-identifier "$APP_GROUP" \
      --source diagnostics-extension.log \
      --destination "$GDEST" >/dev/null 2>"$GDEST/.err"; then
    NSELOG="$(/usr/bin/find "$GDEST" -name diagnostics-extension.log -print -quit 2>/dev/null || true)"
    if [ -n "${NSELOG:-}" ] && [ -f "$NSELOG" ]; then
      cp "$NSELOG" "$OUT/$SAFE-nse.log"
      echo "  saved $OUT/$SAFE-nse.log ($(wc -l < "$OUT/$SAFE-nse.log" | tr -d ' ') lines)"
    else
      echo "  no extension log yet — the extension runs only when a bell push arrives."
    fi
  elif grep -q "cannot contain" "$GDEST/.err" 2>/dev/null; then
    # devicectl reports a missing file inside a group container this way. It is not a failure to
    # reach the container — it means the extension has not written its log yet, which is the normal
    # state until a bell push has actually been handled on this device.
    echo "  no extension log yet — the extension writes one only when it handles a bell push."
  else
    echo "  could not read the app group container:"
    sed 's/^/    /' "$GDEST/.err" 2>/dev/null | tail -3
  fi
done <<< "$DEVICES"

# This Mac's own logs need no root for our subsystem.
echo
echo "== this Mac (last ${MAC_MIN}m) =="
if /usr/bin/log show --last "${MAC_MIN}m" \
     --predicate "subsystem == \"$SUBSYSTEM\"" \
     --info --style compact > "$OUT/mac.log" 2>/dev/null; then
  echo "  saved $OUT/mac.log ($(wc -l < "$OUT/mac.log" | tr -d ' ') lines)"
else
  echo "  (no Mac log — the Mac app may not be running)"
fi

echo
echo "All output in $OUT/"
