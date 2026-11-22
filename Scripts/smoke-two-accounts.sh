#!/bin/bash
#
# The three end-to-end runs against real iCloud, on the two rig simulators, from one clean build.
#
#   1. The app suite with the live CloudKit tests on, on the first simulator: one account.
#   2. LivePairTests, a side on each simulator: a space shared each way, entries in order, receipts,
#      a photo, a closed space. Then LivePairContractTests: the rules the in-memory mailbox is held
#      to under swift test, checked against iCloud by the same code.
#   3. LivePairSendTests, a side on each: an invitation by code, a Solo, a key replaced while the
#      other side ran no rounds, a send that collects first, a removal collected.
#
# IT ERASES. The live tests delete every pair space in both Apple Accounts, clear the first
# account's deathmark, and write records from made-up devices into its device zone. A member made on
# either simulator beforehand loses its spaces. So it does nothing unless told the accounts hold
# nothing anybody wants:
#
#   ERASE_SPACES=yes Scripts/smoke-two-accounts.sh [first-udid second-udid]
#
# It builds into fresh derived data every time. A run on a build left over from an earlier commit
# passes or fails for that commit, and nothing on screen says so: on 2026-11-11 the build failed, the
# tests ran anyway on the build from that afternoon, and both sides passed.

set -uo pipefail

if [ "${ERASE_SPACES:-}" != "yes" ]; then
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

first="${1:-5A43F953-128D-4FE6-9135-0D26520E02B6}"
second="${2:-DF6EB0C7-9FCF-45C8-A120-6349FBFA288F}"
logs="${SMOKE_LOGS:-$(mktemp -d)}"
derived="$logs/derived"
mkdir -p "$logs"
rm -rf "$derived"

echo "building once into $derived"
xcodebuild build-for-testing -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination "platform=iOS Simulator,id=$first" -derivedDataPath "$derived" > "$logs/build.log" 2>&1
if ! grep -q "\*\* TEST BUILD SUCCEEDED \*\*" "$logs/build.log"; then
  echo "the build failed, so nothing was run; see $logs/build.log"
  grep -E "error:" "$logs/build.log" | sort -u | head -10
  exit 1
fi

run() {
  xcodebuild test-without-building -workspace Carpenter.xcworkspace -scheme Carpenter \
    -derivedDataPath "$derived" -parallel-testing-enabled NO "$@"
}

outcome() {
  if grep -q "\*\* TEST EXECUTE SUCCEEDED \*\*" "$1"; then echo passed; else echo FAILED; fi
}

failed=0
report() {
  local result
  result=$(outcome "$2")
  echo "$1: $result ($2)"
  if [ "$result" != passed ]; then
    failed=1
    grep -E "✘|error:|Issue recorded" "$2" | cut -c1-240 | head -8
  fi
}

export TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1

echo "one account: the app suite with the live tests on"
run -destination "platform=iOS Simulator,id=$first" -only-testing:CarpenterTests > "$logs/one-account.log" 2>&1
report "one account" "$logs/one-account.log"

pair() {
  local suite=$1 a=$2 b=$3 stamp
  stamp="$suite-$(date +%H%M%S)"
  echo "two accounts: $suite"
  TEST_RUNNER_CARPENTER_LIVE_PAIR_ROLE=$a TEST_RUNNER_CARPENTER_LIVE_PAIR_RUN=$stamp \
    run -destination "platform=iOS Simulator,id=$first" -only-testing:"CarpenterTests/$suite" \
    > "$logs/$suite-$a.log" 2>&1 &
  TEST_RUNNER_CARPENTER_LIVE_PAIR_ROLE=$b TEST_RUNNER_CARPENTER_LIVE_PAIR_RUN=$stamp \
    run -destination "platform=iOS Simulator,id=$second" -only-testing:"CarpenterTests/$suite" \
    > "$logs/$suite-$b.log" 2>&1 &
  wait
  report "$suite, $a" "$logs/$suite-$a.log"
  report "$suite, $b" "$logs/$suite-$b.log"
}

pair LivePairTests alice bob
pair LivePairContractTests alice bob
pair LivePairSendTests ann ben

echo "commit $(git rev-parse --short HEAD)$(git diff --quiet || echo ' with uncommitted changes'), logs in $logs"
exit "$failed"
