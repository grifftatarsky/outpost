#!/bin/bash
# Runs the package suite as several processes side by side.
#
# Every suite that builds a session runs on the main actor, so one `swift test` process uses one
# core for nearly all of it however many suites run at once. This builds once, deals the suites out
# to SHARDS processes, and reports the same totals. `swift test` is still the reference: CI runs it,
# and a failure here is rerun there before it is believed.
#
#   Scripts/test-package.sh            six processes
#   SHARDS=4 Scripts/test-package.sh   four
set -uo pipefail
cd "$(dirname "$0")/../Packages/Carpenter" || exit 1

shards=${SHARDS:-6}
swift build --build-tests 2>&1 | tail -1 || exit 1

bundle="$(swift build --show-bin-path)/CarpenterKitTests.xctest/Contents/MacOS/CarpenterKitTests"
helper="$(dirname "$(dirname "$(xcrun --find swift-test)")")/libexec/swift/pm/swiftpm-testing-helper"
platform="$(xcrun --show-sdk-platform-path)"
export DYLD_FRAMEWORK_PATH="$platform/Developer/Library/Frameworks"
export DYLD_LIBRARY_PATH="$platform/Developer/usr/lib"

logs="$(mktemp -d)"
run() { "$helper" --test-bundle-path "$bundle" "$bundle" --testing-library swift-testing "$@"; }

run --list-tests | cut -d/ -f1 | sort -u > "$logs/suites"
if [ ! -s "$logs/suites" ]; then
  echo "no suites were listed; run 'swift test' to see why"
  exit 1
fi

started=$(date +%s)
pids=()
for n in $(seq 0 $((shards - 1))); do
  pattern=$(awk -v n="$n" -v of="$shards" 'NR % of == n' "$logs/suites" | sed 's/\./\\./g' | paste -sd'|' -)
  [ -z "$pattern" ] && continue
  run --filter "^($pattern)/" > "$logs/shard-$n.log" 2>&1 &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done

tests=0; suites=0; known=0
for log in "$logs"/shard-*.log; do
  line=$(grep -E "Test run with [0-9]+ tests? in [0-9]+ suites?" "$log" | tail -1)
  if [ -z "$line" ]; then
    echo "a process ended without a result: $log"
    failed=1
    continue
  fi
  tests=$((tests + $(echo "$line" | sed -E 's/.*with ([0-9]+) tests?.*/\1/')))
  suites=$((suites + $(echo "$line" | sed -E 's/.* in ([0-9]+) suites?.*/\1/')))
  if echo "$line" | grep -q "known issue"; then
    known=$((known + $(echo "$line" | sed -E 's/.* with ([0-9]+) known issues?.*/\1/')))
  fi
done

grep -hE "^✘" "$logs"/shard-*.log | cut -c1-400
elapsed=$(( $(date +%s) - started ))
if [ "$failed" -ne 0 ]; then
  echo "FAILED: $tests tests in $suites suites, $elapsed seconds, logs in $logs"
  exit 1
fi
echo "passed: $tests tests in $suites suites, $elapsed seconds, $known known issues, logs in $logs"
