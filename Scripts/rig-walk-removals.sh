#!/bin/bash
#
# The removal walk on the rig: Trig (gamma), Quad (delta) and Fifth (outpost-27), all under --mailbox,
# so what it shows is proved above the mailbox and nothing below it.
#
#   A race   Trig and Quad remove each other with neither sending, then Trig's reaches the mailbox
#            first. All three phones must show the same room: Trig and Fifth in, Quad out, and Quad
#            told so.
#   After    What Trig says after the race reaches Fifth and never reaches Quad.
#   A tie    Trig and Fifth both remove Quad with neither sending, each writing under a key of their
#            own. Each must read what the other wrote, and Quad neither.
#
# Every step is one RigChecks test on one device. Each run makes two new rooms, so it can be repeated.
# Logs and screen trees go to /tmp/outpost-rig-exchange; the first failing step stops the walk.
#
# Usage: Scripts/rig-walk-removals.sh

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

trig=0993066E-DA3B-4925-A7C3-F4189A3F7DD7
quad=92E0602F-FCEF-4EDF-BC71-389B3C052E89
fifth=EBDFF5AF-7699-4646-93B0-7218985EC2C0
derived=/tmp/carpenter-dd
exchange=/tmp/outpost-rig-exchange
codes=/tmp/outpost-rig-mailbox/codes
mkdir -p "$exchange"

for member in Trig Quad Fifth; do
    if [ ! -s "$codes/$member.identity" ]; then
        echo "$member has no code in $codes: onboard it under --mailbox first (docs/simulator-rig.md)"
        exit 1
    fi
done

echo "building once for every device"
if ! xcodebuild build-for-testing -workspace Carpenter.xcworkspace -scheme Carpenter \
    -destination "platform=iOS Simulator,id=$trig" -derivedDataPath "$derived" > "$exchange/walk-build.log" 2>&1; then
    echo "FAILED  the build ($exchange/walk-build.log)"
    exit 1
fi

step() {
    local name=$1 device=$2 test=$3
    shift 3
    if env TEST_RUNNER_OUTPOST_RIG=1 "$@" xcodebuild test-without-building -workspace Carpenter.xcworkspace \
        -scheme Carpenter -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
        -only-testing:"CarpenterUITests/RigChecks/$test" -parallel-testing-enabled NO > "$exchange/$name.log" 2>&1
    then
        echo "passed  $name"
    else
        echo "FAILED  $name ($exchange/$name.log)"
        exit 1
    fi
}

together() {
    local room=$1
    step "$room-1-trig-invites-quad" "$trig" testTrigMakesARoomAndInvitesQuad TEST_RUNNER_RIG_ROOM="$room" TEST_RUNNER_RIG_JOINER=Quad
    step "$room-2-quad-joins" "$quad" testQuadJoins
    step "$room-3-trig-invites-fifth" "$trig" testTrigMakesARoomAndInvitesQuad TEST_RUNNER_RIG_ROOM="$room" TEST_RUNNER_RIG_JOINER=Fifth
    step "$room-4-fifth-joins" "$fifth" testQuadJoins
    step "$room-5-trig-lets-them-in" "$trig" testRunsARound TEST_RUNNER_RIG_NAME=Trig
    step "$room-6-quad-catches-up" "$quad" testRunsARound TEST_RUNNER_RIG_NAME=Quad
    step "$room-7-fifth-catches-up" "$fifth" testRunsARound TEST_RUNNER_RIG_NAME=Fifth
    step "$room-8-quad-says" "$quad" testQuadSays TEST_RUNNER_RIG_ROOM="$room" TEST_RUNNER_RIG_SAY="hello in $room"
    step "$room-9-trig-sees" "$trig" testSees TEST_RUNNER_RIG_ROOM="$room" TEST_RUNNER_RIG_EXPECT="hello in $room"
    step "$room-10-fifth-sees" "$fifth" testSees TEST_RUNNER_RIG_ROOM="$room" TEST_RUNNER_RIG_EXPECT="hello in $room"
}

stamp="$(date +%H%M)"
race="Race$stamp"
tie="Tie$stamp"

together "$race"
step "$race-8-trig-removes-quad-offline" "$trig" testRemoves TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_REMOVE=Quad TEST_RUNNER_RIG_OFFLINE=1
step "$race-9-quad-removes-trig-offline" "$quad" testRemoves TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_REMOVE=Trig TEST_RUNNER_RIG_OFFLINE=1
step "$race-10-trig-sends" "$trig" testStaysOpen TEST_RUNNER_RIG_ROOM="$race"
step "$race-11-quad-sends" "$quad" testStaysOpen TEST_RUNNER_RIG_ROOM="$race"
for member in fifth trig quad; do
    device=$fifth
    [ "$member" = trig ] && device=$trig
    [ "$member" = quad ] && device=$quad
    step "$race-12-$member-records" "$device" testRecordsMembers TEST_RUNNER_RIG_ROOM="$race" \
        TEST_RUNNER_RIG_PEOPLE=Trig,Quad,Fifth TEST_RUNNER_RIG_RECORD="$race-$member"
done
expected="Trig=in,Quad=out,Fifth=in"
for member in fifth trig quad; do
    shown="$(cat "$exchange/$race-$member" 2>/dev/null)"
    if [ "$shown" != "$expected" ]; then
        echo "FAILED  $race: $member's phone shows $shown, expected $expected"
        exit 1
    fi
done
echo "passed  $race: every phone shows $expected"
step "$race-13-quad-is-told" "$quad" testSees TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_EXPECT="You were removed from this room"
step "$race-14-trig-says-after" "$trig" testQuadSays TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_SAY="after the race"
step "$race-15-fifth-sees-it" "$fifth" testSees TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_EXPECT="after the race"
step "$race-16-quad-never-sees-it" "$quad" testNeverSees TEST_RUNNER_RIG_ROOM="$race" TEST_RUNNER_RIG_EXPECT="after the race"

together "$tie"
step "$tie-8-trig-removes-quad-offline" "$trig" testRemoves TEST_RUNNER_RIG_ROOM="$tie" TEST_RUNNER_RIG_REMOVE=Quad \
    TEST_RUNNER_RIG_OFFLINE=1 TEST_RUNNER_RIG_SAY="under Trig's key"
step "$tie-9-fifth-removes-quad-offline" "$fifth" testRemoves TEST_RUNNER_RIG_ROOM="$tie" TEST_RUNNER_RIG_REMOVE=Quad \
    TEST_RUNNER_RIG_OFFLINE=1 TEST_RUNNER_RIG_SAY="under Fifth's key"
step "$tie-10-trig-sends" "$trig" testStaysOpen TEST_RUNNER_RIG_ROOM="$tie"
step "$tie-11-fifth-reads-trig" "$fifth" testSees TEST_RUNNER_RIG_ROOM="$tie" TEST_RUNNER_RIG_EXPECT="under Trig's key"
step "$tie-12-trig-reads-fifth" "$trig" testSees TEST_RUNNER_RIG_ROOM="$tie" TEST_RUNNER_RIG_EXPECT="under Fifth's key"
step "$tie-13-quad-reads-neither" "$quad" testNeverSees TEST_RUNNER_RIG_ROOM="$tie" TEST_RUNNER_RIG_EXPECT="under Trig's key"

echo "the removal walk passed: proved above the mailbox, on three simulators"
