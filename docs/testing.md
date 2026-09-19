---
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

## The suites

| Suite | Runs with | Covers |
|---|---|---|
| Package suite, `Packages/Carpenter/Tests` | `swift test` | The log, cryptography, sync, session and view logic, against fakes. 1,478 tests on 2026-09-17. |
| App suite, `App/CarpenterTests` | `xcodebuild test … -only-testing:CarpenterTests` | What needs a real app bundle: the system keychain, and the live CloudKit tests, which are off unless asked for. |
| UI tests, `App/CarpenterUITests` | `xcodebuild test … -only-testing:CarpenterUITests/<class>` | Apple's accessibility audit, a contrast audit per accent, a label check, and the rig steps. |

CI runs the package suite, the lint and a build of the app.

**What green is worth.** The package suite has been green while the app did not work, more than once.
It proves the logic above the mailbox and cannot prove CloudKit. A run on two accounts is the only
evidence for anything that crosses the network.

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

## The app and the extension

The notification extension opens the shared container through the `readOnly` view of its
`SessionStorage` and writes nothing. `AppAndExtensionTests` checks that a setting and a room deletion
the app saves while the extension runs both survive, that an extension round leaves the shared files
byte-for-byte unchanged, and that the app still collects what the extension saw.

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

### A whole round on one account

A packet is addressed by a `RecipientTag`, never by an account. So two sessions pointed at the
**same** zone write packets to each other's tags and read the one outbox, and a whole round runs over
real CloudKit on one account. `LiveRig.joined(...)` in `LiveRoundTests.swift` sets that up with a
fresh zone per test.

| Suite | What it puts on the real wire |
|---|---|
| `LiveRoundTests` | a message between two identities; a 24-entry round arriving complete and in order; every packet acknowledged; a hole deleted off the server being named and refilled; a read report moving a mark; an edit and a withdrawal; a room deleted after a removal staying deleted after a relaunch |
| `LiveSiblingFeedTests` | the raw record fetched back and searched for the epoch key it must not contain; the payload being exactly the ciphertext; a stranger's identity refused; a second device opening it |
| `LiveOutpostTests` | a post with a photo arriving with identical bytes; an edit and a deletion; an Outpost's own photo; a post unseen by its reader and never by its author; a comment crossing back |

What this cannot cover is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md): a second account
accepting a share, a third party, and anything that needs a phone.

Preferences default to off, and a test that forgets one looks like a delivery failure. Showing other
people's photos and sharing your own are both off until set.

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

## Before a run on two accounts

**Both devices need a build from the same tree.** The app removes subscriptions it does not
recognize, and subscription IDs have changed before, so a device on an old build deletes the new
build's subscriptions.

**Grant notification permission** on any device expected to show a banner. A denied prompt does not
come back; turn it on in Settings.

**Record types are created by the app.** `MessageBell` is seeded into a `Schema` zone before the
subscription that names it. Look for `bell: record type present` in the log.

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

## Accessibility

**Apple's audit.** `AccessibilityAuditTests` calls `performAccessibilityAudit()` on the rooms list,
every tab and a conversation: contrast, hit regions, clipped text and missing descriptions, over the
rendered app. It needs the app idle, so it launches with `--quiet-for-audit`. Issues are recorded one
failure each, with Apple's description and the element.

**The wide layout.** `WideLayoutTests` needs no member: it launches the fixture shell with
`--site-shot rooms` on an iPad (`outpost-ipad` on the rig) and is skipped unless
`TEST_RUNNER_OUTPOST_WIDE=1`. `testPortrait` and `testLandscape` walk rooms, a room, the sidebar,
Outposts, your Outpost, Search, You and Appearance with a screenshot and Apple's audit at each stop;
`testLooks` only screenshots, for running under a setting; the keyboard and Search-to-You tests
assert. Set the setting on the device first and pass `-parallel-testing-enabled NO`, or the runner
tests a clone and shuts the device you configured down:

```bash
xcrun simctl ui <ipad-udid> appearance dark
```

```bash
TEST_RUNNER_OUTPOST_WIDE=1 TEST_RUNNER_OUTPOST_LOOK=dark xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=<ipad-udid>' -parallel-testing-enabled NO -only-testing:CarpenterUITests/WideLayoutTests/testLooks
```

The audit's *Text clipped* on the glass sidebar's labels is the audit, not the app: it measures a
label's frame from the icon's edge and the words draw whole.

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

The first two were a `NavigationStack` with no `.navigationTitle`, so VoiceOver had nothing to
announce and fell back to the first element, which was the chrome. `@AccessibilityFocusState` on the
headline, set on appear and only when VoiceOver is running, fixes it. The third was a missing
heading trait, which `Scripts/lint/screen-headings.py` now fails the build over.

Also read on the same walk, and left alone: the You tab's first stop is the animated mark, announced
"Outpost, Image". That is deliberate — see
[Decisions](decisions.md#the-mark-stands-where-yous-title-would-be-and-that-is-a-departure) — and
the VoiceOver cost is recorded there.

In Xcode 27, `Simulator.app` is replaced by `DeviceHub.app` in `Xcode.app/Contents/Applications`.

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

## Driving a notification's actions

A message banner's Reply and Mark as Read can be driven on the rig without a real push. The pieces
were measured on 2026-09-19:

- **Deliver the banner yourself.** `xcrun simctl push <udid> com.microgpt.carpenter payload.json`
  with `"category": "outpost.message"` in `aps` and the room's UUID under `"outpost.room"` at the top
  level. Leave out `mutable-content`: on a signed-out simulator the extension cannot decrypt anything,
  so the payload's own title and body are what draw. A room's UUID is in the App Group's
  `focusFilter.rooms`.
- **Pull the live banner down; don't long-press it in Notification Center.** Under XCUITest a press
  on a Notification Center entry, for any duration, expands nothing, and a press-and-drag there
  collapses the stack. Dragging the banner down while it is on screen shows the actions every time.
  `RigChecks.testAnswerFromTheBanner` goes home, writes `ready-for-push` into the exchange directory,
  and waits up to 90 seconds for the banner. Push once that file appears.
- **Warm or cold.** Move the app to the background by launching Settings, or quit it with
  `simctl terminate`. A cold launch by the system carries **no launch arguments**, so it has no
  `--mailbox`: its round goes to CloudKit and the answer waits on disk for the next launch under
  `--mailbox`. Read the log for `push: answered from a notification` and the round after it.
- `testQuadSaysWhatItIsTold` (`RIG_SAY`) and `testQuadSeesTheAnswer` (`RIG_EXPECT`) are the other
  end. The second scrolls, because a conversation with unread messages opens at the first of them.

## App Store screenshots

`Scripts/app-store-shots.sh <iphone-udid> <ipad-udid> <out-dir>` boots both, sets the status bar to
9:41, runs `AppStoreShots.testShots` (`TEST_RUNNER_OUTPOST_SHOTS=1`) over the `--site-shot` fixtures,
and exports the images at App Store sizes. The iPad set is captured in landscape and comes out turned,
with an orientation tag that would turn it again; the script fixes both. What the set is and why is in
[App Store](app-store.md#6-screenshots).

## Still unproved underneath notifications

Does a `CKRecordZoneSubscription` on your own private zone fire when a share participant writes into
that zone? It should, because a participant's write into your shared zone lands in your private
database, and the device-sync subscription behaves that way. It has not been observed. If it does not
fire, the fallback is a database subscription on the shared database, still scoped to `MessageBell`,
at the cost of an occasional banner for somebody who shares the sender's outbox but not the room; only
`PushChannel` and `CloudKitMailbox+Bell.swift` would change.
