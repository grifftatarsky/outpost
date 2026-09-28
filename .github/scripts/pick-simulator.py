#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator on this machine, or of the one named.

Reads `xcrun simctl list devices available --json` on stdin and writes one UDID on stdout, or
nothing at all if the machine has no such device. The caller decides what an empty answer means.

**Why a name is looked up here rather than handed to xcodebuild.** `-destination
'platform=iOS Simulator,name=outpost-alpha'` means the newest OS by default, so on Xcode 27 it found
nothing: the rig's simulators run iOS 26.5. A UDID names exactly one device, whatever it runs.

**Its own file rather than a `python3 -c` in the workflow.** It was a `-c`, and the second line of
the script carried the YAML block's indentation into Python, so every run of the App suite job died
with `IndentationError: unexpected indent` before it reached a test. A file is a file: it runs the
same here as it does on the runner, which is the only way that class of mistake gets caught before
it is pushed.

Runs on nothing but the standard library, because a runner has no dependencies installed yet.
"""

import json
import sys


def newest_iphone(devices: dict[str, list[dict]], named: str | None = None) -> str | None:
    # Runtime identifiers sort as strings in version order — `iOS-18-0` before `iOS-26-0` — so
    # reversed gives the newest first. A device the image lists but cannot boot is not available.
    for runtime in sorted(devices, reverse=True):
        if "iOS" not in runtime:
            continue
        for device in devices[runtime]:
            name = device.get("name", "")
            wanted = name == named if named else "iPhone" in name
            if device.get("isAvailable") and wanted:
                return device["udid"]
    return None


if __name__ == "__main__":
    udid = newest_iphone(json.load(sys.stdin)["devices"], sys.argv[1] if len(sys.argv) > 1 else None)
    if udid:
        print(udid)
