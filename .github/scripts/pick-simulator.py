#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator on this machine.

Reads `xcrun simctl list devices available --json` on stdin and writes one UDID on stdout, or
nothing at all if the machine has no iPhone. The caller decides what an empty answer means.

**Its own file rather than a `python3 -c` in the workflow.** It was a `-c`, and the second line of
the script carried the YAML block's indentation into Python, so every run of the App suite job died
with `IndentationError: unexpected indent` before it reached a test. A file is a file: it runs the
same here as it does on the runner, which is the only way that class of mistake gets caught before
it is pushed.

Runs on nothing but the standard library, because a runner has no dependencies installed yet.
"""

import json
import sys


def newest_iphone(devices: dict[str, list[dict]]) -> str | None:
    # Runtime identifiers sort as strings in version order — `iOS-18-0` before `iOS-26-0` — so
    # reversed gives the newest first. A device the image lists but cannot boot is not available.
    for runtime in sorted(devices, reverse=True):
        if "iOS" not in runtime:
            continue
        for device in devices[runtime]:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                return device["udid"]
    return None


if __name__ == "__main__":
    udid = newest_iphone(json.load(sys.stdin)["devices"])
    if udid:
        print(udid)
