<!-- COPY BEGIN 6b740085 [NEEDS HUMAN REVIEW] -->

# Work order: plan step 11, test waits counted in attempts

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Source of the step: `docs/pre-testflight.md:131-133`.

Read at commit `9af603a` on `overnight-2026-10-31`, 2026-11-10. No Swift file had uncommitted changes
when read; four docs did (`docs/inbox.md`, `docs/pre-testflight.md`, `docs/epics/foundations.md`,
`docs/epics/notifications.md`), so re-read a doc before editing it. Every line number is from that
commit. Each change below also quotes the text to find, because another step may move lines first.

Nothing was built or run for this work order. Every statement about what the compiler accepts or
what a test does at run time is marked "inferred" unless a file and line shows it.

Paths are relative to `/Users/grifftatarsky/projects/outpost`. `T/` means
`Packages/Carpenter/Tests/CarpenterKitTests/`. `APP/` means `Packages/Carpenter/Sources/CarpenterApp/Session/`.

---

## 1. What it must guarantee

CLAUDE.md asks for these before code, and Griff confirms them (see section 11).

1. A wait in the package suite ends when its condition holds or after 2,400 looks. No clock ends it.
   A busy machine makes the wait longer and never makes it fail.
2. Between looks the test sleeps 25 milliseconds, so on a quiet machine the cap is the minute it is
   today, and a test that is really broken still fails in about a minute with its own message.
3. A wait on a real network keeps its clock: the live suites in `App/CarpenterTests` and the UI
   tests. In the package suite one clock is left, `.timeLimit(.minutes(10))`, which ends a hang.

What it has to stand up to: the full run's own 2,170 tests taking turns on the main actor
(`docs/testing.md:74-77`), a sanitizer build beside it (`docs/testing.md:86-88`), a three-core CI
runner (`docs/testing.md:255-257`).

---

## 2. What is there now

The cap is `TestDeadline.seconds = 60` and `TestDeadline.fromNow` (`T/TestDeadline.swift:3-7`),
added by commit `5dbdac3` on 2026-11-04, which raised nineteen waits from five seconds. There are
21 loops of the form `while …, Date() < deadline` in the package tests and none in
`CarpenterKitTesting` (grep for `deadline`, `Task.sleep`, `Task.yield`, `ContinuousClock`,
`Date() <` over both). The fakes hold no wait at all: `InMemoryEntrySync` and its `Relay`
(`Packages/Carpenter/Sources/CarpenterKitTesting/InMemoryEntrySync.swift:4-166`) are two actors with
no clock in them.

What the waits wait for is work the app starts in its own tasks and nobody awaits:
`incomingTask` (`APP/AppSession+DeviceSync.swift:13-33`), `Task { await publishOwnEntries() }`
(`APP/AppSession+DeviceSync.swift:316-324`, with `publishing` and `publishAgain` at
`APP/AppSession.swift:225-226`), and two saves (`APP/AppSession+Membership.swift:170` and `:739`).
All of it is in the test process. None of it needs time; it needs turns.

### A. Shared helpers that wait on the wall clock

| Helper | Where | Loop | Called from |
|---|---|---|---|
| `AppSession.settleDeviceSync(until:)` | `T/SettlingDeviceSync.swift:6-12` | check, `refreshDeviceSync()`, sleep 25 ms, until `TestDeadline.fromNow` | 27 calls in 13 files: `BeingToldAboutARestoreTests` 68, 288, 467; `AnEntryTooBigToSendTests` 260; `TellingTheRemovedLastTests` 73; `WhatARepairRequestCanCostTests` 382; `RestoringFromAKeyTests` 68, 115; `DeviceEnrolmentTests` 72, 94, 111, 125; `SiblingMailTests` 33, 69, 119; `APacketNobodyIsTrackingTests` 77, 96; `NothingGoesOutThatIsNotOnDiskTests` 126, 365, 376; `NobodyButTheSenderClearsAPhotoTests` 276; `DeviceApprovalTests` 222, 287; `OneMemberTwoDevicesTests` 37, 84; `SettingsFromAnotherDeviceTests` 27, 40 |
| `AppSession.settleDeviceSync()` | `T/SettlingDeviceSync.swift:14-22` | refresh, sleep 25 ms, count four quiet polls in a row (`publishing || publishAgain` resets), until `TestDeadline.fromNow`. Returns silently when the deadline passes | 77 calls in 21 files (`grep -n 'settleDeviceSync()' T/*.swift`): `SiblingMailTests` 14, `NothingGoesOutThatIsNotOnDiskTests` 7, `OneMemberTwoDevicesTests` 6, `WhatRemovingADeviceCutsOffTests` 6, `ChangingYourHiddenAddressTests` 5, `WhoCanTellYouWhereToReadSomebodyTests` 5, `APacketNobodyIsTrackingTests` 4, `DeathmarkTests` 4, `ForgingAKeyTests` 4, `AnEntryTooBigToSendTests` 3, `BeingToldAboutARestoreTests` 3, `DeviceEnrolmentTests` 3, `MailBetweenDevicesIsSealedPerDeviceTests` 2, `NobodyButTheSenderClearsAPhotoTests` 2, `NothingIsSnatchedTests` 2, `TellingTheRemovedLastTests` 2, and one each in `HistoryRepairTests`, `RestoringFromAKeyTests`, `SettingsFromAnotherDeviceTests`, `WhatARepairRequestCanCostTests`, `WritingOldDatesTests` |
| `AppSession.approveNewDevice(_:timeout:)` | `T/ApprovingANewDevice.swift:8-32` | two loops on one deadline, sleep 20 ms each (lines 16-25 and 27-30). `timeout:` defaults to `TestDeadline.seconds` and no caller passes it (the word `timeout` appears nowhere else under `Packages/Carpenter/Tests` or `Sources`) | 40 calls in 24 files (`grep -n 'approveNewDevice(' T/*.swift`) |

28 test files reach one of these three. Those files hold 246 `@Test` lines.

### B. Local helpers and inline loops on the wall clock

| # | Where | Test or helper | Loop |
|---|---|---|---|
| B1 | `T/DeviceEnrolmentTests.swift:11-18` | `settle(_:until:)`, called at 176, 210, 238, 283, 319, 361, 380, 383 | the same loop as `settleDeviceSync(until:)`, copied |
| B2 | `T/DeviceEnrolmentTests.swift:249-256` | "History from another device survives a relaunch" (223) | rebuilds the session every 50 ms until the room shows |
| B3 | `T/EntrySyncTests.swift:15-22` | `settle(_:until:)`, called at 43 | the same copy as B1 |
| B4 | `T/EntrySyncTests.swift:78-86` | "Opening the app on both devices is enough, even if nothing announced itself" (54) | refresh both, sleep 25 ms |
| B5 | `T/HistoryRepairTests.swift:764-771` | `FinalRefusalThroughTheSessionTests.settle(_:until:)` | the same copy as B1. **Never called** (`grep -n 'settle(' T/HistoryRepairTests.swift` prints only line 764) |
| B6 | `T/HistoryRepairTests.swift:794-799` | "An entry a revoked device signed past its cutoff is taken back everywhere…" (773) | refresh both, sleep 25 ms |
| B7 | `T/NamingYourDevicesTests.swift:95-100` | "Names reach the member's own devices and nobody else" (78) | refresh both, sleep 25 ms |
| B8 | `T/TheDeviceListTellsTheTruthTests.swift:113-118` | "A device that has never written anything still reaches the list, and says so" (95) | refresh both, sleep 25 ms |
| B9 | `T/SilentFailureTests.swift:110-115` | `RevocationReportingTests.pair()` (89), used by that suite's tests | refresh both, sleep 25 ms |
| B10 | `T/DeviceAddedNoticeTests.swift:47-52` | "A second phone of Bob's reaches Alice as a dated line…" (18) | refresh both, sleep 25 ms |
| B11 | `T/DeletingARoomTests.swift:347-360` | `settle(_:_:until:)`, called at 325 and 338 in "Deleting on one device deletes on the member's other device…" (300) | refresh both, sleep 25 ms, then four more rounds of the same |
| B12 | `T/WhatRemovingADeviceCutsOffTests.swift:47-53` | `rig(announcing:)` (20), used by the suite | refresh and `settleDeviceSync()` on each of two devices, no sleep of its own. A deadline around waits that each have their own deadline |
| B13 | `T/WhoCanTellYouWhereToReadSomebodyTests.swift:59-65` | `rig()` (34) | the same as B12 |
| B14 | `T/ChangingYourHiddenAddressTests.swift:58-64` | `rig(announcing:)` (32) | the same as B12 |
| B15 | `T/SiblingMailTests.swift:165-171` | "A device away for longer than mail is kept is caught up when it comes back" (131) | the same as B12 |
| B16 | `T/WritesThatCannotLandTests.swift:23-26` | "A join nonce that cannot be written down is reported, not swallowed" (10) | sleep 10 ms. Waits for the save at `APP/AppSession+Membership.swift:170` |
| B17 | `T/NothingGoesOutThatIsNotOnDiskTests.swift:69-72` | `waitUntil(_:)`, called at 163 and 192 | `Task.yield()` in a tight loop until the deadline |

### C. Fixed sleeps

| # | Where | Test | What the sleep stands in for |
|---|---|---|---|
| C1 | `T/DeletingARoomTests.swift:327-328` | "Deleting on one device deletes on the member's other device…" | 200 ms after `second.sendOwnEntries()`, for the publish to finish. `docs/testing.md:98-99` already says style rules this out |
| C2 | `T/EntrySyncTests.swift:102` | "A device does not receive its own writes back" (92) | 100 ms for nothing to happen. Under load the 100 ms can pass before the device's sync task has run, and the test passes without having looked (inferred) |
| C3 | `T/AppSessionTests.swift:390` | "Room organisation survives a relaunch too" (378) | 50 ms for the save started at `APP/AppSession+Membership.swift:739`. Under load 50 ms may not be enough, and then the test fails (inferred) |
| C4 | `T/SendRaceTests.swift:57` and `:96`, `T/ReplicaRaceTests.swift:59` and `:106` | the four "typed mid-sync" and "typed mid-fetch" tests | 30 or 60 ms inside a mailbox hook, so a send started in its own task lands while the round is suspended. Under load the send may not have run in that time; the test still passes, without the interleaving it is named for (inferred) |

### D. Already counted in attempts

`T/MediaTests.swift:559-566` (`settled(_:)`, 200 × 10 ms, called at 573, 583, 596, 608, 619, 621) and
`T/MediaTests.swift:652-656` (400 × 10 ms). No clock. They are a second and third copy of the loop.

### E. Not waits, leave alone

- `T/PushArrivalsTests.swift:27`: a 50 ms sleep inside the handler under test. Nothing gives up on it.
- `T/TestVideo.swift:83` and `:89`: 5 ms polls of an `AVAssetWriterInput`, with no cap. Real AVFoundation.
- `T/ArrangingRoomsDoesNotRollBackTests.swift:74, 77, 80`, `T/NothingGoesOutThatIsNotOnDiskTests.swift:165`,
  `T/SiblingFeedIsSealedTests.swift:223`: single `Task.yield()` calls, no clock.
- `ContinuousClock().measure` in `T/AKeysNumberIsNotALoopBoundTests.swift:59` and
  `T/APacketOfStrangersTests.swift:77`, and the rest of the fifteen tests tagged `timing`: they time a
  cost, they do not wait. Already parked at `docs/inbox.md:497-503`.
- `settleRegistration(attempts:)`, which starts at `APP/AppSession+Identity.swift:104`, is app code
  the app calls (`App/Carpenter/AppRootView+Opening.swift:37` and two more). It already counts attempts.

### F. Must stay on the wall clock: they wait on a real network or another process

All in `App/CarpenterTests`, all enabled only when `LiveCloudKit.isAsked`
(`App/CarpenterTests/CloudKitMailboxTests.swift:11-13`). Do not touch any of them.

| Where | What it waits for |
|---|---|
| `LivePairTests.swift:25-32`, `LivePair.waitFor(_:minutes:)`, 17 calls (8 in `LivePairTests.swift`, 9 in `LivePairSendTests.swift`) | a file the other simulator's test process leaves in `/tmp/outpost-rig-exchange`, every 2 s for six minutes |
| `LivePairTests.swift:44-56`, `LivePair.until(…)`, 15 calls (9 and 6) | a CloudKit round every 3 s for six minutes |
| `LivePairSendTests.swift:21-26`, `rounds(_:_:through:)`, 4 calls | a CloudKit round, then 2 s |
| `LiveSiblingFeedTests.swift`, the seven loops that start at 72, 132, 153, 177, 214, 233 and 273 | 30 tries, 2 s apart, for a record to show in CloudKit |
| `LiveSiblingFeedTests.swift:303, 313, 335`, `LiveDeathmarkTests.swift:49` | 2 s so iCloud's stored times differ |
| `CloudKitMailboxTests.swift:18-24`, `LiveCloudKit.mailbox()`, 12 calls in five files | 10 tries, 2 s apart, for the account status |
| `CloudKitSubscriptionTests.swift:16-19`, 6 calls | 10 tries, 1 s apart, for subscriptions |
| `LivePairMailboxMeasurements.swift:431` | 120 s between steps of a measurement |

### G. Must stay on the wall clock: UI tests

`App/CarpenterUITests` (`RigChecks.swift`, `UXFindingsTests.swift`, `VoiceOverWalkTests.swift`,
`AccentContrastAuditTests.swift`, `ScreenCatalogueTests.swift`) use XCUITest's
`waitForExistence(timeout:)` and `app.wait(for:timeout:)`, which take seconds, and two
`Thread.sleep` calls (`ScreenCatalogueTests.swift:51, 72`). They drive a real app in a simulator and
run only by hand (`docs/inbox.md:252-253`). Do not touch them.

---

## 3. Which tests have failed, and which would

Recorded:

- "History from another device survives a relaunch" (`T/DeviceEnrolmentTests.swift:223`, loop B2)
  failed once in a full run on 2026-09-14 on a ten-second deadline (`docs/inbox.md:247-250`).
- "Opening the app on both devices is enough…" (`T/EntrySyncTests.swift:54`, loop B4) and "A device
  away for longer than mail is kept…" (`T/SiblingMailTests.swift:131`, loop B15) failed on 2026-11-04
  at a load average near 1,000 on five seconds (`docs/testing.md:91-96`, `docs/inbox.md:497-500`).
- `approveNewDevice`'s first loop ("the request from the new device never reached the approving
  device", `T/ApprovingANewDevice.swift:26`) failed the same day (commit `5dbdac3`, message). The
  test it failed in is not recorded.
- Two device-sync tests failed on five seconds with a sanitizer build running beside them
  (`docs/testing.md:86-88`). Not named.

Since the cap became a minute, no failure is recorded in the docs I read. The plan says a test that
takes one second alone reports seventy in the full run (`docs/pre-testflight.md:131-133`) and does
not name it. Not verified here: nothing was run.

Would fail (inferred): any test that reaches a loop in A or B, when its turn on the main actor is
slow enough that the minute passes first. Those are among the 246 tests in the 28 files of section
A, plus the tests of B16 and B17. Which of them do, and at what load, is not measured. C3 would fail
the same way on its 50 ms. C2 and C4 would not fail; they would stop testing what they are named
for.

Two suites wait and carry no time limit, against `docs/style.md:176-178`:
`T/APacketNobodyIsTrackingTests.swift:8` and `T/MailBetweenDevicesIsSealedPerDeviceTests.swift:25`.
After this change the time limit is the only thing that ends a hung wait under load, so they need it.

---

## 4. The helper

One file, `T/Eventually.swift`, replacing `T/TestDeadline.swift`. No imports are needed: `Duration`
and `Task.sleep(for:)` come with the standard library (`Swift` and `_Concurrency`).

```swift
enum TestWait {
    static let attempts = 2_400
    static let pause: Duration = .milliseconds(25)
}

@MainActor
func eventually(
    _ done: () async throws -> Bool, otherwise step: () async throws -> Void = {}
) async rethrows {
    for _ in 0..<TestWait.attempts {
        if try await done() { return }
        try await step()
        try? await Task.sleep(for: TestWait.pause)
    }
}
```

It returns nothing. Every caller already asserts after its wait, in its own words, and those
messages stay.

Why these choices:

- **Order.** Look, step, pause. That is the order of 20 of the 21 loops today (all but
  `settleDeviceSync()`), so a condition that already holds costs no refresh.
- **The pause is a sleep, not `Task.yield()`.** Apple: "If this task is the highest-priority task in
  the system, the executor immediately resumes execution of the same task"
  (https://developer.apple.com/documentation/swift/task/yield(), read through
  https://developer.apple.com/tutorials/data/documentation/swift/task/yield().json). A test run alone
  would spend 2,400 yields in a few milliseconds while a save on another executor was still running,
  and fail on a quiet machine (inferred, not measured). The sleep suspends the test, which frees the
  main actor the same way. Do not "simplify" it to a yield. B17 is a yield loop today and only works
  because a clock bounds it.
- **2,400 × 25 ms.** A minute alone, which is today's cap and what `docs/testing.md:266-267` says.
  25 ms is what 12 of the 21 loops already use. Under load a look takes one turn of the main
  actor's queue however long that is, and the work being waited for is in the same queue, so it
  advances at least one hop per look (inferred from how the main actor queues work of equal
  priority; not measured).
  How many looks the slowest wait needs under load is **not known**; step 7.4 measures it.
- **`@MainActor`, plain closure types.** Every caller is a `@MainActor` suite or an `AppSession`
  extension (checked for each file in section 5). `waitUntil` at
  `T/NothingGoesOutThatIsNotOnDiskTests.swift:69-72` already takes `() async -> Bool` in a main-actor
  method and compiles, so this signature should too (inferred). If Swift 6.4 objects to calling the
  closures, mark both parameter types `@MainActor` and nothing else changes.
- **Names.** `eventually` and `TestWait` are not declared in the Swift, `_Concurrency`, Foundation,
  SwiftUI, Darwin or Testing interfaces of the installed SDK, and there is no C function
  `eventually(` under the SDK's `usr/include` (grep, 2026-11-10). Neither name exists in the
  repository's Swift.

`UnnecessaryEffectMarker` is an error in every target (`Packages/Carpenter/Package.swift:4-8`). Where
a `try await Task.sleep` is replaced by a call that cannot throw, drop the `try`.

---

## 5. The changes, file by file

### 5.1 `T/TestDeadline.swift` → `T/Eventually.swift`

Delete `TestDeadline.swift`. Add `Eventually.swift` with exactly the code in section 4.

### 5.2 `T/SettlingDeviceSync.swift`, whole file

```swift
@testable import CarpenterApp

extension AppSession {
    func settleDeviceSync(until condition: () -> Bool) async {
        await eventually { condition() } otherwise: {
            await refreshDeviceSync()
        }
    }

    func settleDeviceSync() async {
        var quietLooks = 0
        await eventually {
            quietLooks = publishing || publishAgain ? 0 : quietLooks + 1
            return quietLooks > 4
        } otherwise: {
            await refreshDeviceSync()
        }
    }
}
```

`import Foundation` goes; only `Date` used it (inferred; put it back if the compiler asks).

`settleDeviceSync()` today looks only after a refresh and a pause, and wants four quiet looks. The
new one also looks once before the first refresh, so it wants five. When nothing is publishing on
entry that is the same four refreshes as today. When something is, it is one refresh and 25 ms more.
Every look today's version counts, this one counts too, so it never returns earlier than today's.

### 5.3 `T/ApprovingANewDevice.swift`, the function body

Leave the import lines as they are. Replace the function (lines 8-32) with:

```swift
    func approveNewDevice(_ newDevice: AppSession) async throws {
        if newDevice.state == .checkingForRegistration {
            newDevice.checkAccount(with: StubAccountRegistry(hasMember: true))
            await newDevice.settleRegistration()
        }
        let pending = try #require(newDevice.pendingDevice?.id, "the new device is not waiting for approval")
        await eventually { deviceRequests.contains { $0.device == pending } } otherwise: {
            await newDevice.refreshDeviceSync()
            await refreshDeviceSync()
        }
        let request = try #require(
            deviceRequests.first { $0.device == pending },
            "the request from the new device never reached the approving device")
        try await approveDevice(request)
        await eventually { newDevice.enrolment != nil } otherwise: {
            await newDevice.refreshDeviceSync()
        }
        try #require(newDevice.enrolment != nil, "the new device never took its approval")
    }
```

The `timeout:` parameter goes; nobody passes it. The two messages are unchanged. The two waits each
get their own 2,400 looks where they shared one minute.

### 5.4 `T/DeviceEnrolmentTests.swift`

- Delete `private func settle(_ session: AppSession, until condition: () -> Bool) async` (lines 11-18)
  and the blank line after it.
- At the eight call sites (176, 210, 238, 283, 319, 361, 380, 383) change `await settle(X) {` to
  `await X.settleDeviceSync {`. `X` is `second`, `mine` or `first`. The closures do not change.
- B2, lines 249-256. Find `var relaunched = TestSession.make(keychain: secondKeychain, at: directory)`.
  Replace from there through the closing brace of the `while` with:

```swift
        var relaunched = TestSession.make(keychain: secondKeychain, at: directory)
        await relaunched.load()
        await eventually { arrived(relaunched) } otherwise: {
            relaunched = TestSession.make(keychain: secondKeychain, at: directory)
            await relaunched.load()
        }
```

### 5.5 `T/EntrySyncTests.swift`

- Delete `private func settle(_ session: AppSession, until condition: () -> Bool) async` (15-22) and
  the blank line after it.
- Line 43: `await settle(incoming) {` → `await incoming.settleDeviceSync {`.
- B4, lines 78-86. Find `let deadline = TestDeadline.fromNow`. Replace through the loop's closing
  brace with:

```swift
        await eventually {
            incoming.rooms.first?.name == "Kitchen"
                && incoming.messages(in: room).contains { $0.body == "door code changed" }
        } otherwise: {
            await original.refreshDeviceSync()
            await incoming.refreshDeviceSync()
        }
```

- C2, line 102: `try await Task.sleep(for: .milliseconds(100))` → `await session.settleDeviceSync()`.
  That makes at least four fetches from the relay and waits for the device's own publish to end,
  which is the thing that could hand its writes back.

### 5.6 `T/HistoryRepairTests.swift`

- Delete the unused `private func settle(_ session: AppSession, until condition: () -> Bool) async`
  in `FinalRefusalThroughTheSessionTests` (764-771) and the blank line after it.
- B6, lines 794-799. Find `while !pad.rooms.contains(where: { $0.id == room }), Date() < deadline {`.
  Replace the `let deadline` line and the loop with:

```swift
        await eventually { pad.rooms.contains { $0.id == room } } otherwise: {
            await phone.refreshDeviceSync()
            await pad.refreshDeviceSync()
        }
```

### 5.7 Four loops of the same form

Each: delete the `let deadline = TestDeadline.fromNow` line and replace the `while` loop.

`T/NamingYourDevicesTests.swift:95-100`:

```swift
        await eventually { sibling.deviceName(me) != nil } otherwise: {
            await first.refreshDeviceSync()
            await sibling.refreshDeviceSync()
        }
```

`T/TheDeviceListTellsTheTruthTests.swift:113-118`:

```swift
        await eventually { first.devices.count >= 2 && second.devices.count >= 2 } otherwise: {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
        }
```

`T/SilentFailureTests.swift:110-115` (keep the order, second then first):

```swift
        await eventually { first.devices.count >= 2 } otherwise: {
            await second.refreshDeviceSync()
            await first.refreshDeviceSync()
        }
```

`T/DeviceAddedNoticeTests.swift:47-52`:

```swift
        await eventually { bob.devices.count >= 2 } otherwise: {
            await bob.refreshDeviceSync()
            await bobsSecond.refreshDeviceSync()
        }
```

### 5.8 `T/DeletingARoomTests.swift`

- C1, lines 327-328. Keep `second.sendOwnEntries()`. Replace
  `try await Task.sleep(for: .milliseconds(200))` with:

```swift
        await eventually { !second.publishing && !second.publishAgain }
```

  `sendOwnEntries()` sets `publishing` before it returns (`APP/AppSession+DeviceSync.swift:316-324`)
  and `publishOwnEntries` clears it in a `defer` (`:327`), so this waits for exactly the publish the
  sleep was guessing at. The file has `@testable import CarpenterApp`.
- B11, lines 347-360. Replace the helper with:

```swift
    private func settle(_ first: AppSession, _ second: AppSession, until done: () -> Bool) async throws {
        await eventually { done() } otherwise: {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
        }
        for _ in 0..<4 {
            await first.refreshDeviceSync()
            await second.refreshDeviceSync()
            try? await Task.sleep(for: TestWait.pause)
        }
    }
```

  The signature keeps `throws` so the two `try await settle(…)` calls stay as they are. The four
  closing rounds stay interleaved on purpose: the test is looking for the second device's feed
  handing a key back to the first, which needs the first to fetch after the second has published.
  Two `settleDeviceSync()` calls in a row would not do that.

### 5.9 The four loops that wrap `settleDeviceSync()`

A wait whose step is itself two waits would take about nine minutes to give up alone (2,400 looks of
about 225 ms). So the step becomes the two refreshes, as in 5.7, and the settling moves after the
wait, which leaves both devices quiet on the way out as today.

`T/WhatRemovingADeviceCutsOffTests.swift:47-53`. Replace the `let deadline` line and the loop with:

```swift
        await eventually { !restored.rooms.isEmpty } otherwise: {
            await stolen.refreshDeviceSync()
            await restored.refreshDeviceSync()
        }
        await stolen.settleDeviceSync()
        await restored.settleDeviceSync()
```

`T/WhoCanTellYouWhereToReadSomebodyTests.swift:59-65`: the same with `thief` for `restored` and
`phone` for `stolen`.

`T/ChangingYourHiddenAddressTests.swift:58-64`: the same with `tablet` for `restored` and `phone`
for `stolen`.

`T/SiblingMailTests.swift:165-171` (the test ends right after, so no settling):

```swift
        await eventually { away.messages(in: room).count >= 4 } otherwise: {
            await away.refreshDeviceSync()
            await original.refreshDeviceSync()
        }
```

If one of these four fails ten runs in section 7, put its old loop body back inside `otherwise:`,
add an `attempts:` parameter to `eventually` defaulting to `TestWait.attempts`, pass 300 at that
site, and say so in the report.

### 5.10 Condition-only waits

`T/WritesThatCannotLandTests.swift:23-26`. Replace the `let deadline` line and the loop with:

```swift
        await eventually { alice.integrity.writesFailed > before }
```

`T/NothingGoesOutThatIsNotOnDiskTests.swift`: delete `private func waitUntil(_ condition: () async -> Bool) async`
(69-72) and the blank line after it. At 163 and 192 change
`await waitUntil { await log.appendsArrived == before + 1 }` to
`await eventually { await log.appendsArrived == before + 1 }`.

`T/MediaTests.swift:559-566`:

```swift
    private func settled(_ loader: MediaLoader) async -> MediaLoadState {
        await eventually { loader.state(of: Self.attachment, sentBy: Self.author) != .loading }
        return loader.state(of: Self.attachment, sentBy: Self.author)
    }
```

`T/MediaTests.swift:652-656`. Replace `var state = …` and the `for … where` loop with:

```swift
        await eventually { loader.state(of: attachment, sentBy: Self.author) != .loading }
        let state = loader.state(of: attachment, sentBy: Self.author)
```

`T/AppSessionTests.swift:390`, C3. Replace `try await Task.sleep(for: .milliseconds(50))` with:

```swift
        await eventually { first.stateOnDisk?.organisation.isPinned(room) == true }
```

`stateOnDisk` is set only after the file is written (`APP/AppSession.swift:231-243`), and that
function is the only place the state file is saved (`grep -rn 'documents.save(' Packages/Carpenter/Sources`
prints one line). The file has `@testable import CarpenterApp`.

### 5.11 Time limits on the two suites that lack one

- `T/APacketNobodyIsTrackingTests.swift:8`: `@Suite("A packet no device is tracking leaves iCloud", .serialized)`
  → add `.timeLimit(.minutes(10))` after `.serialized`.
- `T/MailBetweenDevicesIsSealedPerDeviceTests.swift:25`: the suite titled "A device with no receiving
  key does not make the others' mail readable by the identity alone" → the same.

A time limit on a suite applies to each test in it, and going over records a failure
(https://developer.apple.com/tutorials/data/documentation/testing/trait/timelimit(_:).json, the data
behind https://developer.apple.com/documentation/testing/trait/timelimit(_:)).

### 5.12 Optional, its own commit, only with a yes (section 11): the race tests, C4

In `T/SendRaceTests.swift:55-58` and `:94-97` and `T/ReplicaRaceTests.swift:57-60` and `:104-107`,
replace the two lines inside the hook with one that waits for the send itself, keeping each test's
own text:

```swift
        await mailbox.onPut { @Sendable in
            _ = try? await alice.send("typed while sending", to: room)
        }
```

(`onFetch` in `ReplicaRaceTests`; the texts are "typed while sending", "ring for this", "typed while
fetching", "survives a relaunch".) The send then always finishes while the round is suspended in the
mailbox, which is what 30 and 60 ms were hoping for. It can only hang if `send` waits for the round.
From reading it does not: `append` (`APP/AppSession.swift:367-427`) waits only for
`oneWriteAtATime` (`:429-437`), which wraps the two log appends (`:400` and
`APP/AppSession+Sync.swift:324`) and not the mailbox call. Inferred; run each of the four tests alone
first, and if one hangs, revert this part only.

---

## 6. Order of work

1. Before any edit, the baseline in 7.1.
2. 5.1 to 5.10 together: none of it compiles without the rest once `TestDeadline` is gone.
3. 5.11.
4. Filtered run (7.2), then the checks in 7.3, then the measurement (7.4) and the loaded runs (7.5).
5. Docs (section 8).
6. 5.12 only if told to.

If commits are asked for: one for 5.1 to 5.10 ("Count test waits in attempts, not seconds"), one for
5.11, one for the docs, one for 5.12. Say in each what was run.

---

## 7. Tests to run, and what done looks like

Do not build in a folder another process is using. `swift test --scratch-path <a folder of your own>`
keeps this work apart, as `Scripts/check-all.sh:198` does for the sanitizer runs. `$SCRATCH` below
is that folder.

**7.1 Baseline, on the untouched tree.** Run the whole package suite once quiet and three times
under load, and write down for each: the load average (`uptime`), the count of tests, every failing
test and its message. Load, on eight cores:

```bash
for i in $(seq 1 64); do yes > /dev/null & done
uptime
(cd Packages/Carpenter && swift test --scratch-path "$SCRATCH" 2>&1 | tail -60)
killall yes
```

The failures of 2026-11-04 were at a load average of 400 to 1,000 (`docs/testing.md:71-72`). If 64
does not reproduce a wait running out, say "not reproduced at load N" in the report. Do not claim
the change fixed a failure that was not seen.

**7.2 While working.** The suites that wait:

```bash
cd Packages/Carpenter
names=$(grep -lE 'settleDeviceSync|approveNewDevice|eventually' Tests/CarpenterKitTests/*.swift \
  | xargs grep -hoE '^(struct|final class|class) [A-Za-z]+Tests' | awk '{print $NF}' | sort -u | paste -sd'|' -)
swift test --scratch-path "$SCRATCH" --filter "\.($names|SendRaceTests|ReplicaRaceTests)/"
```

Then ten runs each, alone, of the tests whose loop changed form: `DeletingARoomTests`,
`WhatRemovingADeviceCutsOffTests`, `WhoCanTellYouWhereToReadSomebodyTests`,
`ChangingYourHiddenAddressTests`, `SiblingMailTests`, `EntrySyncTests`, `AppSessionTests`,
`DeviceEnrolmentTests`.

**7.3 Checks that print nothing when done.**

```bash
grep -rnE 'TestDeadline|deadline' Packages/Carpenter/Tests Packages/Carpenter/Sources/CarpenterKitTesting
grep -rn 'Date() <' Packages/Carpenter/Tests
cd Packages/Carpenter/Tests/CarpenterKitTests && for f in $(grep -lE 'settleDeviceSync|approveNewDevice|eventually' *.swift); do
  [ "$(grep -c '@Suite(' $f)" = "$(grep -c '@Suite(.*timeLimit' $f)" ] || echo "$f"; done
git diff --stat -- App
```

The third prints `MailBetweenDevicesIsSealedPerDeviceTests.swift` and nothing else: its first suite
(line 7) does not wait and has no limit. `Eventually.swift`, `SettlingDeviceSync.swift` and
`ApprovingANewDevice.swift` hold no suite and do not print.

`grep -rn 'Task.sleep' Packages/Carpenter/Tests` must print exactly: one line in `Eventually.swift`,
one in `DeletingARoomTests.swift` (the four closing rounds), `PushArrivalsTests.swift:27`,
`TestVideo.swift:83` and `:89`, and, unless 5.12 was done, the four lines of C4.

**7.4 Measure how many looks the slowest wait takes.** Temporarily, and not committed: count the
looks in `eventually`, keep the largest in a `@MainActor var`, and `print("WAIT looks=\(n)")` when
it grows. Run the full suite once quiet and once under the load of 7.1, take the largest number from
each, then remove the counting. If the loaded number is above 240, stop and report it: the cap has
less than ten times the room and Griff should see the number before it is called done.

**7.5 Done.**

- Quiet: `cd Packages/Carpenter && swift test` passes with the same count and the same one known
  issue as the baseline (`docs/pre-testflight.md:36` says 2,170 and one).
- Under the load of 7.1: ten full runs, and in none of them does a test fail on a wait. A failure
  that is a `timing` test's bound is the other inbox item, not this one; list it and go on.
- `./Scripts/lint-branding.sh` passes (the docs change).
- The report says, with numbers: load average of each run, the two numbers from 7.4, and which
  baseline failures are gone. Anything not run is "not verified".

`App/CarpenterTests` and `App/CarpenterUITests` are not changed, so there is nothing to run there.

---

## 8. Docs

Every passage below sits inside a copy marker already at `NEEDS HUMAN REVIEW`, so no status changes
and no new id is needed. Do not reword a marker. Fill in dates and measured numbers; leave out any
number that was not measured.

- `docs/testing.md:264-273` (marker `894dca3c`), "Waiting in a test". Say: a test waits with
  `eventually` in `Eventually.swift`; it looks, runs its step, sleeps 25 ms, up to
  `TestWait.attempts` (2,400) times; that is a minute on a quiet machine and has no clock on a busy
  one; the cap was five seconds until 2026-11-04 and a minute of wall clock until the day of this
  change; the largest number of looks any wait needed, quiet and loaded, from 7.4; the suites that
  wait carry `.timeLimit(.minutes(10))`, which is still wall clock and is what ends a hang. Keep the
  sentence about the slowest test taking five minutes at a load average near 1,000.
- `docs/testing.md:98-99` and `:106-107` (marker `8a4d142d`): the 200 ms sleep in
  `DeletingARoomTests` is gone, so put that sentence in the past with the date; "the device-sync
  deadlines are a minute now" becomes that the waits count attempts.
- `docs/style.md:176-178` (marker `91a604a1`): wait with `eventually`; never compare against a clock
  and never sleep for a fixed time; the cap is `TestWait.attempts`; a suite that waits carries
  `.timeLimit(.minutes(10))`.
- `docs/inbox.md:247-250` (marker `88dfd060`): the title says the relaunch test "waits on a wall
  clock", which stops being true. Reword: it finds out the write landed by rebuilding the session in
  a loop, up to `TestWait.attempts` times; waiting on the write itself is still the simpler fix.
- `docs/inbox.md:500-501` (marker `12295e6f`): "The device-sync deadlines are a minute now" becomes
  that they count attempts and have no deadline. The rest of that entry is about the `timing` tests
  and stays.
- `docs/pre-testflight.md:131-133` has uncommitted edits from somebody else. Do not edit it; tell the
  orchestrator step 11 is done and let it mark the list.

---

## 9. Risks

- **The compiler.** Nothing here was compiled. The likeliest objections: isolation of the two
  closure parameters (fallback in section 4), a leftover `try` in front of a call that no longer
  throws, and `rethrows` with a non-literal closure (the code above passes only closure literals).
  In 5.4 the two closures share `relaunched`, one reading and one writing. They never run at the
  same time, so this should be accepted (inferred). If it is reported as an overlapping access, do
  the reload inside the one condition closure: return true if `arrived(relaunched)`, otherwise
  rebuild, load, and return `arrived(relaunched)`.
- **A broken test under load ends on the time limit, not on its wait.** 2,400 looks at a second or
  more each is longer than ten minutes, so `.timeLimit(.minutes(10))` fires first and the message is
  "time limit exceeded" in place of the test's own. Alone it is still the test's own message after
  about a minute. This is the cost of having no clock in the wait.
- **`settleDeviceSync()` takes five looks where it took four** (5.2). 77 call sites. At most 25 ms
  and one refresh more per call, and never an earlier return.
- **Four rigs settle after the wait and not inside it** (5.9). The plain two-refresh loop is the form
  six other tests use for the same job, so this is expected to hold; it is the change most worth the
  ten runs. Fallback given in 5.9.
- **The 200 ms in `DeletingARoomTests` may have covered more than the publish.** From reading it did
  not. Ten runs alone.
- **`EntrySyncTests` line 102 now fetches where it slept.** Stronger, but a different thing to pass.
- **The number 2,400 is not measured.** 7.4 measures what it has to be larger than.
- **Lines may have moved.** Step 10 of the plan (accessors only tests call) works in the same test
  folder. This work order uses `publishing`, `publishAgain` and `stateOnDisk`, which the app itself
  reads and writes (`APP/AppSession+DeviceSync.swift:318-327`, `APP/AppSession.swift:237-239`), so
  step 10 should not move them; if it has, stop and report.
- **Nothing new can be shown to fail first.** There is no cheap test that proves "no clock ends a
  wait" without waiting a minute. The greps in 7.3 and the loaded runs in 7.5 are the evidence.

---

## 10. Not in this step

- The fifteen `timing` tests keep their wall-clock bounds (`docs/inbox.md:497-503`).
- `eventually` stays silent when it runs out, as every loop does today. Having it record an issue
  with the caller's source location would name the wait that ran out; it would also change what 100
  call sites report. Parked.
- The relaunch test (B2) could wait on the write and relaunch once. A condition that looks right from
  reading is `second.everythingHeldIsOnDisk` (`APP/AppSession+Sync.swift:319`) together with
  `second.stateOnDisk == second.persisted`. Not tried; inferred.
- `settleRegistration(attempts:)` in the app sleeps 300 ms a try. App code, real Keychain, left alone.

---

## 11. Only Griff can decide

1. **The three sentences in section 1.** CLAUDE.md has him confirm them before code.
2. **The cap.** 2,400 looks, 25 ms apart: a minute on a quiet machine, no clock on a busy one. The
   price is the second risk in section 9. Recommended: yes.
3. **`.timeLimit(.minutes(10))` stays as the one wall-clock bound in the package suite.** At a load
   average near 1,000 the slowest test took five of the ten minutes (`docs/testing.md:272-273`), so
   a heavier load could still fail a good test there. Without it a hang holds the run for good.
   Recommended: keep it, and write it down as a limit he agreed to.
4. **The four race tests (5.12).** Wait for the send in place of 30 and 60 ms. Recommended: yes, in
   its own commit.
5. **A lint.** Reject `Date() <`, `deadline` and `TestDeadline` under `Packages/Carpenter/Tests`, so
   the next wait cannot bring a clock back. It would be a new rule with teeth, so it needs his word.
   Recommended: yes, as a follow-up, not in this step.
6. **Loading the machine.** Sections 7.1, 7.4 and 7.5 are seventeen full runs of the package suite,
   fourteen of them beside sixty-four busy processes. That is an hour or more, while other overnight
   work may be building or using the simulators. Say when, or say a lighter check will do.

<!-- COPY END 6b740085 -->
