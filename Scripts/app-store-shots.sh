#!/bin/zsh
#
# App Store screenshots from the Debug build's --site-shot fixtures.
#
#   Scripts/app-store-shots.sh <iphone-udid> <ipad-udid> <out-dir>
#
# The iPhone should be an iPhone 17 Pro Max (6.9-inch, 1320 x 2868) and the iPad an iPad Pro
# 13-inch (2752 x 2064 in landscape). docs/app-store.md says which screens and why.
#
# Two things the export fixes, both measured 2026-09-19: an iPad captured in landscape comes out as
# portrait pixels with the picture turned, and every capture carries an eXIf chunk whose orientation
# still says "turn" after the pixels are turned, so a viewer that honours it turns them again.

set -euo pipefail
IPHONE=$1 IPAD=$2 OUT=$3
root="$(cd "$(dirname "$0")/.." && pwd)"
DD=/tmp/carpenter-dd
cd "$root"

for D in $IPHONE $IPAD; do
  xcrun simctl boot "$D" 2>/dev/null || true
  xcrun simctl status_bar "$D" override --time 9:41 --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
done

xcodebuild build-for-testing -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination "platform=iOS Simulator,id=$IPHONE" -derivedDataPath $DD -quiet

mkdir -p "$OUT"
for pair in "iphone:$IPHONE" "ipad:$IPAD"; do
  name=${pair%%:*} udid=${pair#*:}
  result=/tmp/app-store-shots-$name.xcresult attachments=/tmp/app-store-shots-$name
  rm -rf "$result" "$attachments" "$OUT/$name"
  xcrun simctl terminate "$udid" com.microgpt.carpenter 2>/dev/null || true
  TEST_RUNNER_OUTPOST_SHOTS=1 xcodebuild test-without-building -workspace Carpenter.xcworkspace \
    -scheme Carpenter -destination "platform=iOS Simulator,id=$udid" -derivedDataPath $DD \
    -parallel-testing-enabled NO -only-testing:CarpenterUITests/AppStoreShots/testShots \
    -resultBundlePath "$result" -quiet
  mkdir -p "$attachments" "$OUT/$name"
  xcrun xcresulttool export attachments --path "$result" --output-path "$attachments" >/dev/null
  python3 - "$name" "$attachments" "$OUT/$name" <<'PY'
import json, shutil, struct, subprocess, sys
name, attachments, out = sys.argv[1:]
keep = {b'IHDR', b'PLTE', b'IDAT', b'IEND', b'sRGB', b'gAMA', b'cHRM', b'iCCP', b'tRNS'}
for test in json.load(open(f'{attachments}/manifest.json')):
    for a in test.get('attachments', []):
        title = a['suggestedHumanReadableName'].split('_0_')[0]
        png = f'{out}/{title}.png'
        shutil.copy(f"{attachments}/{a['exportedFileName']}", png)
        if name == 'ipad':
            subprocess.run(['sips', '-r', '270', png], capture_output=True, check=True)
        data = open(png, 'rb').read()
        clean, i = bytearray(data[:8]), 8
        while i < len(data):
            length = struct.unpack('>I', data[i:i + 4])[0]
            if data[i + 4:i + 8] in keep:
                clean += data[i:i + 12 + length]
            i += 12 + length
        open(png, 'wb').write(clean)
        size = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', png],
                              capture_output=True, text=True).stdout.split()
        print(f'{name}: {title} {size[-3]} x {size[-1]}')
PY
done
