<!-- COPY BEGIN 0ffcffb9 [NEEDS HUMAN REVIEW] -->

# Work order: plan steps 3 and 4 on the rig

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

For `docs/pre-testflight.md`, "Left to do, in order", items 3 and 4 (the simulator half of 4):
the app's own screens on two Apple Accounts, the older live suite, and the rest of the lock walk.

Written 2026-11-10 between 22:50 and 23:20 from the tree at `fe9ec3e` (branch `overnight-2026-10-31`).
Nothing was built or run to write it. Every line number is from that tree. Where a fact comes from a
log in this session's scratch folder, the log is named; "S/" below means
`/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/`.
Those logs are overwritten by later runs, so copy them before running anything.

Not in this order: the iPhone half of item 4, and building decision 2 (Face ID or the phone's
passcode before the code). Commit only if whoever runs this was told to.

Devices: `A` = outpost-alpha `5A43F953-128D-4FE6-9135-0D26520E02B6`, `B` = outpost-beta
`DF6EB0C7-9FCF-45C8-A120-6349FBFA288F`. Bundle `com.microgpt.carpenter`, product `Outpost.app`
(`docs/simulator-rig.md:70-71`).

---

## 1. What I found that changes the plan

Read these first. Three of them contradict what the docs say today.

**F1. The lock walk of 2026-11-10 stopped at setup and reported a pass.**
`docs/open-questions.md:167-173`, `docs/simulator-rig.md:446-449` and `docs/pre-testflight.md:45-49`
say the walk covered a wrong code, the right code, a clean restart behind the lock, the name still
there, and *Forgot the code?* erasing the phone. The only log of that run, `S/lockwalk.log`
(17:14:08 to 17:16:03), shows otherwise:

- The last action is the second tap on "Finish" inside `settle` (`S/lockwalk.log` lines 679-717). A
  system alert (`kTCCServiceFocusStatus-alert`) interrupted it, the button was gone on the retry, and
  the failure was accepted by `XCTExpectFailure` at `App/CarpenterUITests/RigChecks.swift:66-69`
  (`S/lockwalk.log:719,728`).
- The next line is `Tear Down` 0.11 seconds later, then `passed (106.548 seconds)`
  (`S/lockwalk.log:737-738`).
- The log has no home press, no `lock-6-locked` and nothing after it: `grep -c -E "lock-(6|7|8|9|10|11)"`
  on the log prints 0. `/tmp/outpost-rig-exchange` holds `lock-1-recovery-key.txt` to
  `lock-5b-private-notifications.txt` (17:14 to 17:15) and no later step.
- outpost-alpha still holds that member: its App Group file
  `…/Shared/AppGroup/<id>/com.microgpt.carpenter/state.json` begins `{"sealed":"` and was last
  written 17:15:56 on 2026-11-10 (read from disk at 23:04, no `simctl`). Had the walk reached the
  erase, the file would be gone.

So what was walked that day is `RigChecks.swift:153-214` only: the recovery key at setup,
notifications before the lock, the lock offer, the code typed twice, the private-notifications alert,
and the privacy check-up. Lines 216-273 (locked on return, wrong code, right code, clean restart,
name, forgot and erase) did not run on 2026-11-10, so they have never run against a lock that seals.
`docs/epics/identity-and-devices.md:459-471` cites the same check for the lock as it was before it
sealed anything; whether those runs reached the end is not recorded and cannot be checked now.

Why a failed tap inside `XCTExpectFailure` ends the test method is **not verified**. Apple's page says `continueAfterFailure` defaults to true
(https://developer.apple.com/tutorials/data/documentation/xctest/xctestcase/continueafterfailure.json),
and `RigChecks` never sets it, so the method should have gone on. It did not.

Consequence: **any `RigChecks` step can pass without finishing**, whenever a tap made through
`tapped()` or a check made through `stillThere()` (`RigChecks.swift:64-79`) fails. Every rig result
that rests on "the step passed" is suspect until change C1 below is in.

**F2. outpost-alpha is not empty.** It holds the member "Lockwood", made under
`--mailbox /tmp/outpost-lock-check` (`RigChecks.swift:154,162`), with the lock on and the code
`482913` (`RigChecks.swift:199`). Every app-suite run on alpha since 17:16 was hosted in an app
sitting behind that lock (the tests are hosted in the app:
`App/Carpenter.xcodeproj/project.pbxproj:745,773`). outpost-beta holds no member (its App Group
folder `com.microgpt.carpenter` is empty, read 23:04). Check again before starting; another process
was using both devices while this was written.

**F3. No UI test drives the real app over iCloud.** `RigChecks.launch` always adds
`--mailbox /tmp/outpost-rig-mailbox` (`RigChecks.swift:23`) and the lock check adds
`--mailbox /tmp/outpost-lock-check` (`:154`). The other UI test classes launch a demo or an idle app
(`ScreenCatalogueTests.swift:47,64` `--site-shot`; `UXFindingsTests.swift:13` `--copy-shot`;
`VoiceOverWalkTests.swift:11,190` and `AccentContrastAuditTests.swift:9` `--quiet-for-audit`).
Leaving `--mailbox` off is enough to reach CloudKit (`App/Carpenter/AppRootView.swift:65-77`), but
then nothing hands a code from one device to the other: `RigCodes.leave` writes only when `--mailbox`
is given (`App/Carpenter/FileMailbox.swift:127-142`), and a Solo started from the list of people
never leaves its invitation at all (`AppRootView.swift:562-590` has no `RigCodes` call). Change C3.

**F4. The older live suite ran on these two simulators tonight, in another process.** Not in the docs
yet. From the logs in S/:

| Run | When | Result | Log |
|---|---|---|---|
| `CarpenterTests`, whole target, alpha only | 22:36-22:37 | 63 tests in 13 suites: 39 passed, 24 skipped, 98.4 s | `S/live-single-alpha2.log` |
| `LivePairTests`, alice on alpha, bob on beta | three attempts 22:38-23:06 | stalled or failed (the last: "bob waited 3.0 minutes for Alice's closed space to be gone") | run folders `old-223849`, `LivePairTests-225041`, `LivePairTests-225913` under `/tmp/outpost-rig-exchange/live-pair/` |
| `LivePairTests`, fourth attempt, after `fe9ec3e` | 23:07-23:08 | alice passed in 65.1 s, bob in 64.9 s | `S/live-alice.log`, `S/live-bob.log` |
| `LivePairSendTests`, ann on alpha, ben on beta | 23:08-23:09 | ann passed in 71.7 s, ben in 70.6 s | `S/live-ann.log`, `S/live-ben.log` |

Commit `fe9ec3e` (23:10) made each side clear its own spaces first and sync while it waits. Still not
done: the single-device suite on **beta**, and the half of one test that needs beta's user record
(F5).

**F5. One live test silently skips its second half.**
`CloudKitMailboxTests.aSpaceIsSharedWithOnePerson` returns early unless
`/tmp/outpost-rig-exchange/pairs/beta-user.json` exists (`App/CarpenterTests/CloudKitMailboxTests.swift:84-86`).
That folder does not exist now. So "and then with them alone", read-only, did not run tonight.

**F6. Two live suites the docs cite no longer exist.** `LiveRoundTests` and `LiveOutpostTests` were
deleted in `bd994f0` ("Each pair of people gets a space of its own…"). `docs/testing.md:386-405`,
`docs/roadmap.md:97,99,102,104,241-244,271` and three epics still cite them as proof over real
CloudKit. What they proved was proved against the old shared outbox zone. On today's pair spaces
nothing live covers: a hole repaired over the wire, a read report moving a mark, an edit, a
withdrawal, a deleted room staying deleted, or anything about an Outpost (post, photo, comment,
unseen). Section 9, item 6.

**F7. The lock walk puts a recovery key on the Mac's clipboard.** `copyFromTheShareSheet`
(`RigChecks.swift:52-62`) taps Copy in the share sheet, and `settle` does the same on every
onboarding (`:91-93,109-116`). `docs/simulator-rig.md:116-118` forbids the simulator pasteboard
because it overwrites what Griff last copied. Section 9, item 5.

**F8. `onboard()` passes when nothing was onboarded.** `RigChecks.swift:133` is
`if field.waitForExistence(timeout: 5) { … }` with no `else`. Over real iCloud the first screen waits
on the account check, and an account that remembers a dead device never offers the field
(`docs/simulator-rig.md:209-232`). Fixed in C4.

**F9. Read in the code, not measured:**
- Under `--mailbox` on a signed-in simulator the app still starts device sync against the real
  account: `startDeviceSync` checks only `UITestMode.isOn` and `testSession`
  (`App/Carpenter/AppRootView+Sync.swift:20-37`). `docs/simulator-rig.md:50-51` says the same.
- The round under `--mailbox` passes `media: cloud`, not the rig mailbox
  (`AppRootView+Sync.swift:60`; the rig-aware `media` is at `AppRootView.swift:99-105`), so collecting,
  settling and sweeping photos in a round goes to CloudKit.
- Erasing one device (`eraseThisDevice`, `App/Carpenter/AppRootView+Device.swift:229-243`, which is what
  *Forgot the code?* and `--reset-device` call) never withdraws that device's feed.
  `forgetOwnContribution` (`Packages/Carpenter/Sources/CarpenterCloudKit/CloudKitEntrySync.swift:256-277`)
  has no caller in the app. One record left in `SiblingFeeds` makes `occupancy()` answer `occupied`
  (`CloudKitEntrySync.swift:194-199`), so the next first launch on that account never offers setup.
- *Erase everything after N wrong codes* ends in `wipe` (`App/Carpenter/AppRootView+Lock.swift:86-91`,
  `AppRootView+Device.swift:180-187`), which deletes the `SiblingFeeds` zone of the real account even
  under `--mailbox` (`AppRootView+Device.swift:151-168,206-216`). Do not walk that
  setting on a simulator whose account holds a member anybody wants.

**F10. Stale in the docs.** `docs/simulator-rig.md:24-26,35-36` says neither simulator is signed in;
both ran CloudKit tonight. `:235-239,247-248` says to wait for a log line and terminate after
`--reset-account`; the app now exits by itself (`AppRootView.swift:370-378`).
`Scripts/rig-walk-removals.sh:23-25` names three devices that no longer exist; only alpha and beta
are on this Mac (read from `~/Library/Developer/CoreSimulator/Devices/*/device.plist`).

---

## 2. Every live suite

All in `App/CarpenterTests`, hosted in the app. "Flag" is `CARPENTER_CLOUDKIT_TESTS=1`
(`CloudKitMailboxTests.swift:9-13`).

| Suite | Enabled by | Tests | What it proves | Accounts |
|---|---|---|---|---|
| `CloudKitMailboxTests` (`CloudKitMailboxTests.swift:49-158`) | flag | 5 | A space is shared with nobody until a person is named, then with them alone and read-only (second half needs F5's file). A packet comes back byte for byte and can be withdrawn. A packet at the app's budget is accepted and one over the ceiling refused. A photo three times the ceiling goes as one copy per person and is deleted. Erasing leaves no `Pair-` zone. | one |
| `CloudKitSubscriptionTests` (`CloudKitSubscriptionTests.swift:7-144`) | flag | 5 | The packet and ring subscriptions exist on the shared database, the first silent, the second visible, each naming one record type, never duplicated, and anything else there is swept. | one |
| `LiveDeathmarkTests` (`LiveDeathmarkTests.swift:7-59`) | flag | 2 | A deathmark is stored with iCloud's time, gathers check-offs and is gone when cleared; posting again starts a new one. | one |
| `LiveSiblingFeedTests` (`LiveSiblingFeedTests.swift:7-369`) | flag | 6 | The feed on the server is ciphertext without the room key. A second device receives it and it is then deleted. A new device's request and its approval cross, deleted from inside the handler. A reinstall writes over its old record. iCloud keeps the first-stored time through a rewrite. An approval is stored once. | one |
| `LivePairTests` (`LivePairTests.swift:70-188`) | flag, role `alice` or `bob`, a run name | 1 per role | Invite by code and join; each joins the other's space; 24 entries arrive in order; receipts empty Alice's space; a photo's copy is collected and cleared; Bob cannot write into Alice's space; her space holds a ring; a closed space stops being readable. | two, two processes |
| `LivePairSendTests` (`LivePairSendTests.swift:9-130`) | flag, role `ann` or `ben`, a run name | 1 per role | A Solo started from the people Ann knows; both ends read the same phrase; after Ann replaces the room key while Ben is quiet, Ben's next send collects first and seals under the new key; after Ann removes Ben, his send is refused and nothing is written. | two, two processes |
| `LivePairMailboxMeasurements` (`LivePairMailboxMeasurements.swift:144-525`) | `CARPENTER_PAIR_STEP=<step>` alone; **not** behind the flag | 17 steps | Measurements, not proofs: 300 zones and links, what a reader may write, what a subscription fires on. | two, by hand |

Not live, same target: `BrandingTests` 2, `KeyboardExtensionPointTests` 1, `KeychainTests` 14,
`ScannedFieldsTests` 3, `TheVaultOnTheRealKeychainTests` 1 (the lock's vault against the real
keychain with a stand-in for the Secure Enclave, `TheVaultOnTheRealKeychainTests.swift:46-48`),
`FileProtectionTests` 3 (skipped on a simulator).

### Commands

Build once, from the tree both devices will run (`docs/testing.md:443-447`):

```bash
cd /Users/grifftatarsky/projects/outpost
A=5A43F953-128D-4FE6-9135-0D26520E02B6
B=DF6EB0C7-9FCF-45C8-A120-6349FBFA288F
DD=/tmp/carpenter-dd
OUT=/tmp/outpost-rig-exchange/runs-$(date +%m%d-%H%M); mkdir -p "$OUT"
xcodebuild build-for-testing -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination "platform=iOS Simulator,id=$A" -derivedDataPath "$DD" > "$OUT/build.log" 2>&1
grep -E '\*\* TEST BUILD' "$OUT/build.log"        # must print ** TEST BUILD SUCCEEDED **
x() { xcodebuild test-without-building -workspace Carpenter.xcworkspace -scheme Carpenter \
        -derivedDataPath "$DD" -parallel-testing-enabled NO "$@"; }
```

A build made for alpha's destination ran on beta tonight (`S/live-pair.sh`), so one build serves both.

Single device, one account (use `$B` and another log name for beta):

```bash
TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 x -destination "platform=iOS Simulator,id=$A" \
  -only-testing:CarpenterTests > "$OUT/single-alpha.log" 2>&1
grep -E '✘|Test run with|\*\* TEST' "$OUT/single-alpha.log"
```

Two accounts, two processes, started together. Either may start first: each side waits up to six
minutes for the other's file (`LivePairTests.swift:25-32`). The run name must be new each time, or a
side reads the last run's files at once; without it the folder is `…/live-pair/none`
(`LivePairTests.swift:11,17`).

```bash
pair() {  # pair <Suite> <role on alpha> <role on beta>
  local RUN="$1-$(date +%H%M%S)"
  TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 TEST_RUNNER_CARPENTER_LIVE_PAIR_ROLE=$2 \
    TEST_RUNNER_CARPENTER_LIVE_PAIR_RUN=$RUN x -destination "platform=iOS Simulator,id=$A" \
    -only-testing:CarpenterTests/$1 > "$OUT/$1-$2.log" 2>&1 &
  TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 TEST_RUNNER_CARPENTER_LIVE_PAIR_ROLE=$3 \
    TEST_RUNNER_CARPENTER_LIVE_PAIR_RUN=$RUN x -destination "platform=iOS Simulator,id=$B" \
    -only-testing:CarpenterTests/$1 > "$OUT/$1-$3.log" 2>&1 &
  wait
  grep -E '✘|↳|✔ Test [a-z]+\(\)|\*\* TEST' "$OUT/$1-$2.log" "$OUT/$1-$3.log"
}
pair LivePairTests alice bob
pair LivePairSendTests ann ben
```

Rules that have bitten before (`docs/testing.md:370-375`): the `TEST_RUNNER_` prefix and its place
before `xcodebuild` are required, `-parallel-testing-enabled NO` is required, and a suite that
"passes" in a hundredth of a second was skipped. With a role set, name the suite in `-only-testing`;
never run the whole target with a role.

### How long each took when last recorded

| Run | Time | Source |
|---|---|---|
| Whole target, one device, 2026-11-04 on "iPhone 17" | 38 tests, 79 s | `docs/simulator-rig.md:368` |
| Whole target, alpha, 2026-11-10 22:36 | 63 tests (39 ran), 98.4 s | `S/live-single-alpha2.log` |
| of which `CloudKitMailboxTests` | 40.2 s | same |
| of which `LiveSiblingFeedTests` | 36.0 s | same |
| of which `LiveDeathmarkTests` | 11.0 s | same |
| of which `CloudKitSubscriptionTests` | 10.6 s | same |
| `LivePairTests`, 2026-11-10 23:07 | 65.1 s and 64.9 s | `S/live-alice.log`, `S/live-bob.log` |
| `LivePairSendTests`, 2026-11-10 17:24 | 85 and 84 s in the docs; 85.0 and 83.5 in the log as read at 23:02, since overwritten | `docs/simulator-rig.md:439-440` |
| `LivePairSendTests`, 2026-11-10 23:08 | 71.7 s and 70.6 s | `S/live-ann.log`, `S/live-ben.log` |
| `LivePairMailboxMeasurements` | no record found; `beta-notify-send` sleeps 8 minutes by its own code (`LivePairMailboxMeasurements.swift:431`) | |
| One `RigChecks` step | 106.5 s of test in 124.7 s of `xcodebuild`, for the truncated lock setup | `S/lockwalk.log:738,745` |

### What each run leaves in an Apple Account, and how it is cleaned

| Run | Leaves | Cleaned by |
|---|---|---|
| `CloudKitMailboxTests` | Starts every test by deleting **every** `Pair-` zone in the account (`CloudKitMailboxTests.swift:62-64`; `CloudKitMailbox+Pairs.swift:150-158`). Leaves the last test's zone unless `erasingLeavesNothing` ran last (order is not promised). | Running the suite again. It takes a real member's spaces with it. |
| `CloudKitSubscriptionTests` | The app's own two subscriptions on the shared database; its stray is removed (`:141-142`). | Nothing to clean. |
| `LiveDeathmarkTests` | Nothing when it passes (`:35,57`). A failure part-way leaves a deathmark for a made-up identity. | Running it again; the first test clears first (`:16`). |
| `LiveSiblingFeedTests` | Nothing when every test passes: each ends with `forgetOwnContribution` (`:114,186-187,253-254,288,321,349`). A test that fails before that line leaves a record in `SiblingFeeds`, and the account then reads as occupied (F9). | Only `--reset-account`, which is Griff's to allow (`docs/simulator-rig.md:38-41,241-245`). |
| `LivePairTests`, `LivePairSendTests` | Each side deletes every `Pair-` zone of its account first and last (`LivePairTests.swift:79,121,127,186`; `LivePairSendTests.swift:31,75,81,128`). A side that fails keeps its zones until the next run's first line. On the Mac: `/tmp/outpost-rig-exchange/live-pair/<run>/`. In the app's container: `tmp/carpenter-live-pair-<id>/` (about 10 to 35 KB each, seen on both devices). | The next pair run, or `CloudKitMailboxTests`. |
| `LivePairMailboxMeasurements` | `alpha-make` leaves 300 `PairMeasure-` zones; `beta-notify-make` leaves a zone and a record in the **public** database (`:400-402`). `beta-id` writes nothing to iCloud, only `/tmp/outpost-rig-exchange/pairs/beta-user.json`. | `alpha-clean`, `beta-clean`, `beta-notify-clean` (`:437-524`). Run only `beta-id`. |
| A `RigChecks` step under `--mailbox` | Files under the mailbox folder. On a signed-in simulator, also a device feed in the real account (F9, not measured). | The folder: `rm -rf`. The feed: `--reset-account`. |
| The app over real iCloud (section 6) | A member: its feed in `SiblingFeeds`, its `Pair-` zones, shares accepted from the other account, two subscriptions. | `--reset-account` on each device (`AppRootView.swift:370-378` → `wipe`, `AppRootView+Device.swift:151-168`). Griff's to allow. |

Any live suite deletes a member's spaces on that account. Run the live suites **before** a member is
made over iCloud, never between.

---

## 3. The lock: what a rig check covers and what is missing

One check exists, `testANewMemberSavesTheKeyAndLocksTheApp` (`RigChecks.swift:152-274`).

| Part of the lock | In a check? | Ever run? |
|---|---|---|
| Lock offered at setup, after the recovery key and notifications; code typed twice; private notifications offered | yes, `:153-214` | once, 2026-11-10 |
| Locked when the app comes back; a wrong code says so; the right code opens | yes, `:216-233` | **no** (F1) |
| A clean restart behind the lock; no setup offered; the member is still there | yes, `:235-248` | **no** |
| *Forgot the code?* asks, then erases this phone | yes, `:250-273` | **no** |
| Changing the code (`AppLockViews.swift:524-526,571-597`; `AppLockController.swift:229-233,319`) | no | no |
| Opening with the recovery key, which turns the lock off (`AppLockViews.swift:126-141,200-262`; `AppLockController.swift:332-354`) | no | no |
| Turning the lock off (`AppLockViews.swift:527-532`; `AppLockController.swift:236-239,308-313`) | no | no |
| Turning it on from You (`AppLockViews.swift:534-536,558-566`) | no | no |
| Face ID: the switch, opening with it, and the note after Face ID changes (`AppLockViews.swift:510-523,117-121`; `AppLockController.swift:95-103,203-220`) | no | no |
| A passphrase in place of digits (`AppLockViews.swift:53-89,319-324`) | no | no |
| *Lock: after 1, 5, 15 minutes* (`AppLockViews.swift:493-509`) | no | no |
| The waits after five wrong codes, and *Erase everything after N* (`AppLock.swift:149-158`; `AppLockViews.swift:656-677`) | no | no |

Two lines of the existing check cannot work as written: `RigChecks.swift:254-257` taps a secure field
on the lock screen, and a lock with digits draws a keypad and no field
(`AppLockViews.swift:46-52`; `DigitPad.swift:18-46`).

Face ID on a simulator: no toggle appears unless Face ID is enrolled (`AppLockController.swift:16-25`,
`AppLockViews.swift:343-347`), and the tree saved at `lock-5-code-typed` shows none. Enrolling and
matching from a script is reported to work through `notifyutil` and
`com.apple.BiometricKit_Sim.pearl.match`, but the one Apple forum post that shows it from a UI test
says it did not work (https://developer.apple.com/forums/thread/767414), and the other route is a
third-party tool (https://github.com/wix/AppleSimulatorUtils). Not verified on iOS 27.2. It also needs
`LAContext().domainState.biometry.stateHash` to be non-nil on a simulator
(`AppLock.swift:137-139`), not verified. **Recommendation: do not build a simulator check for Face
ID. It runs on the iPhone with decision 2**, which the plan already says (`docs/pre-testflight.md:115-117`).

---

## 4. Order of work

1. Step 0: look at the devices (section 5).
2. C1: make a check unable to pass without finishing. Everything after depends on it.
3. C2 and the lock walk on alpha (section 5, runs L1 to L7). Needs nothing from Griff.
4. The rest of the live suite (runs S1 to S4). Needs nothing from Griff unless an account asks for
   its password.
5. C3, C4 and the two-account walk in the app's own screens (section 6). Needs three answers from
   Griff (section 9, items 1 to 3).
6. Docs (section 8).

Do not start while another `xcodebuild` is running against these devices:
`ps -axo pid,etime,command | grep "xcodebuild test" | grep -v grep` must print nothing.

---

## 5. Step 0, the harness, the lock walk, the live suite

### Step 0. Look before touching

```bash
xcrun simctl list devices | grep outpost            # both Booted
kept() {   # what the app keeps on a device: nothing, sealed or clear
  local g; g="$(xcrun simctl get_app_container "$1" com.microgpt.carpenter group.com.microgpt.carpenter 2>/dev/null)" || { echo "no app"; return; }
  local f="$g/com.microgpt.carpenter/state.json"
  if [ ! -e "$f" ]; then echo nothing
  elif [ "$(head -c 9 "$f")" = '{"sealed"' ]; then echo sealed
  else echo clear; fi
}
kept $A; kept $B
git -C /Users/grifftatarsky/projects/outpost rev-parse --short HEAD; git status --short
```

Expected today: alpha `sealed` (Lockwood, code 482913), beta `nothing`. The `get_app_container`
form with a group name is from `simctl`'s help as I remember it; **not verified**. If it prints
nothing, find the folder the way this order did: the App Group folder whose
`.com.apple.mobile_container_manager.metadata.plist` names `group.com.microgpt.carpenter`.

Move the old step files out of the way, keep them as the evidence for F1:
`mkdir -p /tmp/outpost-rig-exchange/2026-11-10-first-lock-walk && mv /tmp/outpost-rig-exchange/lock-*.txt "$_"`,
and `cp S/lockwalk.log` there too.

### C1. A check that stops early must fail

File: `App/CarpenterUITests/RigChecks.swift`. UI-test code only.

1. Add, after `read(_:)` (`:122-125`):

   ```swift
   func finish(_ step: String = #function) {
       write("finished", to: String(step.prefix { $0 != "(" }) + ".finished")
   }
   ```

   and make `finish()` the last statement of every `test…` method in the file (29 of them). The
   runner (below) deletes `<test>.finished` before a step and requires it after. This holds whatever
   XCTest does with an expected failure, which is why it is a file and not an assertion in
   `tearDown`: whether an assertion there would also be swallowed is not known.

2. Find out what a failed tap does, once, with a probe that is **not committed**:

   ```swift
   func testWhatAFailedTapDoes() throws {
       let app = launch()
       let landed = tapped(app.buttons["no such button"].firstMatch)
       write(landed ? "landed" : "returned false", to: "failed-tap")
       finish()
   }
   ```

   If `/tmp/outpost-rig-exchange/failed-tap` is missing after the run, a failed tap ends the method,
   and `tapped` and `stillThere` have never returned `false` on a vanished element. Then replace both
   (`:64-79`) with forms that cannot record a failure, and pass the app in:

   ```swift
   func tapped(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
       guard let frame = try? element.snapshot().frame, !frame.isEmpty else { return false }
       app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
       return true
   }

   func stillThere(_ element: XCUIElement) -> Bool {
       guard let frame = try? element.snapshot().frame else { return false }
       return !frame.isEmpty
   }
   ```

   `XCUIElement.snapshot()` is declared `throws`; that it throws on a missing element, and does not
   record a failure, is from memory and **not verified**. Run the probe again: the file must say
   `returned false` and `testWhatAFailedTapDoes.finished` must exist. `stillThere` loses the
   hit-test, so read the first few step screenshots for a tap that landed on something covered. If the
   probe shows a failed tap does *not* end the method, leave `tapped` alone and say so in the report;
   F1 then has another cause and the `.finished` file is still the guard.

3. `settle` (`:81-107`) answers a system alert only at the top of each pass, and only by the labels
   "Allow" and "Don’t Allow". The alert that broke the walk appeared mid-pass and its button is
   identified, not labelled, `kTCCServiceFocusStatus-allow-button` (`S/lockwalk.log:693`). Add:

   ```swift
   func answerSystemAlert() -> Bool {
       let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
       guard alert.exists else { return false }
       let allow = alert.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", "allow-button")).firstMatch
       if allow.exists { allow.tap(); return true }
       for label in ["Allow", "OK", "Don’t Allow"] where alert.buttons[label].exists {
           alert.buttons[label].tap()
           return true
       }
       return false
   }
   ```

   Call it in place of the loop at `:86-90`, and again before each `tapIfThere` in the loop at
   `:95-101`.

Done when: the probe's two files say what happened; a step whose body is cut reports FAILED from the
runner; `xcodebuild build-for-testing` succeeds with no new warning.

### C2. The lock walk as steps, and the missing ones

Same file. "One step per test, one device per run" (`docs/simulator-rig.md:87`).

1. Shared pieces, next to `launch` (`:20-27`):

   ```swift
   var usesICloud: Bool { ProcessInfo.processInfo.environment["RIG_ICLOUD"] == "1" }
   var memberName: String { ProcessInfo.processInfo.environment["RIG_NAME"] ?? "Lockwood" }
   var lockCode: String { read("lock-code").isEmpty ? "482913" : read("lock-code") }

   func launchForLock() -> XCUIApplication {
       usesICloud ? launch() : launch(in: "/tmp/outpost-lock-check")
   }

   func lockedNotice(_ app: XCUIApplication) -> XCUIElement {
       app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "is locked")).firstMatch
   }

   func typeOnPad(_ app: XCUIApplication, _ code: String) {
       for digit in code { app.buttons[String(digit)].firstMatch.tap() }
   }

   func openThroughTheLock(_ app: XCUIApplication) {
       if lockedNotice(app).waitForExistence(timeout: 15) { typeOnPad(app, lockCode) }
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "the code did not open the app")
       settle(app)
   }

   func openLockSettings(_ app: XCUIApplication) {
       app.buttons["You"].firstMatch.tap()
       XCTAssertTrue(tapIfThere(app, "App lock", timeout: 5, scrolling: true), "no App lock row on You")
       XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label IN %@", ["Change code", "Turn on the lock"]))
           .firstMatch.waitForExistence(timeout: 5), "the lock's settings did not open")
   }

   func answerTheCodeAlert(_ app: XCUIApplication, with code: String) {
       let alert = app.alerts.firstMatch
       XCTAssertTrue(alert.waitForExistence(timeout: 5), "the lock would change without the current code")
       let field = alert.secureTextFields.firstMatch
       XCTAssertTrue(field.waitForExistence(timeout: 3), "nowhere to type the current code")
       field.tap()
       field.typeText(code)
       alert.buttons["Continue"].firstMatch.tap()
       sleep(2)
   }

   func wrongCodeNotice(_ app: XCUIApplication) -> XCUIElement {
       app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "That's not it")).firstMatch
   }
   ```

   `launch` gains a second parameter, `in directory: String? = nil`, used for the `--mailbox` path
   (C4 rewrites the same lines; do both together). Labels: the row "App lock" with "On" or "Off"
   is on You's root (`YouView+Settings.swift:168-178`, `YouView.swift:264`); the alert is "Enter your
   current code", field "Code", "Continue" (`AppLockViews.swift:571-593`); the keypad's keys are
   labelled by their digit (`DigitPad.swift:63-74`).

2. `testANewMemberSavesTheKeyAndLocksTheApp`: replace `:153-156` with `let app = launchForLock()`.
   End the method after `settle(app)` at `:214`:

   ```swift
   XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "setup did not end in the app")
   shoot(app, "lock-5c-set-up")
   finish()
   ```

   Delete `:216-273`; the steps below take their place. After `:198` add
   `XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "no software keyboard: the two checks below mean nothing without one")`,
   because `:200` and `:207` test what the keyboard covers and nothing shows one was up.

3. New steps. Written from the screens, **not built**:

   ```swift
   func testTheLockHoldsAndOpens() throws {
       let app = launchForLock()
       let locked = lockedNotice(app)
       XCTAssertTrue(locked.waitForExistence(timeout: 15), "the app started without its lock")
       XCTAssertFalse(app.textFields.firstMatch.exists, "a locked phone was taken for an empty one and offered setup")
       XCTAssertFalse(app.buttons["You"].firstMatch.exists, "the app under the lock could still be reached")
       shoot(app, "lock-6-locked")
       typeOnPad(app, String(repeating: lockCode.hasPrefix("0") ? "1" : "0", count: lockCode.count))
       XCTAssertTrue(wrongCodeNotice(app).waitForExistence(timeout: 10), "a wrong code did not say so")
       shoot(app, "lock-7-wrong-code")
       typeOnPad(app, lockCode)
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "the right code did not open the app")
       settle(app)
       app.buttons["You"].firstMatch.tap()
       XCTAssertTrue(app.staticTexts[memberName].firstMatch.waitForExistence(timeout: 10),
           "what the phone keeps did not come back once the lock opened")
       shoot(app, "lock-8-open")
       XCUIDevice.shared.press(.home)
       sleep(2)
       app.activate()
       XCTAssertTrue(locked.waitForExistence(timeout: 10), "the app came back to the front without its lock")
       shoot(app, "lock-8b-back-in-front")
       finish()
   }

   func testChangesTheCode() throws {
       let old = lockCode
       let new = ProcessInfo.processInfo.environment["RIG_NEW_CODE"] ?? "135790"
       let app = launchForLock()
       openThroughTheLock(app)
       openLockSettings(app)
       XCTAssertTrue(tapIfThere(app, "Change code", timeout: 5), "no way to change the code")
       answerTheCodeAlert(app, with: String(old.reversed()))
       XCTAssertTrue(wrongCodeNotice(app).waitForExistence(timeout: 5), "a wrong current code did not say so")
       XCTAssertFalse(app.buttons["Lock the app"].firstMatch.exists, "a wrong current code opened the way to a new one")
       shoot(app, "lock-12-wrong-current-code")
       XCTAssertTrue(tapIfThere(app, "Change code", timeout: 5))
       answerTheCodeAlert(app, with: old)
       let fields = app.secureTextFields
       XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5), "the current code did not open the way to a new one")
       XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "no software keyboard")
       fields.element(boundBy: 0).tap()
       fields.element(boundBy: 0).typeText(new)
       fields.element(boundBy: 1).tap()
       fields.element(boundBy: 1).typeText(new)
       shoot(app, "lock-13-new-code-typed")
       let lockButton = app.buttons["Lock the app"].firstMatch
       XCTAssertTrue(lockButton.waitForExistence(timeout: 3) && lockButton.isHittable, "no button to keep the new code")
       lockButton.tap()
       let keep = app.alerts.buttons["Keep them as they are"].firstMatch
       if keep.waitForExistence(timeout: 3) { keep.tap() }
       XCTAssertTrue(app.buttons["Change code"].firstMatch.waitForExistence(timeout: 15), "the new code was not kept")
       write(new, to: "lock-code")
       shoot(app, "lock-14-code-changed")

       XCUIDevice.shared.press(.home)
       sleep(2)
       app.activate()
       XCTAssertTrue(lockedNotice(app).waitForExistence(timeout: 10), "the app came back without its lock")
       typeOnPad(app, old)
       XCTAssertTrue(wrongCodeNotice(app).waitForExistence(timeout: 10), "the old code was not refused")
       XCTAssertFalse(app.buttons["You"].firstMatch.exists, "the old code still opens the app")
       typeOnPad(app, new)
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "the new code did not open the app")
       finish()
   }

   func testTurnsTheLockOff() throws {
       let app = launchForLock()
       openThroughTheLock(app)
       openLockSettings(app)
       XCTAssertTrue(tapIfThere(app, "Turn off the lock", timeout: 5), "no way to turn the lock off")
       answerTheCodeAlert(app, with: lockCode)
       XCTAssertTrue(app.buttons["Turn on the lock"].firstMatch.waitForExistence(timeout: 20), "the lock did not turn off")
       shoot(app, "lock-15-off")
       XCUIDevice.shared.press(.home)
       sleep(2)
       app.activate()
       XCTAssertFalse(lockedNotice(app).waitForExistence(timeout: 5), "the lock came up after it was turned off")
       app.terminate()
       app.launch()
       _ = app.wait(for: .runningForeground, timeout: 20)
       XCTAssertFalse(lockedNotice(app).waitForExistence(timeout: 8), "the lock came up at a clean restart after it was turned off")
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15))
       app.buttons["You"].firstMatch.tap()
       XCTAssertTrue(app.staticTexts[memberName].firstMatch.waitForExistence(timeout: 10),
           "what the phone keeps did not open once the lock was off")
       finish()
   }

   func testTurnsTheLockOnInSettings() throws {
       let code = ProcessInfo.processInfo.environment["RIG_NEW_CODE"] ?? "482913"
       let app = launchForLock()
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 20), "the app did not open")
       settle(app)
       openLockSettings(app)
       XCTAssertTrue(tapIfThere(app, "Turn on the lock", timeout: 5), "no way to turn the lock on")
       let fields = app.secureTextFields
       XCTAssertTrue(fields.element(boundBy: 1).waitForExistence(timeout: 5))
       fields.element(boundBy: 0).tap()
       fields.element(boundBy: 0).typeText(code)
       fields.element(boundBy: 1).tap()
       fields.element(boundBy: 1).typeText(code)
       let lockButton = app.buttons["Lock the app"].firstMatch
       XCTAssertTrue(lockButton.waitForExistence(timeout: 3) && lockButton.isHittable)
       lockButton.tap()
       let makePrivate = app.alerts.buttons["Make them private"].firstMatch
       if makePrivate.waitForExistence(timeout: 3) { makePrivate.tap() }
       XCTAssertTrue(app.buttons["Turn off the lock"].firstMatch.waitForExistence(timeout: 20), "the lock did not turn on")
       write(code, to: "lock-code")
       shoot(app, "lock-18-on-from-settings")
       XCUIDevice.shared.press(.home)
       sleep(2)
       app.activate()
       XCTAssertTrue(lockedNotice(app).waitForExistence(timeout: 10), "the app came back without the lock just set")
       typeOnPad(app, code)
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 15), "the code just set did not open the app")
       finish()
   }

   func testTheRecoveryKeyOpensTheLock() throws {
       let key = code("\(memberName).recovery").split(whereSeparator: \.isNewline)
           .map { $0.trimmingCharacters(in: .whitespaces) }
           .first { $0.hasPrefix("KEY:") }.map { $0.dropFirst(4).trimmingCharacters(in: .whitespaces) } ?? ""
       XCTAssertFalse(key.isEmpty, "\(memberName) left no recovery key in the rig's folder")
       let app = launchForLock()
       XCTAssertTrue(lockedNotice(app).waitForExistence(timeout: 15), "the app started without its lock")
       let way = app.buttons["Use your recovery key"].firstMatch
       XCTAssertTrue(way.waitForExistence(timeout: 5) && way.isHittable, "no way to the recovery key from the lock")
       way.tap()
       let field = entry(app, "Paste your recovery key")
       XCTAssertTrue(field.waitForExistence(timeout: 5))
       field.tap()
       field.typeText("NOT-A-KEY")
       XCTAssertTrue(tapIfThere(app, "Unlock", timeout: 3))
       XCTAssertTrue(
           app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "That isn't the recovery key")).firstMatch
               .waitForExistence(timeout: 5), "something that is not the key did not say so")
       XCTAssertTrue(lockedNotice(app).exists, "something that is not the key opened the app")
       shoot(app, "lock-16-not-the-key")
       field.tap()
       field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + key)
       XCTAssertTrue(tapIfThere(app, "Unlock", timeout: 3))
       XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 20), "the recovery key did not open the app")
       settle(app)
       openLockSettings(app)
       XCTAssertTrue(app.buttons["Turn on the lock"].firstMatch.exists, "the recovery key opened the app and left the lock on")
       shoot(app, "lock-17-opened-by-the-key")
       finish()
   }

   func testForgetsTheCodeAndErases() throws {
       let app = launchForLock()
       let locked = lockedNotice(app)
       XCTAssertTrue(locked.waitForExistence(timeout: 15), "the app started without its lock")
       let forgot = app.buttons["Forgot the code?"].firstMatch
       XCTAssertTrue(forgot.waitForExistence(timeout: 5) && forgot.isHittable, "no way back for somebody who forgot the code")
       forgot.tap()
       let erase = app.alerts.buttons["Erase"].firstMatch
       XCTAssertTrue(erase.waitForExistence(timeout: 5), "forgetting did not ask before erasing")
       shoot(app, "lock-10-forgot")
       erase.tap()
       XCTAssertTrue(
           app.textFields.firstMatch.waitForExistence(timeout: 30) || app.buttons["Skip"].firstMatch.exists,
           "erasing did not bring the phone back to the start")
       XCTAssertFalse(locked.exists, "the lock stayed up after the phone's copy was erased")
       shoot(app, "lock-11-erased")
       app.terminate()
       app.launch()
       _ = app.wait(for: .runningForeground, timeout: 20)
       XCTAssertFalse(locked.waitForExistence(timeout: 8), "the lock outlived the erase")
       finish()
   }
   ```

   One more, for a lock over a member that talks to somebody (section 6, rows 18 to 20):

   ```swift
   func testWaitsBehindTheLock() throws {
       let app = launchForLock()
       let locked = lockedNotice(app)
       XCTAssertTrue(locked.waitForExistence(timeout: 15), "the app started without its lock")
       sleep(UInt32(ProcessInfo.processInfo.environment["RIG_SECONDS"].flatMap { UInt32($0) } ?? 60))
       XCTAssertTrue(locked.exists, "the lock went away by itself")
       shoot(app, "lock-19-still-shut")
       finish()
   }
   ```

   And `openChecks` (`:492-504`) and `testRunsARound` (`:527-540`) gain, before `settle(app)`:
   `if !read("lock-code").isEmpty, lockedNotice(app).waitForExistence(timeout: 5) { typeOnPad(app, lockCode) }`,
   so a step on a phone whose lock the rig turned on gets past it. Whether XCUITest sees into the
   lock's own window (`App/Carpenter/AppRootView+Lock.swift:20-39`) has never been tried: every line
   that reads the lock screen is in the part of the old check that never ran.

   Facts these lean on: a recovery key is accepted as the `KEY:` line alone
   (`Packages/Carpenter/Sources/CarpenterKit/Crypto/RecoveryKey.swift:78-96`), upper-case letters,
   digits and hyphens (`:121-127,138`), which suits the field's forced capitals
   (`AppLockViews.swift:217-219`); a new lock locks at once (`AppLock.swift:57-58`); a right code
   clears the count of wrong ones (`AppLock.swift:120-124`), so each step spends at most two of the
   five free tries (`:149`). The recovery sheet's "Unlock" is the only one on screen while the lock
   uses digits (`DigitPad.swift:34-43`). The key button's label is at `AppLockViews.swift:136`, the
   erase alert at `:150-156`, "Turn off the lock" at `:527-532`.

4. The recovery key step needs the key. It is never drawn (`RecoveryKeyView.swift:26-110`) and the
   only way out today is the share sheet. Change C3 leaves it in the rig's folder. Until Griff allows
   C3, skip `testTheRecoveryKeyOpensTheLock` and say so.

### The runner

New file `Scripts/rig-walk-lock.sh`, modelled on `Scripts/rig-walk-removals.sh:19-57`. One device.

```bash
#!/bin/bash
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
device="${1:-5A43F953-128D-4FE6-9135-0D26520E02B6}"
derived="${DERIVED_DATA:-/tmp/carpenter-dd}"
exchange=/tmp/outpost-rig-exchange
app="$derived/Build/Products/Debug-iphonesimulator/Outpost.app"
mkdir -p "$exchange"

kept() {
    local group file
    group="$(xcrun simctl get_app_container "$device" com.microgpt.carpenter group.com.microgpt.carpenter 2>/dev/null)" || { echo "no app"; return; }
    file="$group/com.microgpt.carpenter/state.json"
    if [ ! -e "$file" ]; then echo nothing
    elif [ "$(head -c 9 "$file")" = '{"sealed"' ]; then echo sealed
    else echo clear; fi
}

expect() {
    local found; found="$(kept)"
    if [ "$found" = "$1" ]; then echo "passed  $2: what the phone keeps is $1"
    else echo "FAILED  $2: what the phone keeps is $found, expected $1"; exit 1; fi
}

step() {
    local name=$1 test=$2
    shift 2
    rm -f "$exchange/$test.finished"
    if env TEST_RUNNER_OUTPOST_RIG=1 "$@" xcodebuild test-without-building -workspace Carpenter.xcworkspace \
        -scheme Carpenter -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" \
        -only-testing:"CarpenterUITests/RigChecks/$test" -parallel-testing-enabled NO > "$exchange/$name.log" 2>&1 \
        && [ -e "$exchange/$test.finished" ]
    then echo "passed  $name"
    else echo "FAILED  $name ($exchange/$name.log; finished: $([ -e "$exchange/$test.finished" ] && echo yes || echo no))"; exit 1
    fi
}

fresh() {
    xcrun simctl terminate "$device" com.microgpt.carpenter 2>/dev/null
    xcrun simctl uninstall "$device" com.microgpt.carpenter
    xcrun simctl install "$device" "$app"
}

xcodebuild build-for-testing -workspace Carpenter.xcworkspace -scheme Carpenter \
    -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived" > "$exchange/lock-build.log" 2>&1 \
    || { echo "FAILED  the build ($exchange/lock-build.log)"; exit 1; }

case "$(kept)" in
    sealed) echo "starting from the member already behind a lock" ;;
    nothing | "no app")
        fresh
        rm -rf /tmp/outpost-lock-check "$exchange/lock-code"
        step lock-1-setup testANewMemberSavesTheKeyAndLocksTheApp
        expect sealed lock-1-setup ;;
    clear) echo "this phone holds a member with no lock; erase it or turn its lock on first"; exit 1 ;;
esac

step lock-2-holds testTheLockHoldsAndOpens
step lock-3-change testChangesTheCode
expect sealed lock-3-change
step lock-4-holds-under-the-new-code testTheLockHoldsAndOpens
step lock-5-off testTurnsTheLockOff
expect clear lock-5-off
step lock-6-on testTurnsTheLockOnInSettings
expect sealed lock-6-on
step lock-7-forgot testForgetsTheCodeAndErases
expect nothing lock-7-forgot

if [ "${WITH_RECOVERY_KEY:-0}" = 1 ]; then
    fresh
    rm -rf /tmp/outpost-lock-check "$exchange/lock-code"
    step lock-8-setup testANewMemberSavesTheKeyAndLocksTheApp
    expect sealed lock-8-setup
    step lock-9-recovery-key testTheRecoveryKeyOpensTheLock
    expect clear lock-9-recovery-key
    step lock-10-on-again testTurnsTheLockOnInSettings
    step lock-11-forgot testForgetsTheCodeAndErases
    expect nothing lock-11-forgot
fi
echo "the lock walk passed: on a simulator, where the Secure Enclave is a stand-in, under --mailbox"
```

`fresh` exists because the notifications page is explained once per install: `explained.notifications`
is an `@AppStorage` key (`AppRootView.swift:119`) that an erase does not clear
(`AppSession+Erasing.swift:30-32` clears only `storage.settings`), and the setup step asserts that
page comes before the lock (`RigChecks.swift:184-188`). Uninstall only when `kept` says `nothing`:
keychain items outlive an uninstall (`docs/simulator-rig.md:152`).

### Runs for the lock (L)

- **L1.** `Scripts/rig-walk-lock.sh` on alpha as it stands. It starts from Lockwood and runs
  lock-2 to lock-7. About seven steps at two minutes each.
- **L2.** After C3: `WITH_RECOVERY_KEY=1 Scripts/rig-walk-lock.sh`, lock-8 to lock-11.
- **L3.** Read every step's screenshot, not only the pass line
  (`xcrun xcresulttool export attachments --path <DD>/Logs/Test/<bundle>.xcresult --output-path "$OUT/shots"`).
  Things to look for by eye: the keypad on a 402-point screen, the key button clear of the home
  indicator, the alert's field with the software keyboard up, both appearances
  (`xcrun simctl ui $A appearance dark`, then back to `light`).
- **L4.** One time on beta (440 points wide) with `Scripts/rig-walk-lock.sh $B`, since beta holds
  nothing. Do this only if section 6 will reset beta's account afterwards (F9), or leave it out.

Done when: every step prints `passed`, every `expect` agrees, and the last line prints. If a step
fails, the finding is the result; fix nothing in the app without writing down what it must guarantee
first (`CLAUDE.md`, "Before building").

What this does not prove, to be written exactly so: nothing about the Secure Enclave, Face ID, a
passphrase, the waits, erasing after wrong codes, or a notification while locked.

### Runs for the live suite (S)

Only on devices whose app holds no member over iCloud. Alpha's Lockwood is a `--mailbox` member
behind a lock, which tonight's runs show does not get in the way.

- **S1.** Whole target on **beta** (the single-device command, `$B`). Expect about 100 s, 39 passed
  and 24 skipped, like alpha.
- **S2.** Beta says who it is, so alpha can name it:

  ```bash
  TEST_RUNNER_CARPENTER_PAIR_STEP=beta-id x -destination "platform=iOS Simulator,id=$B" \
    -only-testing:CarpenterTests/LivePairMailboxMeasurements > "$OUT/beta-id.log" 2>&1
  ls -l /tmp/outpost-rig-exchange/pairs/beta-user.json
  ```

- **S3.** `TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 x -destination "platform=iOS Simulator,id=$A" -only-testing:CarpenterTests/CloudKitMailboxTests > "$OUT/mailbox-named.log" 2>&1`.
  `aSpaceIsSharedWithOnePerson` must now take longer than its 4.7 s of tonight, and pass. Then
  `rm -rf /tmp/outpost-rig-exchange/pairs` (the file is beta's record name in this container).
- **S4.** Only if the tree changed since `fe9ec3e`: `pair LivePairTests alice bob`, then
  `pair LivePairSendTests ann ben`. Otherwise tonight's passes stand; cite the logs.

Done when: S1 and S3 pass and the docs say which device and account pair each ran on.

---

## 6. The app's own screens on two Apple Accounts

Nothing here has ever run. It needs Griff's answers to section 9, items 1 to 3, first.

### C3. Let the rig hand codes over without swapping the mailbox

App code, `#if DEBUG` only, compiled out of Release like the rest of the rig.

1. `App/Carpenter/FileMailbox.swift:127-142`, replace `RigCodes` with:

   ```swift
   enum RigCodes {
       static let directory: URL? = {
           let arguments = ProcessInfo.processInfo.arguments
           if let index = arguments.firstIndex(of: "--rig-codes"), index + 1 < arguments.count {
               return URL(fileURLWithPath: arguments[index + 1])
           }
           if let index = arguments.firstIndex(of: "--mailbox"), index + 1 < arguments.count {
               return URL(fileURLWithPath: arguments[index + 1]).appending(path: "codes")
           }
           return nil
       }()

       static func leave(_ code: String, as name: String) {
           guard let directory else { return }
           do {
               try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
               try code.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
           } catch {
               Diagnostics.sync.error(
                   "rig mailbox: could not leave a code — \(String(describing: error), privacy: .public)")
           }
       }
   }
   ```

2. `App/Carpenter/AppRootView+Sync.swift:66`: `if rig != nil, !session.codeForSharing.isEmpty {`
   becomes `if RigCodes.directory != nil, !session.codeForSharing.isEmpty {`.
3. `App/Carpenter/AppRootView+Ready.swift:212`: `if rig != nil, let code = try? issued.encoded() {`
   becomes `if RigCodes.directory != nil, let code = try? issued.encoded() {`.
4. `App/Carpenter/AppRootView.swift:588`, after `issued[person] = try await session.invite(…)`, inside
   the `do`:

   ```swift
   #if DEBUG
       if RigCodes.directory != nil, let code = try? issued[person]?.encoded() {
           RigCodes.leave(code, as: "\(session.viewer.displayName).invite")
       }
   #endif
   ```

   This is the Solo from the list of people and the people picked while making a room.
5. `App/Carpenter/AppRootView.swift:251-257`, on the recovery key page's `NavigationStack`, after
   `.themed(.default)`:

   ```swift
   #if DEBUG
       .task {
           if let text = session.recoveryKeyText() {
               RigCodes.leave(text, as: "\(session.viewer.displayName).recovery")
           }
       }
   #endif
   ```

   That writes a rig member's recovery key into the rig's folder on the Mac. Section 9, item 2.
6. `Scripts/check-release-leaves.sh:56`: add `"rig-codes"` to `LEAVES`.
7. `docs/testing.md`, "Launch arguments for the rig" (`:610-622`) and `docs/simulator-rig.md:295-302`:
   say what `--rig-codes <folder>` does and that it changes nothing else.

Tests for C3: `xcodebuild … build` for the simulator, a generic-device build
(`docs/pre-testflight.md:340`), `./Scripts/lint-branding.sh`, `python3 Scripts/copy-review.py check`,
`Scripts/check-release-leaves.sh $A` (must stay clean with 23 strings), and the package suite once
before committing. No package code changes, so no package test is added; the proof is the walk.

### C4. Rig checks that can run over iCloud

`App/CarpenterUITests/RigChecks.swift`.

1. `:20-27`, `launch`:

   ```swift
   var mailboxDirectory: String { ProcessInfo.processInfo.environment["RIG_MAILBOX"] ?? "/tmp/outpost-rig-mailbox" }
   var codesDirectory: String { usesICloud ? "/tmp/outpost-rig-icloud" : "\(mailboxDirectory)/codes" }

   func launch(_ extra: [String] = [], in directory: String? = nil) -> XCUIApplication {
       let app = XCUIApplication()
       let offline = ProcessInfo.processInfo.environment["RIG_OFFLINE"] == "1" ? ["--mailbox-refuses", "full"] : []
       let world = usesICloud ? ["--rig-codes", codesDirectory] : ["--mailbox", directory ?? mailboxDirectory] + offline
       app.launchArguments += world + extra
       app.launch()
       _ = app.wait(for: .runningForeground, timeout: 20)
       return app
   }
   ```

   and `code(_:)` at `:419-421` reads `"\(directory ?? codesDirectory)/\(name)"`; for the lock steps
   under `--mailbox` that is `/tmp/outpost-lock-check/codes`, so give `code` the same optional
   parameter or make `codesDirectory` follow `launchForLock`. Pick one and keep one copy of the rule.
2. `:9-10`: the skip message says "launch both devices under --mailbox"; make it name `RIG_ICLOUD` too.
3. `:127-146`, `onboard`: replace the silent `if` at `:133` with
   `XCTAssertTrue(field.waitForExistence(timeout: usesICloud ? 60 : 10), "setup was not offered: over iCloud that is an account that already holds a member")`
   and keep the body. After `settle`, assert the member exists:
   `XCTAssertTrue(app.buttons["You"].firstMatch.waitForExistence(timeout: 20), "\(name) was not set up")`.
4. `:458-459`, `testQuadJoins`: the invitation's file is hard-coded as `Trig.invite`. Read
   `"\(ProcessInfo.processInfo.environment["RIG_INVITER"] ?? "Trig").invite"`.
5. New steps, **not built**; labels cited so they can be corrected against a `testDump` tree first:

   ```swift
   func testStartsASoloFromPeople() throws {
       let person = try XCTUnwrap(ProcessInfo.processInfo.environment["RIG_PERSON"], "set RIG_PERSON to who the Solo is with")
       let app = launch()
       sleep(3)
       settle(app)
       app.buttons["Rooms"].firstMatch.tap()
       if !tapIfThere(app, "New solo", timeout: 3), !tapIfThere(app, "Send a Solo", timeout: 2) {
           XCTAssertTrue(tapIfThere(app, "New conversation", timeout: 3), "no way to start a Solo")
           XCTAssertTrue(tapIfThere(app, "Solo", timeout: 3))
       }
       shoot(app, "solo-1-people")
       let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", person)).firstMatch
       XCTAssertTrue(row.waitForExistence(timeout: 5), "\(person) is not among the people this phone knows")
       row.tap()
       sleep(5)
       shoot(app, "solo-2-invitation")
       XCTAssertFalse(
           app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "invitation was not sent")).firstMatch.exists,
           "the Solo was started and its invitation failed")
       XCTAssertFalse(code("\(memberName).invite").isEmpty, "the Solo's invitation never reached the rig's folder")
       finish()
   }

   func testBlocksFromTheirPage() throws {
       let person = try XCTUnwrap(ProcessInfo.processInfo.environment["RIG_BLOCK"], "set RIG_BLOCK to who to block")
       let app = launch()
       sleep(3)
       openChecks(app)
       XCTAssertTrue(roomMenu(app, "Who is in this room"))
       let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", person)).firstMatch
       XCTAssertTrue(row.waitForExistence(timeout: 5), "\(person) is not in the member list")
       row.tap()
       sleep(2)
       shoot(app, "block-1-their-page")
       XCTAssertTrue(tapIfThere(app, "Block everywhere", timeout: 5, scrolling: true), "no Block on their page")
       let block = app.buttons["Block"].firstMatch
       XCTAssertTrue(block.waitForExistence(timeout: 5), "Block on a person's page asked nothing")
       shoot(app, "block-2-asked")
       block.tap()
       sleep(8)
       shoot(app, "block-3-blocked")
       finish()
   }

   func testUnblocks() throws {
       let app = launch()
       sleep(3)
       settle(app)
       app.buttons["You"].firstMatch.tap()
       XCTAssertTrue(tapIfThere(app, "Privacy & Safety", timeout: 5, scrolling: true))
       XCTAssertTrue(tapIfThere(app, "Blocked people", timeout: 5, scrolling: true))
       shoot(app, "unblock-1-list")
       XCTAssertTrue(tapIfThere(app, "Unblock", timeout: 5), "nobody to unblock")
       sleep(8)
       shoot(app, "unblock-2-done")
       finish()
   }

   func testCannotWrite() throws {
       let app = launch()
       sleep(3)
       openChecks(app)
       XCTAssertTrue(
           app.staticTexts["You were removed from this room"].firstMatch.waitForExistence(timeout: 120),
           "this phone never heard it was removed")
       shoot(app, "removed-1-told")
       XCTAssertFalse(entry(app, "Message").waitForExistence(timeout: 3), "a removed member still has somewhere to write")
       finish()
   }
   ```

   Labels: "New solo" and "New conversation" › "Solo" (`RoomsListView+Actions.swift:134,142,159`),
   "Send a Solo" on an empty list (`RoomsListView+Content.swift:214,224`), the failure title
   (`AppRootView.swift:608`), "Block everywhere" on a person's page (`PeopleView.swift:280`), the
   question and its "Block" (`BlockedPeopleView.swift:99-134`), "Privacy & Safety"
   (`YouView+Settings.swift:103`), "Blocked people" (`PrivacyAndSafetySettingsView.swift:231`),
   "Unblock" (`BlockedPeopleView.swift:42`), the removal notice
   (`ConversationView+Transcript.swift:129`). Whether a removed member loses the composer is **not
   verified**; if the field is still there, the step should type and the other side should run
   `testNeverSees`. Whether tapping a member's row opens their page, and which tab lists a Solo, are
   also **not verified**: run `testDump` and `testPeopleAndRooms` (`:373-391,804-809`) first and read
   the trees. The block is walked from the person's page because that is where it was broken on
   2026-11-05 (`docs/simulator-rig.md:422-424`).

### The walk

New file `Scripts/rig-walk-two-accounts.sh`: the same `step` as the lock runner, with a device
argument (`step <name> <device> <test> [VAR=value …]`) and `TEST_RUNNER_RIG_ICLOUD=1` on every step.
Ann is alpha, Ben is beta. Both devices must hold nothing (`kept` says `nothing` on each) and have
the same build installed (`fresh` on each).

| # | Device | Test | Variables | Shows |
|---|---|---|---|---|
| 1 | A | `testFifthOnboards` | `RIG_NAME=Ann` | setup offered over real iCloud; recovery key; notifications; lock declined; check-up |
| 2 | B | `testFifthOnboards` | `RIG_NAME=Ben` | the same on the wider phone |
| 3 | A, then B | `testRunsARound` | `RIG_NAME=Ann` / `Ben` | `Ann.identity` and `Ben.identity` appear in `/tmp/outpost-rig-icloud` |
| 4 | A | `testTrigMakesARoomAndInvitesQuad` | `RIG_ROOM=Kettle RIG_JOINER=Ben` | a room, an invitation by Ben's code |
| 5 | B | `testQuadJoins` | `RIG_INVITER=Ann` | the phrase, *They match* |
| 6 | A, then B | `testRunsARound` | `RIG_ROOM=Kettle` | Ann lets Ben in; Ben sees the room |
| 7 | B | `testQuadSays` | `RIG_ROOM=Kettle RIG_SAY="hello from Ben"` | a message collects before it is written, in the app |
| 8 | A | `testSees` | `RIG_ROOM=Kettle RIG_EXPECT="hello from Ben"` | it crossed two accounts |
| 9 | A, then B | `testQuadSays` / `testSees` | `RIG_SAY="hello from Ann"` | the other way |
| 10 | A | `testStartsASoloFromPeople` | `RIG_NAME=Ann RIG_PERSON=Ben` (delete `Ann.invite` first) | the Solo from the list of people makes an invitation |
| 11 | B | `testQuadJoins` | `RIG_INVITER=Ann` | Ben accepts it without a code of his |
| 12 | A, then B | `testRunsARound`, then `testQuadSays` on B and `testSees` on A in the Solo | `RIG_ROOM=<the Solo's name on that phone>` | the Solo carries a message |
| 13 | B | `testBlocksFromTheirPage` | `RIG_ROOM=Kettle RIG_BLOCK=Ann` | the question, then the block |
| 14 | A | `testQuadSays` | `RIG_ROOM=Kettle RIG_SAY="during the block"` | |
| 15 | B | `testNeverSees` | `RIG_ROOM=Kettle RIG_EXPECT="during the block"` | 90 s with nothing arriving |
| 16 | B | `testUnblocks`, then `testSees` | `RIG_EXPECT="during the block"` | what was said during the block arrives after it |
| 17 | B, then A | `testQuadSays` / `testSees` | `RIG_SAY="after the block"` | both ways again, the 2026-11-05 defect |
| 18 | A | `testTurnsTheLockOnInSettings`, then `testWaitsBehindTheLock` | `RIG_NAME=Ann`, then `RIG_SECONDS=5` | the lock over a real member; the app is left shut and in front. Note `stat -f %m` of alpha's `state.json` and that `kept $A` says `sealed`. |
| 19 | B | `testQuadSays` | `RIG_ROOM=Kettle RIG_SAY="while Ann is locked"` | |
| 19b | A | `testWaitsBehindTheLock` | `RIG_SECONDS=60` | three rounds' worth of time shut (`AppRootView+Sync.swift:19`). `state.json` must have the same `stat -f %m` as at 18, and alpha's log must have no `mailbox fetch` line since 18. |
| 20 | A | `testTheLockHoldsAndOpens`, then `testSees` | `RIG_NAME=Ann`, then `RIG_ROOM=Kettle RIG_EXPECT="while Ann is locked"` | nothing collected while shut, collected once open |
| 21 | A | `testTheRecoveryKeyOpensTheLock` | `RIG_NAME=Ann` | the recovery key opens a real member's lock |
| 22 | A | `testRemoves` | `RIG_ROOM=Kettle RIG_REMOVE=Ben` | the removal, from the member list |
| 23 | B | `testCannotWrite` | `RIG_ROOM=Kettle` | Ben is told, and has nowhere to write |
| 24 | A | `testRecordsMembers` | `RIG_ROOM=Kettle RIG_PEOPLE=Ann,Ben RIG_RECORD=kettle-ann` | `Ann=in,Ben=out` |

Under `RIG_ICLOUD`, `launchForLock` is the plain `launch`, so the lock steps run on Ann as she is.
Between 18 and 21 every step on alpha meets the lock first, which the line added to `openChecks`
gets past. After 21 the lock is off, so 22 and 24 need nothing.

About 37 `xcodebuild` runs at one to two minutes. Keep both apps in front while a message crosses
(`docs/simulator-rig.md:124-127`): a step leaves its app running, and nothing here sends it to the
background except the lock steps.

**The screens changed on 2026-11-10**, to photograph with a member that has real content, after step
17: add one step that opens and `shoot`s each, read from `git show --stat c8bc149`: a message held
down (*Hide for me* with no question, `MessageBubbleView.swift:369`), message detail
(`MessageDetailView.swift:158`), You › Notifications › Messaging and the Outpost notifications page
(`NotificationSettingsSections.swift`), the Outposts tab (`RootView+Outpost.swift`), the join page
with the system's Paste (`Accessibility.swift:122`), You › Integrity. Both appearances, and once at
`xcrun simctl ui $A content_size accessibility-extra-extra-extra-large` for the large symbols; put
`content_size large` back (`docs/testing.md:736-739`).

Done when: every row passes with their `.finished` files, the screenshots were read, and the result
is written down as "two accounts, in the app, on simulators, one run each". A ring after a block
stays unproven: a push from the other account has never reached a simulator here
(`docs/simulator-rig.md:426-428`).

Afterwards both accounts hold a member. Clean with `--reset-account` on each device if Griff allowed
it, and confirm with a first launch that offers setup.

---

## 7. Risks

- **The check that lies.** Until C1 is proven by its probe, a pass means nothing. The `.finished`
  file is the guard; do not report a step without it.
- **A dirty account stops section 6 at step 1.** If either account holds a feed from a device that
  no longer exists (the members made on 2026-11-05 were never reset before their simulators were
  deleted, as far as the docs say: `docs/simulator-rig.md:24-26,411-413`; inferred), setup is never
  offered. The lock walk on alpha may add one (F9). That is why section 6 asks for `--reset-account`
  first.
- **`--reset-account` on a locked phone.** Alpha is behind a lock. `wipe` runs with no enrolment in
  that state and builds its own engine to erase the zone (`AppRootView+Device.swift:206-216`). Read,
  not run. Run the lock walk first, so alpha is empty before any reset.
- **An Apple Account that asks for its password.** Any CloudKit call then fails with
  `AuthTokenError` and only Griff can answer it (`docs/simulator-rig.md:268-271,388-390`). It followed
  a suite run once. Stop and tell him; do not tap *Not Now*.
- **Load.** Erasing or reinstalling devices at once made every step take twenty minutes
  (`docs/simulator-rig.md:333-335`). One device at a time, and nothing else building.
- **The snapshot tap in C1** may tap something covered, and whether `snapshot()` throws is not
  verified. The probe decides.
- **Typing a recovery key into a field** with forced capitals and a growing height
  (`AppLockViews.swift:212-220`): hyphens or the keyboard's own corrections may change it. If the key
  is refused, read `lock-17` before concluding the vault is wrong.
- **The software keyboard.** Nothing in the docs says how it is turned on in Xcode 27's DeviceHub,
  and nothing shows it was up in the first lock walk. The new steps assert it where the keyboard
  matters; if those assertions fail, it is a setting on the simulator, not a defect.
- **Other work in the tree.** Decision 2 (Face ID or the phone's passcode before the code) will
  change the lock's pages and may add *Face ID only*; the sheet rework on the rooms view touches the
  join and Solo sheets. Labels in C2 and C4 are from `fe9ec3e`. Rerun the lock walk after decision 2
  lands; on a simulator the stand-in asks for nothing, so that run proves the screens and not the
  factor.
- **`XCTAssert` text and file names** in the checks are not copy a member reads, so they carry no
  copy markers, like the existing ones.
- **Do not walk** *Erase everything after N wrong codes* on these devices (F9).

---

## 8. Docs to change when the runs are done

Inside existing copy markers; the words change, so each chunk stays or becomes `NEEDS HUMAN REVIEW`.
No new chunk without an id from `python3 Scripts/copy-review.py new-id`.

- `docs/open-questions.md:167-173`: say what was walked on 2026-11-10 (setup only) and what the new
  walk covered, with its date and device.
- `docs/simulator-rig.md:446-449`: the same correction. `:24-26,35-36`: the devices are signed in.
  `:91-94`: the list of steps. `:235-239,247-248`: `--reset-account` exits by itself. `:456-457`: what
  is still not run. Add what F4 and section 6 showed, each as "one run".
- `docs/pre-testflight.md:45-49,113-117`: the lock line and items 3 and 4.
- `docs/testing.md:386-405`: remove `LiveRoundTests`, `LiveOutpostTests` and `LiveRig.joined`; list
  the suites in section 2. `:610-622`: `--rig-codes`. `:411-420`: the table of what has run against a
  real account names files that the pair-space rewrite replaced; check each row against
  `Packages/Carpenter/Sources/CarpenterCloudKit` before keeping it.
- `docs/epics/identity-and-devices.md:455-471`: it cites this check for criteria written before the
  lock sealed anything, and still says the lock "does not encrypt what is stored". Say what the check
  has and has not reached, and leave the rest to whoever owns that epic's rewrite.
- `docs/inbox.md`: F7, F9 (four items), F10's stale script, and F8 if not fixed.
- `docs/roadmap.md:97,99,102,104,241-244,271` and the three epics that cite the deleted suites: only
  after Griff answers section 9, item 6.

---

## 9. Only Griff can decide or supply

1. **May `--reset-account` run on outpost-alpha and outpost-beta**, before section 6 and again after
   it? It erases this app's data in each Apple Account (`docs/simulator-rig.md:241-245`). Without it,
   section 6 stops at the first launch if either account remembers an old device.
2. **May the rig gain `--rig-codes <folder>`, and may a debug build launched with it leave a rig
   member's recovery key and invitations in that folder?** It is app code that exists only for the
   rig, behind `#if DEBUG`, checked out of Release by `check-release-leaves.sh`. Without it, the
   two-account walk and the recovery-key step need codes carried by hand through Files, as on
   2026-11-04 (`docs/simulator-rig.md:370-371`). Recommendation: yes.
3. **Any Apple Account prompt on either simulator** (password, verification). Only he can answer.
4. **He was told the lock was walked end to end on 2026-11-10. It was not** (F1). No decision needed;
   he should know before relying on it, and the three docs say so until they are corrected.
5. **The recovery key on the clipboard** (F7). Keep *Copy* for rig members, or have the checks save
   to Files, which costs a harder step. If the simulator's clipboard can be cut off from the Mac's in
   DeviceHub, that setting is his. Recommendation: allow it for rig members until C3 is in, then drop
   the copy and read the key from the rig's folder.
6. **The proofs that went with `LiveRoundTests` and `LiveOutpostTests`** (F6): repair of a hole, a
   read report, an edit, a withdrawal, a deleted room, and Outposts, over real CloudKit on pair
   spaces. Either the docs stop claiming them, or a third pair suite is written before a tester
   build. Recommendation: write the suite (same shape as `LivePairSendTests`), and correct the docs
   now either way.
7. **Face ID on a simulator**: skip it and walk it on the iPhone with decision 2, or have somebody at
   the Mac enrol Face ID in DeviceHub for one hand-driven look. Recommendation: skip.
8. **A third simulator with no Apple Account**, for lock walks and three-member walks under
   `--mailbox` that then leave nothing in an account (F9). He had the rig cut to two on 2026-11-10.
   Recommendation: yes, one, made only when a walk needs it.

<!-- COPY END 0ffcffb9 -->
