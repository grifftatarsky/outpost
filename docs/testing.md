---
# COPY BEGIN a23f7c79 [NEEDS HUMAN REVIEW]
title: Testing
layout: default
nav_order: 5
---

# Testing

{: .no_toc }

The suites, what each can and cannot prove, and the practical knowledge for running the app on
simulators. How four simulators are set up and driven is on [the simulator rig](simulator-rig.md).

Two constraints shape everything here.

**One Apple Account cannot prove sharing.** An account cannot take part in its own share, so
anything between two people needs two accounts.

**A simulator does more than it once seemed to.** On Apple silicon it gets a real push token, runs
the notification service extension and reaches a live CloudKit container. It cannot receive an
iCloud Keychain hand-off, so one member on two devices needs real phones, and an account with
Advanced Data Protection on cannot write to CloudKit from a simulator at all. See
[what a simulator can do](simulator-rig.md#what-a-simulator-can-actually-do).

Each epic has its own test plan: [Messaging](epics/messaging.md#test-plan),
[Notifications](epics/notifications.md#test-plan), [Rooms](epics/rooms-and-membership.md#test-plan),
[Identity](epics/identity-and-devices.md#test-plan), [Data etiquette](epics/data-etiquette.md#test-plan),
[Content](epics/content-and-composer.md#test-plan), [Desktop](epics/desktop.md#test-plan).

1. TOC
{:toc}

<!-- COPY END a23f7c79 -->

<!-- COPY BEGIN 4227807f [NEEDS HUMAN REVIEW] -->

## The suites

| Suite | Runs with | Covers |
|---|---|---|
| Package suite, `Packages/Carpenter/Tests` | `swift test` | The log, cryptography, sync, session and view logic, against fakes. 2,009 tests in 348 suites on 2026-11-04. |
| App suite, `App/CarpenterTests` | `xcodebuild test … -only-testing:CarpenterTests` | What needs a real app bundle: the system keychain, and the live CloudKit tests, which are off unless asked for. |
| UI tests, `App/CarpenterUITests` | `xcodebuild test … -only-testing:CarpenterUITests/<class>` | Apple's accessibility audit, a contrast audit per accent, a label check, and the rig steps. |

CI runs the package suite, the app suite, the lint and a build of the app for iOS and macOS.

**What green is worth.** The package suite has been green while the app did not work, more than once.
It proves the logic above the mailbox and cannot prove CloudKit. A run on two accounts is the only
evidence for anything that crosses the network.

<!-- COPY END 4227807f -->

<!-- COPY BEGIN d9819eff [NEEDS HUMAN REVIEW] -->

**Everything at once.** `Scripts/check-all.sh` runs what CI runs, on this Mac: the package suite,
the lint, the copy markers, a build for macOS and for the iOS Simulator, the app suite, and the check
for words a Release build should not carry. Every step runs even when an earlier one fails, so one
run finds every kind of fault. It ends with a digest of the errors, the failed tests and the warnings
in files the branch changed, and copies that digest to the clipboard, which is what a session
without a compiler needs pasted back. `Scripts/check-all.sh --digest` reads the last run's logs
again without rebuilding anything, and `--only app-suite` (or any list of steps) reruns just those.
A failing app-suite test is named from its result bundle, through `xcresulttool`.

<!-- COPY END d9819eff -->

<!-- COPY BEGIN 8a4d142d [NEEDS HUMAN REVIEW] -->

## How the package suite holds up, measured 2026-11-04

**Where the time goes.** The full run with coverage took 382 seconds of test time on 2026-11-04,
with the load average between 400 and 1,000 because several other builds were running. Later the
same night, at a load average under 30, it took 101 seconds and 163 seconds of processor time, so on
average fewer than two of the eight cores were busy. Most of the time is spent on the main actor. 173
suites are `@MainActor`, and every `AppSession` lives there, so those tests take turns on one thread
however many cores the machine has. That is also why a test's reported duration says little about
what it costs: its clock runs while it waits for the main actor. The longest reported 296 seconds,
and the reported durations add up to 36,662 seconds inside a 382-second run. To find out what a
suite costs, run it alone with `--filter`.

**`.serialized` protects nothing here.** 149 suites in 113 files carry it. Each test gets a new suite
value and makes its own sessions, mailbox, clock and scratch folder, and no test reads a static
another test writes (`TestScratch.root` is made once per process and only read). So there is nothing
for the trait to keep apart; all it does is stop the tests of one suite overlapping while they wait.
Taken off all 149 on 2026-11-04, the full suite passed in 121 seconds against 101 with it,
one run each at a similar load, so taking it off saves no time. Alone at a load average of 10, the
formerly serialized suites passed; with a sanitizer build running beside them, two device-sync tests
failed on their five-second deadline, which is the load problem below and not something the trait
guarded. It was left in place.

**What is flaky, and why.** Six tests failed in that loaded run, and each holds a bound in wall-clock
time. Two in `ProjectionCostTests` (drawing the feed, and what a screen reads) and one in
`WhatIsUnsentTests` hold an absolute time per call. `WhatALaunchWritesTests` allows the session three
times what a plain log takes, plus 50 milliseconds. Two poll device sync until a five-second deadline
runs out: "Opening the app on both devices is enough" in `EntrySyncTests`, and "A device away for
longer than mail is kept" in `SiblingMailTests`. `DeletingARoomTests`, `NamingYourDevicesTests`,
`WritesThatCannotLandTests` and the photo loader in `MediaTests` also poll against a deadline of two
to five seconds, and passed. `DeletingARoomTests` also sleeps a fixed 200 milliseconds before it goes
on, which [style](style.md#tests) rules out.

The suites that a search for clocks, sleeps and concurrent code found, 34 suites and 180 tests
including all six, then ran alone ten times at load averages from 230 down to 15, and passed every
time. So none of them is flaky by interleaving that ten runs could find. They are flaky under load,
and the cost tests measure the machine as much as the code. A cost test that counts something
(`projectionBuilds`, decryptions) does not have this problem; one that times something does. The
tests that time themselves carry the tag `timing`, and the device-sync deadlines are a minute now;
see [waiting in a test](#waiting-in-a-test).

<!-- COPY END 8a4d142d -->

<!-- COPY BEGIN c835132c [NEEDS HUMAN REVIEW] -->

**Fakes that are easier than the real thing.** The table under
[the fakes](#the-fakes-are-held-to-the-real-seams) covers the mailbox, the log store, device sync and
screening. Four seams arrived after it and are not in it.
`InMemoryDeathmarkBoard` posts in one step, where `CloudKitDeathmarkBoard.post` deletes the zone,
makes it again and then saves the mark, so a failure between those calls leaves no mark at all; the
fake cannot fail, and no test covers a post that half happened. `FakeHardwareKeys` checks whether the
Secure Enclave is available before looking for the key, and `SecureEnclaveKeys.agree` looks for the
key first, so a missing key and an unavailable enclave come back as different errors in the two.
`StubAccountRegistry` answers whatever it is built with, and the mapping from CloudKit errors to an
answer is tested on its own in `AccountCheckErrorTests`, which is the right split. And
`InMemoryEntrySync` used to live in `CarpenterKit`, so the fake was compiled into the app that ships
though nothing in the app used it. It lives in `CarpenterKitTesting` with the other fakes now, and
`Scripts/check-release-leaves.sh` looks for its name in a Release binary.

**Coverage**, from `swift test --enable-code-coverage` and `llvm-cov`, by lines and by functions:

| Code | Lines | Functions |
|---|---|---|
| `CarpenterKit/Crypto` | 97.9% | 95.4% |
| `CarpenterKit/Membership` | 96.0% | 94.0% |
| `CarpenterKit/Log` | 97.4% | 94.4% |
| `CarpenterKit/Sync` | 92.7% | 84.3% |
| `CarpenterKit/Storage` | 85.6% | 78.9% |
| `CarpenterApp/Session` | 92.1% | 86.2% |
| `CarpenterUI` | 2.4% | 4.6% |
| `CarpenterCloudKit` | 6.7% | 7.1% |

What no test runs, in the parts that matter most. `AppSession.deathmarkNamesThisDevice(on:)`, which
the notification extension calls to decide whether this device was erased from another, has no test,
and repeats the checks in `obeyDeathmark(on:)` rather than sharing them. `WriteBudget` and
`BudgetedMailbox` are tested only in part and are used by nothing in the app: no transport is
budgeted. The write paths of the read-only stores the extension uses (`ReadOnlyLogStore`,
`ReadOnlyKeychainStore`, `ReadOnlyDocumentStore`) never run, so nothing shows they refuse.
`FileAvatarStore` never runs at all, and `FileMediaStore`'s `sealed(for:)`, `remove` and `removeAll`
never run. `DeviceOnlyKeychainStore`, which keeps a test profile's keys off iCloud Keychain, never has
its reads or writes run. `PacketWire.outstanding(in:)` and `TapSwap.disconnected(_:)` never run
either. Two overloads, `EpochGrant.issue(_:at:link:to:)` and
`MembershipAttestation.issue(joining:code:by:at:lifetime:requiring:)`, are called by nothing in the
app or the suite.

**Assumptions that went stale.** The rig is gone from this Mac: `outpost-alpha` and the other four
simulators on [the simulator rig](simulator-rig.md) do not exist here; the simulators are `bullet`,
on iOS 27.2, and `iPhone 17`. `check-all.sh` defaulted to `outpost-alpha`, so it skipped the app
suite and the release check on any machine without the rig. `scan-for-vulnerabilities.sh` named
`outpost-alpha` with `name=`, which on Xcode 27 finds nothing even when the device exists, and
`check-release-leaves.sh` looked it up by name. The screen catalogue command above named
`outpost-27`. All of those were changed the same day: `check-all.sh` defaults to `bullet` and, when
no simulator was named and `bullet` is not there, takes the newest iPhone simulator, which is also
what the other two take when they are not given one. The build and test commands in `CLAUDE.md`
still name `outpost-alpha`'s UDID. CI selects the newest
Xcode 26 on `macos-26`, which on 2026-11-04 was 26.6 with iOS 26.5 at most
([runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)),
while every local build is Xcode 27.1 with Swift 6.4, so CI compiles with an older compiler than
anybody here does and cannot catch what only Xcode 27 reports.

<!-- COPY END c835132c -->

<!-- COPY BEGIN 546f80b2 [NEEDS HUMAN REVIEW] -->

## Before a commit

`.pre-commit-config.yaml` holds six hooks, every one local, so `pre-commit` fetches nothing. They are
not installed by default. `Scripts/install-hooks.sh` installs them for the clone, which means every
worktree of it, and `Scripts/install-hooks.sh --remove` takes them out. `SKIP=<hook-id> git commit`
skips one.

| Hook | What it does |
|---|---|
| `branding-lint` | `Scripts/lint-branding.sh` without the symbol check, when a Swift, plist, xcconfig, entitlements, project or catalogue file is staged |
| `copy-markers` | `copy-review.py check` |
| `swift-format` | swift-format's rules over the staged Swift files, and nothing about layout |
| `whitespace` | trailing whitespace and merge markers on the lines the commit adds |
| `large-files` | a staged file over 512 KB |
| `secrets` | something shaped like a credential, a signing or key file, the Team ID outside the project file, or an account email address, on the lines the commit adds |

The last three read the staged diff, so they never fail over a line the commit did not touch, and
`pre-commit run --all-files` with nothing staged checks nothing for them. The scan runs the credential
shapes over the whole tree and the whole history instead.

**swift-format checks its rules and not the layout.** The house layout is not swift-format's: run over
the tree with its own printer, it reported 1,908 lines indented differently and 690 places where it
would break a line. The codebase was not reformatted, so `Scripts/hooks/swift-format-rules.py` drops
the printer's findings and fails only on the rules in `.swift-format`. Seven rules that the code already breaks are off:
`OrderedImports` (292 places), `DoNotUseSemicolons` (136), `OnlyOneTrailingClosureArgument`,
`OneVariableDeclarationPerLine`, `AlwaysUseLowerCamelCase`, `NoAccessLevelOnExtensionDeclaration` and
`UseLetInEveryBoundCaseVariable`. With them off, the whole tree passes. Never run
`swift format format` over the tree: it would rewrite thousands of lines.

**Speed.** On 2026-11-04 all six hooks took 3.9 seconds over a one-line change to a Swift file, at a
load average of 22. The branding lint took 19 seconds and 10.8 seconds of processor time at a load
average near 1,000 until its three per-file loops became one `awk` each; each loop had started up to
three processes for each of 414 files. Afterwards it took 5.8 seconds and 2.0 seconds of processor
time, at a higher load.

<!-- COPY END 546f80b2 -->

<!-- COPY BEGIN a322ce24 [NEEDS HUMAN REVIEW] -->

## The scan

`Scripts/scan.sh` runs the package suite under Thread Sanitizer, then under Address Sanitizer and
Undefined Behavior Sanitizer together, then `Scripts/scan-for-vulnerabilities.sh`: the dependency
count, `xcodebuild analyze`, and the secret search over the tree and every commit on every branch. It
is `check-all.sh` with those three steps named, so it ends in the same digest, kept apart in
`$TMPDIR/carpenter-scan`. `--only thread-sanitizer` (or either of the others) runs one, and
`--digest` reads the last run again. Each sanitizer builds into its own folder under `.build`, so
switching between them and an ordinary `swift test` does not rebuild everything.

A sanitizer step fails if `otool -L` does not show its runtime in the test binary, because a run
without the runtime is clean and proves nothing. It skips the tests tagged `timing`, which hold a
bound in wall-clock time; the instrumented code is several times slower, so they fail under a
sanitizer for that reason alone. `Scripts/tests-tagged.py timing` prints which ones.

Undefined Behavior Sanitizer is Clang's, made for C, and the package has no C. Swift already stops on
an overflow or an out-of-range index. Whether `-sanitize=undefined` adds any check to Swift code was
not established; it rides in the same build as Address Sanitizer.

`xcodebuild analyze` runs Clang's static analyzer, which reads C, C++ and Objective-C. The repository
has no file in any of them, so a clean analyze says nothing about this code. Run for `bullet` on
2026-11-04, it succeeded, ran no analyzer step at all and reported nothing. The one warning in its
log was the Swift compiler's: an isolated conformance in `CarpenterUI/Previews/Fixtures.swift:61`,
which is preview code compiled only in a debug build. It was left alone. The scan used to count
every warning in the log, so from an empty build folder it failed on that one; it now counts only
warnings in C, C++ and Objective-C files, which are the only ones the analyzer writes.

**Results on 2026-11-04.** Under Thread Sanitizer all 2,009 tests ran in 424 seconds of test time,
with the runtime linked, and no race was reported. The only failures were three `timing` tests,
which is why the step now skips them. Under Address Sanitizer and Undefined Behavior Sanitizer, the
1,994 tests that are not `timing` ran in 200 seconds with the runtime linked, and nothing was
reported. Keep in mind what is written under [practical traps](#practical-traps-on-the-rig): a clean
Thread Sanitizer run once missed a race that was real.

**In CI**, `.github/workflows/scan.yml` runs both sanitizer steps every Monday and on demand, not on
every pull request. Locally the Thread Sanitizer build took 227 seconds and its run 424, against 101
seconds for the plain suite, on eight cores; a standard hosted macOS runner has three
([runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)). That is
too slow to wait for on every push, and affordable once a week.

<!-- COPY END a322ce24 -->

<!-- COPY BEGIN 894dca3c [NEEDS HUMAN REVIEW] -->

## Waiting in a test

A test that waits for device sync or a background task waits for a condition, up to
`TestDeadline.seconds`, which is a minute. It was five seconds in most places until 2026-11-04, and
under load the five seconds ran out before the work did. A test that passes stops waiting the moment
its condition holds, so the longer deadline costs nothing then: after the change no test in a full
run took longer than it had in proportion to the others, so none sits out the minute. The 33 suites
that wait carry `.timeLimit(.minutes(10))`, so a test that hangs fails instead of holding the run.
Ten minutes is generous on purpose: at a load average near 1,000 the slowest test took five, almost
all of it waiting for its turn on the main actor, and a time limit counts that too.

<!-- COPY END 894dca3c -->

<!-- COPY BEGIN 7e5a7491 [NEEDS HUMAN REVIEW] -->

## Running one area

Suites carry a tag for what they are about, defined in `Tags.swift`: `crypto` (375 tests),
`membership` (498), `sync` (445), `storage` (107) and `ui` (353), counted on 2026-11-04. A suite can
carry two, and one about the whole session carries none, so a tagged run is a quick check while
working and never the gate. `Scripts/test-tag.sh crypto` runs the tests tagged `crypto`, and anything
after the tag goes to `swift test`, for example `--skip-build`. The tag is given by the file a suite
is in, read from its name and its suite titles, so check it before trusting a tagged run to cover a
change.

`swift test --filter tag:crypto` runs nothing on Swift 6.4 (measured 2026-11-04: "No matching test
cases were run"); filtering by tag from the command line is proposal
[ST-0025](https://forums.swift.org/t/review-st-0025-tag-based-test-execution-filtering/87320), in
review in June 2026. So `Scripts/tests-tagged.py` reads the tags out of the source and prints a
`--filter` pattern, and the sanitizer steps use the same script to skip `timing`. Xcode reads the tags
as they are.

<!-- COPY END 7e5a7491 -->

<!-- COPY BEGIN 64f99f8f [NEEDS HUMAN REVIEW] -->

**What only a phone can answer.** `FileProtectionTests` is skipped on a simulator, which does not keep
a file's protection class (measured 2026-09-28). On an iPhone, unlocked:

```bash
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS,id=<phone>' -derivedDataPath /tmp/carpenter-device -only-testing:CarpenterTests/FileProtectionTests
```

Two things each cost a round getting it to pass on 2026-09-28. Xcode's own build folder for the phone
was left from an old checkout, and a package in it compiled against an older `CarpenterKit`:
"cannot find type 'ProtectionDial' in scope", for a type that exists. The same code built and passed
in a fresh `-derivedDataPath`. And a `URL` keeps the resource values it has read, so a test that
reads a file's protection, changes it and reads again gets the first answer; the test reads through
`FileManager.attributesOfItem`, which goes to the file every time.

The report `sync` returns stops before the repairs a round runs. A test that counts what a repair wrote
reads the mailbox as the other person would (`WhatARepairRequestCanCostTests`); one that reads the
report sees zero and passes.

<!-- COPY END 64f99f8f -->

<!-- COPY BEGIN 43897dc9 [NEEDS HUMAN REVIEW] -->

## The fakes are held to the real seams

A fake that is easier than the real thing hides the bugs the real thing has. `TheFakeIsNoEasierTests`
holds each in-memory stand-in to the rules its real counterpart enforces. Add to it when a seam gains
a rule.

| Seam | Rule the real one enforces | How the fake used to be easier |
|---|---|---|
| `Mailbox` | a record over `MailboxRules.recordByteCeiling` is refused | accepted any size. The ceiling is the app's own; CloudKit accepted 16MB on 2026-09-14, and `CloudKitMailbox.put` weighs records so both refuse the same thing. |
| `MediaMailbox` | an upload can be swept only after `MailboxRules.sweepAge` | had no idea when a record was written |
| `MediaMailbox` | a photo is handed only to an address it was sent to | handed the bytes to anyone |
| `LogStore` | every entry is encoded, and one over the ceiling is refused | held the struct, so a type that failed to serialize passed |
| `EntrySync` | the feed crosses as bytes | held the struct. This is the one that put every epoch key in CloudKit in the clear for four weeks. |
| `MediaScreen` | Apple's analyzer refuses to look with screening off, refuses bytes that are not a picture, and refuses a clip that is not on disk | answered all three (fixed 2026-09-17, `TheFakeScreenIsNoEasierTests`) |

`MemoryMediaStore` matches `FileMediaStore`. There is no fake `DocumentStore`: tests use the real one
in a temporary directory. `InMemoryKeychainStore` matches the system keychain on what the app relies
on, and the one refusal the real keychain has, reading before first unlock, has its own fake.

One fake is harsher than the real thing, and stays that way: `InMemoryMailbox` is one pool where the
real mailbox is a zone per account, so a test can only ever sweep more than the app would.

<!-- COPY END 43897dc9 -->

<!-- COPY BEGIN 8a469d2c [NEEDS HUMAN REVIEW] -->

## The app and the extension

The notification extension opens the shared container through the `readOnly` view of its
`SessionStorage` and writes nothing. `AppAndExtensionTests` checks that a setting and a room deletion
the app saves while the extension runs both survive, that an extension round leaves the shared files
byte-for-byte unchanged, and that the app still collects what the extension saw.

<!-- COPY END 8a469d2c -->

<!-- COPY BEGIN 385dcc11 [NEEDS HUMAN REVIEW] -->

## The CloudKit integration tests

`App/CarpenterTests` holds tests that run against a **real account and container**. They are off
unless asked for, so CI and ordinary runs pass without an account:

```bash
TEST_RUNNER_CARPENTER_CLOUDKIT_TESTS=1 xcodebuild test -workspace Carpenter.xcworkspace \
  -scheme Carpenter -destination 'platform=iOS Simulator,id=<udid>' \
  -only-testing:CarpenterTests -parallel-testing-enabled NO
```

Two things about that command are required:

- **`-parallel-testing-enabled NO`.** Parallel testing runs on a clone of the simulator, and a clone
  has no iCloud account, so every test reports "no iCloud account".
- **The variable goes before `xcodebuild`.** Written after it, it becomes a build setting, the suite
  disables itself, and every test "passes" in a hundredth of a second. A run that fast was skipped.

`CloudKitMailboxTests` covers what has gone wrong before: a packet's bytes, wraps and grant lists
surviving the round trip; every field in `CloudKitMailbox.scannedFields` coming back; reading without
a query; a photo's bytes in their own record type; acknowledgment stopping a packet being offered;
the order records come back in; and the record ceiling in both directions.

<!-- COPY END 385dcc11 -->

<!-- COPY BEGIN 21adf5cb [NEEDS HUMAN REVIEW] -->

### A whole round on one account

A packet is addressed by a `RecipientTag`, never by an account. So two sessions pointed at the
**same** zone write packets to each other's tags and read the one outbox, and a whole round runs over
real CloudKit on one account. `LiveRig.joined(...)` in `LiveRoundTests.swift` sets that up with a
fresh zone per test.

| Suite | What it puts on the real wire |
|---|---|
| `LiveRoundTests` | a message between two identities; a 24-entry round arriving complete and in order; every packet acknowledged; a hole deleted off the server being named and refilled; a read report moving a mark; an edit and a withdrawal; a room deleted after a removal staying deleted after a relaunch |
| `LiveSiblingFeedTests` | the raw record fetched back and searched for the epoch key it must not contain; the payload being exactly the ciphertext; a stranger's identity refused; a second device opening it; a new device's request and its approval crossing, with the new device deleting both from inside the handler that received them; a reinstalled device writing over the record its earlier install left |
| `LiveOutpostTests` | a post with a photo arriving with identical bytes; an edit and a deletion; an Outpost's own photo; a post unseen by its reader and never by its author; a comment crossing back |

What this cannot cover is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md): a second account
accepting a share, a third party, and anything that needs a phone.

Preferences default to off, and a test that forgets one looks like a delivery failure. Showing other
people's photos and sharing your own are both off until set.

<!-- COPY END 21adf5cb -->

<!-- COPY BEGIN 648bc4a4 [NEEDS HUMAN REVIEW] -->

### Which parts of the mailbox have run against a real account

| File | What it does | Proved |
|---|---|---|
| `CloudKitMailbox+Packets.swift` | put, fetch, pending deliveries, acknowledge | five live tests |
| `CloudKitMailbox+Attachments.swift` | upload, download, who still owes it, the sweep | three live tests |
| `CloudKitMailbox.swift` | `scannedFields`, `everything`, `searchable`, `locate` | through the two above, and `ScannedFieldsTests` |
| `CloudKitMailbox+Subscriptions.swift` | what this device asks to be told about | five live tests |
| `CloudKitMailbox+Share.swift` | sharing the outbox and accepting a share | two accounts on the rig, 2026-09-14 |
| `CloudKitMailbox+ReverseChannel.swift` | leaving a share link in a peer's zone | two accounts on the rig, 2026-09-14 |
| `CloudKitMailbox+Bell.swift` | ringing a peer's bell | rung on the rig, 2026-09-14; the push did not arrive |
| `PeerZoneDirectory.swift` | which zone answers to which address | six tests that need no account, run in CI |

The last three need a second account, which is why they were proved on the rig rather than in the
suite. On 2026-09-14, with beta's account reset first, the log showed each step in order: the share
accepted, the bell subscribed, the reverse channel written and collected, both sides reaching each
other with the room key crossing, and the bell rung.

**The push did not arrive.** With beta in the background for five minutes after its bell was rung,
nothing reached the app. Griff had seen a banner arrive on a real phone on 2026-09-09, and simulators
are a poor witness for subscription delivery, so this does not show push is broken; it shows the app
cannot depend on push, which is why it syncs in the foreground. See
[Proofs a rig cannot run](proofs-a-rig-cannot-run.md).

**Two things these tests have taught.** A subscription saved for a record type the container does not
have is saved anyway, and then breaks `allSubscriptions()` for the whole database; the app now says so
instead of swallowing the error. And removing `PacketWire.grantValues` from `scannedFields` fails two
tests in about three seconds, a mistake that once took an afternoon of a rendezvous reporting "found 0
offer(s)".

<!-- COPY END 648bc4a4 -->

<!-- COPY BEGIN 499d6f75 [NEEDS HUMAN REVIEW] -->

## Before a run on two accounts

**Both devices need a build from the same tree.** The app removes subscriptions it does not
recognize, and subscription IDs have changed before, so a device on an old build deletes the new
build's subscriptions.

**Grant notification permission** on any device expected to show a banner. A denied prompt does not
come back; turn it on in Settings.

**Record types are created by the app.** `MessageBell` is seeded into a `Schema` zone before the
subscription that names it. Look for `bell: record type present` in the log.

<!-- COPY END 499d6f75 -->

<!-- COPY BEGIN f3785643 [NEEDS HUMAN REVIEW] -->

## Reading the logs

The app writes its own diagnostics to a file in the App Group container, and the pull script
collects them:

```bash
Scripts/pull-device-logs.sh
```

Output goes to `/tmp/dec-logs/`: `<Device>.log` per device, `<Device>-nse.log` for the notification
extension, and `mac.log`. The extension is a separate process and cannot use `OSLogStore`, so it
appends plain lines to its own file. If that file is missing, the extension has not handled a bell
push on that device yet.

| Line | Means |
|---|---|
| `storage: … appGroup=true` | The shared container resolved. `false` is serious; see below. |
| `push: registered N subscription(s)` | Followed by one line per subscription. |
| `mailbox put: wrote a packet addressed to N recipient(s)` | A send left this device. |
| `mailbox: rang a peer's bell` | A banner was asked for a real message. |
| `mailbox: a message went out with nobody to ring` | Sent, and nobody told. |
| `mailbox: no bell for a peer whose mailbox this device has not seen yet` | The bell had no address. |
| `mailbox: restored N learned mailbox address(es)` | Peer zones came back from disk, so a bell can ring before a fetch. |
| `mailbox: N packet(s) held back` | Something would not verify, so it was not acknowledged. A few during a join is normal; a number that never falls is a certificate that never arrives. |
| `mailbox fetch: N zone(s) reachable … M addressed to us` | A collection round. |
| `nse: delivering a decrypted banner` | The extension could open the message. |
| `nse: delivering the generic banner` | It could not. Check the keychain group first. |
| `media: uploaded <id> bytes=N recipients=M` | A photo or clip left this device before its entry was written. |
| `media: fetched <id> bytes=N` | The other side collected it; the ID and size should match. |
| `media: no outbox holds <id> any more` | The entry arrived after the sender's outbox let the bytes go. The bubble says *No longer available*. |
| `media: swept an upload no entry names` | A launch cleared an upload whose entry was never written. |
| `mailbox: a round of N entries went as M of K packets` | A round was split. `M < K` means one failed; the rest go next round. |

**If either process logs `appGroup=false`, stop.** An extension's fallback directory is in its own
container, so it is reading a private copy that is always behind, and that looks exactly like a slow
process.

<!-- COPY END f3785643 -->

<!-- COPY BEGIN ef9139da [NEEDS HUMAN REVIEW] -->

## Xcode's own tools, for an agent

Xcode 27 exposes its tools to an outside agent through `xcrun mcpbridge`: building, running tests,
rendering a SwiftUI preview to an image, tapping and typing in a simulator, reading the console, and
lldb. The first call from a new agent has to open the workspace (`XcodeOpenWorkspace`), which asks
you in Xcode to approve it. To give Claude Code the tools directly:

```bash
claude mcp add xcode -- xcrun mcpbridge
```

`RenderPreview` builds the app's scheme for Xcode's active run destination and returns a picture of
one `#Preview`, and it can vary dark mode, contrast, Dynamic Type and orientation. That is how the
search tab was checked on iOS 27 on 2026-09-26. The tools act on Xcode's active scheme and run
destination, so switch them back when you are done. For the rig, `xcodebuild` and `simctl` are still
the way to install one build on four simulators.

<!-- COPY END ef9139da -->

<!-- COPY BEGIN 84215733 [NEEDS HUMAN REVIEW] -->

## Photographing every screen

`ScreenCatalogueTests` is a UI test that opens the demo app (`--site-shot`), taps every tab, every
row and every toolbar button it can reach, and saves a screenshot of each screen it lands on. It is
what the copy review's pictures come from, and what finds a screen the review is missing. It never
taps anything whose label says erase, delete, subscribe or buy, and it leaves an alert only by a
button that cancels; when it cannot find one, it closes the app and starts again rather than guess.
It is off unless asked:

```bash
TEST_RUNNER_CARPENTER_SCREEN_CATALOGUE=1 xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=<udid>' -only-testing:CarpenterUITests/ScreenCatalogueTests -resultBundlePath /tmp/catalogue.xcresult
```

```bash
xcrun xcresulttool export attachments --path /tmp/catalogue.xcresult --output-path /tmp/catalogue
```

It reaches what a tap reaches in the demo. Alerts that follow a failure, notification banners and
the system's permission prompts are not there, and neither is anything that needs a second device.

<!-- COPY END 84215733 -->

<!-- COPY BEGIN 20da20a2 [NEEDS HUMAN REVIEW] -->

## The copy slideshow

Griff reviews every word a member reads in one page: a slide per screen, a picture beside the words,
a box per string. The tools are in `Scripts/copy-slides`, and they work in a folder of your choosing
(called `DIR` here), never in the repository.

1. **Slides.** `python3 Scripts/copy-slides/slides.py DIR NEW.json` reads every copy chunk in the app
   and writes `DIR/slides.json`. `NEW.json` is a list of chunk ids written or changed since his last
   pass; the page lists them first, under "New or changed by Claude".
2. **Pictures.** The site shots come from `--site-shot` on a simulator (`simctl launch`, then
   `simctl io … screenshot` into `DIR/raw/site-<name>.png`). Previews come from
   `render_previews.py DIR`, through Xcode's tools, which Xcode asks you to approve once. The catalogue
   comes from `ScreenCatalogueTests` (above), exported into `DIR/catalogue`. `shots.py DIR` fits them
   to the slides and writes `DIR/shots`.
3. **Publish** `Scripts/copy-slides/page.html` with `DIR/slides.json` and `DIR/shots/` beside it, to
   the same page as before, so his saved edits stay.
4. **Apply a batch.** Export the page's `edits` and `screens` collections into a folder, then run
   `apply.py EXPORT` to see what changes and `apply.py EXPORT --write` to make them. His words go in
   and their chunks become `HUMAN REVIEWED, UNVERIFIED`, as do the chunks of every screen he marked
   done. Removals and notes are listed for doing by hand. Then drop the finished screens, rebuild, and
   sweep for any screen the slideshow is missing.

<!-- COPY END 20da20a2 -->

<!-- COPY BEGIN 44ff8f19 [NEEDS HUMAN REVIEW] -->

## Tools in a debug build

You › **Debug**, which is compiled out of a release build; `Scripts/check-release-leaves.sh` checks the
release binary for their words.

| Tool | What it does |
|---|---|
| **Check mailbox** | Puts one packet through CloudKit and reports each step. |
| **Rotate mailbox share** | Erases this member's outbox zone and shares it again, so every peer holds a dead link, to watch the rendezvous heal. |
| **Pretend a Focus is on** / **ended** | Drives Do Not Disturb sharing without a Focus, which a simulator does not have. |
| **Haptics** | Plays each cue and names what could be silencing them. |
| **Demo conversation**, **Demo Outpost feed** | Scripted content for layout and pacing. |
| **Blur every photo** | Treats every photo as sensitive, to see the blur the system will not trigger on a simulator. |
| **Show message delay** | Under each message that arrived while the app ran, this device's time of arrival minus the sender's timestamp. It includes the two clocks' disagreement, can be negative, and is not a latency measurement. |

**Erase everything** is not a debug tool: it is the last section of You in every build.

*Check for missing history*, in every conversation's menu, is for members too. It asks everyone, one
person or the other person in a Solo, and says who has answered and what is still missing, counted
from the log when it is read.

<!-- COPY END 44ff8f19 -->

<!-- COPY BEGIN 637f9cc2 [NEEDS HUMAN REVIEW] -->

## Launch arguments for the rig

Debug builds only, all named in `Scripts/check-release-leaves.sh`, and defined in
`App/Carpenter/UITestMode.swift` and `FileMailbox.swift`. The rig's own flags, such as `--mailbox`,
are on [the simulator rig](simulator-rig.md).

- **`--quiet-for-audit`** turns off syncing, device sync, the foreground loop and push registration,
  so an audit can find the app idle. It stops work and changes nothing drawn.
- **`--clock-ahead-days <n>`** gives the session a clock `n` days ahead, to see what only appears with
  time. Invitation expiry moves too.
- **`--channel testflight|appstore`** makes a debug build behave as a TestFlight or App Store build for
  the Supporter year.

<!-- COPY END 637f9cc2 -->

<!-- COPY BEGIN ffab2533 [NEEDS HUMAN REVIEW] -->

## Accessibility

**Apple's audit.** `AccessibilityAuditTests` calls `performAccessibilityAudit()` on the rooms list,
every tab and a conversation: contrast, hit regions, clipped text and missing descriptions, over the
rendered app. It needs the app idle, so it launches with `--quiet-for-audit`. Issues are recorded one
failure each, with Apple's description and the element.

**Contrast per accent.** `AccentContrastAuditTests` runs the contrast audit once per accent on Solos
and You, the two screens whose colors depend on it, using `-theme.accent <name>`. Run it in light and
dark; the appearance comes from the simulator.

**Labels.** `VoiceOverWalkTests` writes each screen's element tree into the report and fails on any
button, image, field, switch or link with no label. It is a label check, not a VoiceOver walk:
XCUITest returns the whole tree in tree order, not the stops VoiceOver makes. Three system-drawn
elements are excluded by name because they are not the app's to label.

**VoiceOver on a simulator.** It runs, and what it says can be read from a screenshot. Turn the
caption panel on and it draws its own speech along the bottom of the screen:

```bash
xcrun simctl spawn <udid> defaults write com.apple.Accessibility VoiceOverCaptionPanelEnabled -int 1
xcrun simctl spawn <udid> defaults write com.apple.Accessibility VoiceOverTouchEnabled -int 1
xcrun simctl spawn <udid> launchctl kickstart -k user/foreground/com.apple.VoiceOverTouch
```

Set both to `0` and kick it again to turn it off. `xcrun simctl io <udid> screenshot` then captures
the caption with the screen, headlessly, taking no focus.

<!-- COPY END ffab2533 -->

<!-- COPY BEGIN ff189202 [NEEDS HUMAN REVIEW] -->

**What can be measured this way: the arrival announcement.** Injected taps *do* activate controls
with VoiceOver running, so a whole flow can be navigated, and the caption after each step is the
first thing VoiceOver says on that screen. That is the announcement a member hears when a screen
appears, and it is where this app's VoiceOver defects have actually been — see the walk of
2026-09-17 below.

**What cannot: the cursor.** Measured 2026-09-17, and this corrects what this page used to say.

- An injected **flick** does not move the VoiceOver cursor. The caption does not change.
- An injected **touch path** — a slow drag, which is touch exploration on a real phone — does not
  move it either.
- **Synthesized keystrokes do not reach the device at all.** Not "only with the window frontmost":
  at all. With `outpost-gamma` selected in DeviceHub, that window frontmost, *Simulate Hardware
  Keyboard* checked and a text field focused with its caret blinking, `System Events` typing
  `hydrogen` put nothing in the field. VO keys (`⌃⌥→`, `⌃⌥A`) did nothing for the same reason.

So the reason the full walk waits for a phone is stronger than "it would take the Mac's keyboard".
A script cannot drive it from this machine at all; it needs a person's hands on a real keyboard, or
a phone. Griff ruled on 2026-09-17 that it waits for the TestFlight build.

**The walk of 2026-09-17**, done with the arrival announcements, found three things the element-tree
label tests could not, because every element already had a label:

| Screen | Said | Now says |
|---|---|---|
| Supporter thank-you | "Close, Button" | "You're a Supporter, Heading" |
| Show the badge? | "Back button" | "Show the Supporter badge?, Heading" |
| Notifications and Photos explainers | "Notifications" / "Photos" | "..., Heading" |

<!-- COPY END ff189202 -->

<!-- COPY BEGIN 66fc43cb [NEEDS HUMAN REVIEW] -->

The first two were a `NavigationStack` with no `.navigationTitle`, so VoiceOver had nothing to
announce and fell back to the first element, which was the chrome. `@AccessibilityFocusState` on the
headline, set on appear and only when VoiceOver is running, fixes it. The third was a missing
heading trait, which `Scripts/lint/screen-headings.py` now fails the build over.

Also read on the same walk, and left alone: the You tab's first stop is the animated mark, announced
"Outpost, Image". That is deliberate — see
[Decisions](decisions.md#the-mark-stands-where-yous-title-would-be-and-that-is-a-departure) — and
the VoiceOver cost is recorded there.

In Xcode 27, `Simulator.app` is replaced by `DeviceHub.app` in `Xcode.app/Contents/Applications`.

<!-- COPY END 66fc43cb -->

<!-- COPY BEGIN 991e837f [NEEDS HUMAN REVIEW] -->

## Practical traps on the rig

**Turn the software keyboard on before looking at any screen with a field.** A simulator types on the
Mac's keyboard, which no member has. The first time a software keyboard was raised, on 2026-09-11,
four things were wrong at once:

- `.submitLabel(.send)` on a multi-line field renames the return key and removes the newline without
  making it send. It was measured and reverted: the arrow in the field sends, and return writes a
  second line.
- Nine screens had no way to dismiss the keyboard, which covered the control below the field.
- A tap gesture over a focused field swallowed caret placement.
- A sheet with a fixed height hid its own button under a growing field.

**Tests write under one folder per run.** `TestScratch.root` is the temporary directory for every
test file, one folder per test process, and each run deletes the folders of runs that have ended.
Until 2026-09-27 each full run left about 200 MB that nothing removed; seventy runs in a night filled
the disk with 15 GB and stopped the build mid-audit. A new test that needs a temporary file takes it
from `TestScratch.root`, never `URL.temporaryDirectory`.

**A switch that does not move may be the harness.** Injected taps moved SwiftUI switches on
2026-09-07 and did not on 2026-09-15, when a short drag did. A switch that moves and saves nothing is
also a real defect this app has had twice, so read the preference before deciding:

```bash
D=$(xcrun simctl get_app_container <udid> com.microgpt.carpenter data)
plutil -p "$D/Library/Preferences/com.microgpt.carpenter.plist"
```

**Dynamic Type.** `xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large` changes a
running app at once; `content_size large` puts it back. Put it back before an audit, because the test
runner clones the setting. The Large Content Viewer only shows while a finger is down, so start a
delayed screenshot, then hold for a few seconds and drag off before lifting.

**Count to ten for a crash that happens sometimes.** The launch crash of 2026-09-12 killed about one
launch in two:

<!-- COPY END 991e837f -->

<!-- COPY BEGIN 2da3b51a [NEEDS HUMAN REVIEW] -->

```bash
for i in $(seq 1 10); do
  xcrun simctl launch <udid> com.microgpt.carpenter >/dev/null 2>&1
  sleep 9
  xcrun simctl terminate <udid> com.microgpt.carpenter 2>/dev/null
done
ls -t ~/Library/Logs/DiagnosticReports/Outpost-*.ips | head -1
```

Three clean runs of a one-in-two fault happen one time in eight, and on that day they did, long enough
to nearly revert a good commit. A clean Thread Sanitizer run is not an all-clear either: it reported no
races while the race was real, because Swift's atomic reference counting looks synchronized to it.
Check with `otool -L` that the sanitizer runtime is linked before trusting a clean result.

**Sample the app before blaming the tools.** On 2026-09-15 taps stopped landing and the status bar
clock froze, and the first explanation written down was Xcode 27. Sampling the app showed the main
thread busy decrypting the log inside a render. See
[Architecture](architecture.md#nothing-a-render-reads-may-do-work).

<!-- COPY END 2da3b51a -->

<!-- COPY BEGIN 1663deed [NEEDS HUMAN REVIEW] -->

## Still unproved underneath notifications

Does a `CKRecordZoneSubscription` on your own private zone fire when a share participant writes into
that zone? It should, because a participant's write into your shared zone lands in your private
database, and the device-sync subscription behaves that way. It has not been observed. If it does not
fire, the fallback is a database subscription on the shared database, still scoped to `MessageBell`,
at the cost of an occasional banner for somebody who shares the sender's outbox but not the room; only
`PushChannel` and `CloudKitMailbox+Bell.swift` would change.

<!-- COPY END 1663deed -->
