<!-- COPY BEGIN bcf7d5cc [NEEDS HUMAN REVIEW] -->

# Spec: many-device tests under `swift test`

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../part-b-plan.md).

Written 2026-11-10/11 from the tree at `fe9ec3e` on `overnight-2026-10-31`, rewritten 2026-11-11 after
a review (twelve findings) and two checks the review did not run: whether the fake is still easier
than iCloud anywhere a scenario depends on, and whether the suites will be fast and the same every
run. Nothing was built or run to write it, and nothing under the repository was changed.

What Griff asked for, 2026-11-10: "I think we spend way too much time on sims when we should have a
more standard 'lots of unit tests, many integration tests, some end to end tests' approach as per
what I believe to be best practice." With it he passed on advice to put N clients in one test
process against a fake backend, and to keep a small smoke suite against real CloudKit.

Shorthand: `T/` = `Packages/Carpenter/Tests/CarpenterKitTests/`, `F/` =
`Packages/Carpenter/Sources/CarpenterKitTesting/`, `C/` = `Packages/Carpenter/Sources/CarpenterCloudKit/`,
`K/` = `Packages/Carpenter/Sources/CarpenterKit/`, `A/` = `Packages/Carpenter/Sources/CarpenterApp/Session/`.
"SDK" = the CloudKit headers in Xcode 27.2's `MacOSX27.2.sdk`.

Where facts come from. Code facts carry file:line and were read in the tree, except counts and
timings, which are from `scratchpad/design/tests-research-code.md` ("research-code"). Web facts are
from `scratchpad/design/tests-research-web.md` ("research-web") and carry the URL that file read
them at; no web page was opened for this spec. "Inferred" means reasoned from the code and not run.
"Not verified" means not checked at all.

All names for new functions below are proposals. None is a name Darwin, Foundation or SwiftUI
already has (so no `round`, `sleep`, `fork`, `kill`, `sync`).

**What the builder builds first** is section 6, "First build": the harness, the faults those
scenarios use, and scenarios 1 to 12. Scenarios 13 to 26 are later.

## What this must guarantee

For Griff to confirm before any code (CLAUDE.md, "Before building").

1. A story with four or five people or devices runs under `swift test` on the Mac, with no
   simulator and no account, with no wall-clock wait, and asserts only things that hold whatever
   order the run's random identifiers fall in. Turn order, call points and same-instant order come
   from test arguments and seeds, so a failing case can be run again alone.
2. The backend those stories run on fails in every way `C/` has code for that a scenario depends
   on, and in the ways Apple documents that `C/` has no code for. Where the fake cannot be made to
   fail like iCloud, the gap is named in section 3 next to the live test that holds it.
3. What is left for two Apple Accounts or an iPhone is a named list of three commands, and it holds
   only what the first two cannot reach.

What it has to stand up to: a fake that is easier than iCloud, an order of arrival nobody tried, a
test that passes because of a fixed number of rounds, and a failure that cannot be replayed.

A limit to sentence 1 that cannot be engineered away without app code only tests call: identity
keys, room keys, `RoomID`, `PacketID`, `DeviceID` and share links come from the system's random
source, so any tie the app breaks by comparing two of them (a key's fingerprint, a space's name)
falls differently each run. Section 5 says how scenarios live with that.

---

## 1. The layers

### Today's counts

| Layer | Tests | Share | Runs with |
|---|---|---|---|
| Unit: one type or function (1,314), plus kit code through a fake transport with no session (28) | 1,342 | 58% | `swift test` |
| Integration, in one process: one session (145), a relaunch (57), two or more sessions exchanging through the fakes (626) | 828 | 36% | `swift test` |
| Needs a simulator: app suite 63 (24 no account, 18 one account, 21 two accounts) and 64 UI test methods | 127 | 6% | `xcodebuild test` |

2,297 in all. The package suite is 2,170 tests in 386 suites and took 112 to 133 seconds in seven
runs on 2026-11-10 (research-code, sections 1 and 6).

By count this is already the shape Griff named. Google's first guess is 70/20/10
(https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html) and its book
gives 80/15/5 (https://abseil.io/resources/swe-book/html/ch11.html). The time goes to simulators for
three reasons the counts hide:

- **The middle layer stops at four parties and cannot fail like iCloud.** No test has five; the 27
  that have four are built six different ways (research-code, section 3). The fakes have no
  conflict, no partial write, no stale read, no order but write order, and no failing receipt,
  share or account call (research-code, section 4).
- **Several rig finds needed no iCloud.** One grant per packet, acknowledging before writing, an
  extra space per launch, and block-then-unblock were all found on simulators and needed only a
  script with the right people in it (research-code, section 5).
- **The top layer does not run by itself.** No script in `Scripts/` starts both sides of a
  two-account run; the driver is a scratch file. The three-device walk names devices that no longer
  exist (`docs/simulator-rig.md:53-55`).

### What each layer must prove

| Layer | Must prove | Must not be asked to prove |
|---|---|---|
| Unit | One rule of one type: canonical bytes, a seal, roster replay, span arithmetic, a cost counted by a test. | Anything about two devices. |
| Integration | The guarantee sentences of a feature, for whole `AppSession`s, across people and devices, in more than one order of arrival, against a backend that throws what iCloud throws. This is where "who it must stop" is tried: a removed device, a second account, a device that was offline, a modified app. | That CloudKit does what the fake does. |
| Contract (the fake's own tests) | The fake and iCloud give the same answers to the calls the app relies on. One set of checks, run against both (section 3). | Faults iCloud will not produce on demand. |
| End to end | Only what the rows above cannot reach: CloudKit's own behaviour, code in the app target, and hardware. | Logic above the mailbox. |

### What still needs two Apple Accounts, one account, a simulator or an iPhone

| Needs | What | Why nothing lower can |
|---|---|---|
| Two Apple Accounts | A space shared by one account and accepted by another (`C/CloudKitMailbox+Pairs.swift:83-100`); the named reader and nobody else reading it; taking a reader off and leaving (`:116-148`). | An account cannot take part in its own share (CLAUDE.md). Each pair has its own space since 2026-09-28, so one account can no longer run a round against itself (research-code, "Noticed"). |
| Two Apple Accounts | One whole round between two people: a join, messages in order, receipts emptying the sender's space, a photo, a key change, a removal. | The only run of `CloudKitMailbox` under a real `AppSession` on both sides. |
| Two Apple Accounts | The times and the order iCloud gives records (`C/CloudKitMailbox+Packets.swift:93-95, 100`). | The fake's times are the fake's. |
| One Apple Account | The wire: record types, `scannedFields` coming back, subscriptions, the sibling feed's sealed bytes, a conflict on a reinstalled device, the rule against calling the engine from its callback (`C/CloudKitEntrySync.swift:331-356`), the deathmark's three calls. | Schema and `CKSyncEngine` behaviour. The fake replaces the adapter that holds the callback rule. |
| A simulator, no account | The system keychain (15 tests), the bundle (3), and one walk of the app's own screens under `--mailbox`. | `AppRootView` is not built by `swift test`. Two rig finds were there: `sync()` binding to libc, and the wrong type passed to `invite(joinerCode:)` (research-code, section 5). |
| An iPhone | File protection classes (`FileProtectionTests`, 3), the Secure Enclave half of the lock, a second device of one member through iCloud Keychain, a push arriving and the extension drawing it, VoiceOver order, Focus. | `docs/proofs-a-rig-cannot-run.md:70-85`. |
| A third Apple Account | Nothing new, if Griff agrees: with a space per pair a third person is more pairs, and every pair is two accounts. The five rows at `docs/proofs-a-rig-cannot-run.md:46-52` are covered in process by scenarios 13 and 24 and by `AMadeUpKeyTests` and `PassingOnANewKeyTests`, which exist. What stays unproven is stored times compared across three real accounts. | That page is `RULED` (`:24`); changing its rows is his call (section 8). |

### The end-to-end smoke set: three commands

| # | What | Accounts | Exists | Last measured |
|---|---|---|---|---|
| E1 | `LivePairTests` (`App/CarpenterTests/LivePairTests.swift:66-123`): a share made and accepted each way, 24 entries in order, receipts emptying the space, a photo, closing the pair. The pair half of the mailbox contract (C6 to C11, section 3) runs in the same two-role harness | two | yes; contract new | not run on the current simulators |
| E2 | `LivePairSendTests`: an invitation by code, a Solo from the people list, a key replaced while the other side ran no rounds, a send that collects first, a removal collected | two | yes | 84 and 85 seconds a side, 2026-11-10 (`docs/simulator-rig.md:438-440`) |
| E3 | `CloudKitMailboxTests` 5, `CloudKitSubscriptionTests` 5, `LiveSiblingFeedTests` 6, `LiveDeathmarkTests` 2, plus the own-space half of the contract (C1 to C5) | one | yes; contract new | 38 tests in 79 seconds on one account, 2026-11-04 (`docs/simulator-rig.md:368`); which 38 was not checked |

`Scripts/smoke-two-accounts.sh` runs all three. Two checks stay outside the script because a
person has to do them, and are listed in `docs/pre-testflight.md` already: one walk in the app's
own screens on two accounts (plan item 3, `:113-114`) and the iPhone items (plan items 4 and 13).

When it runs: before a tester build, and when a change touches `C/`, `CloudKit/schema.ckdb`, the
entitlements, the app target's wiring of a round, or the `Mailbox`, `MediaMailbox` or `EntrySync`
protocols. Whether a change above those seams may be called proven without it is Griff's call
(section 8).

`ScannedFieldsTests` (3 tests) compares field lists and needs neither a bundle nor an account
(`App/CarpenterTests/ScannedFieldsTests.swift:1-66`). The package test target already links
`CarpenterCloudKit` (`Packages/Carpenter/Package.swift:61-66`). Moved to `T/`, the `desiredKeys`
trap is held by `swift test`. The fake reads whole records, so no scenario can see that trap.

---

## 2. The harness

### What exists and is reused as it is

| Piece | Where | Used for |
|---|---|---|
| A client with its own keychain, files, media store and clock | `TestSession.make`, `T/TestSession.swift:30-41` | every device; the harness adds no second maker |
| iCloud for everybody: a space per pair, owned by one account, read by the one named reader | `InMemoryMailbox` over `LocalPairStore`, `F/Fakes.swift:134-379`, `K/Platform/LocalPairStore.swift:10-19, 39-51, 103-111` | one per test, made with the gathering's `TestClock`: its default is `SystemClock()` (`F/Fakes.swift:157`) |
| An account per member, so a member's devices share one | `LocalPairStore.account(of:)`, `K/Platform/LocalPairStore.swift:28-30` | no test code needed |
| One member's device sync | `InMemoryEntrySync.Relay`, `F/InMemoryEntrySync.swift:5-116` | one per member with two or more devices |
| A second device, approved the way a real one is | `keychain.sibling()` (`F/Fakes.swift:63-65`), `approveNewDevice` (`T/ApprovingANewDevice.swift:8-32`) | every second device |
| The round the app runs: device sync, then the mailbox | `SyncRound.run`, `A/RootDecisions.swift:54-95`, called at `App/Carpenter/AppRootView+Sync.swift:53-60` | every scripted turn |
| A hook in the middle of a write or a fetch, and a person who cannot be reached or read | `HookedMailbox`, `F/HookedMailbox.swift:16-23` | grown, below |
| A clock, and a seeded generator | `TestClock`, `SeededGenerator`, `F/Fakes.swift:7-39` | time and order |
| What a removed device's keys open | a copy of `session.chains[room]` taken before, and `entry.opened(using:)`, as `T/ARemovedDeviceAndTheOutpostsItReadTests.swift:70, 79` does | every "a copy of the removed device's keys opens nothing" below |

Nothing below goes into `CarpenterKit`, `CarpenterApp`, `CarpenterCloudKit` or the app target.
The one possible exception (F12) has an `F/`-only route, which is the one this spec picks.

**Not reused: `settleDeviceSync()`.** It sleeps 25 ms between looks and stops on a wall-clock
deadline (`T/SettlingDeviceSync.swift:8-10, 17-19`; `T/TestDeadline.swift:6`), so four quiet looks
cost at least 100 ms. A gathering calls it after every turn; a five-device scenario of a few dozen
turns would spend seconds sleeping, times every case of every sweep. See "Waiting" below.

### What is added

**A1. `Gathering` becomes shared.** Today it is private to one file, makes people and rooms by
name, and settles with a fixed four rounds (`T/AMessageReachesEveryoneItIsForTests.swift:14-66`).
It moves to `T/TestGathering.swift` and gains devices. The private copy is deleted and **all four**
of its tests use the shared one (`:72, 101, 129, 147`), because a private type of the same name
would shadow it in that file. Its own commit.

```swift
@MainActor
final class Gathering {
    let cloud: InMemoryMailbox
    subscript(_ device: String) -> AppSession
    func door(_ device: String) -> HookedMailbox
    func id(_ person: String) -> ParticipantID
    func device(_ device: String) -> DeviceID

    static func of(_ people: String...) async throws -> Gathering
    func room(_ name: String, host: String, guests: [String]) async throws -> RoomID
    func secondDevice(_ device: String, of person: String) async throws

    func takeTurns(_ devices: String...) async -> [String: Result<SyncReport, any Error>]
    func mailboxOnly(_ device: String)
    func settle(inOrder devices: [String]? = nil, passes: Int = 12) async throws
    func away(_ devices: String...)
    func back(_ devices: String...)
    func endProcess(of device: String, atCall number: Int) async
    func relaunch(_ device: String) async
    func clock(_ device: String) -> TestClock
    func advance(by interval: TimeInterval)
    func sameRoom(_ room: RoomID, on devices: [String]) throws
    func callsByName(_ device: String) -> [String]
}
```

A device is named by a string: `"Alice"`, `"Alice's tablet"`. The gathering keeps devices in an
array in the order they were made, never a dictionary, and for each the session, its door, its
keychain and its folder, so it can be relaunched from disk. `RoomOfThree` keeps Carol's keychain
and folder for the same reason (`T/TestRoomOfThree.swift:14-15`).

`mailboxOnly(device)` is a device whose turns skip device sync: a modified app run by a thief who
ignores the removal its own member wrote. It is how a removed device is kept "never told" without
the gathering withholding relay records it would really get.

`callsByName(device)` is the door's call list with each peer's `ParticipantID` replaced by the
gathering's name for it ("put Bob", "fetch Carol"). A per-call sweep prints it on failure, because
call number n reaches a different peer in a different run (section 5).

**A2. One door per device.** Today every session in a test is handed the same mailbox object. A
real device has its own `CloudKitMailbox` and its own `PairIndex` (`C/CloudKitMailbox.swift:9-15`).
So each device gets its own `HookedMailbox(inner: cloud)`; the initialiser already takes the shared
one (`F/HookedMailbox.swift:12`). A fault set on a door is that device's connection failing and
nobody else's. `HookedMailbox` gains three things:

- `MediaMailbox`, forwarded to `inner`. It is `Mailbox` only today (`F/HookedMailbox.swift:4`).
- `calls`: the calls this device made to iCloud, in order.
- One gate that every call passes first. It records the call, runs a step registered for that call
  number, and throws what the door was told to throw. `onPut`, `onFetch`, `refuse`, `cannotReach`
  and `cannotCollect` stay, written through the gate, so their 19 call sites (research-code,
  section 2) do not change.

**A3. The relay.** Changes to `F/InMemoryEntrySync.swift`, each a default-off initialiser argument
except the first:

- `members` is an array in the order devices joined. It is a dictionary keyed by a random `UUID`
  today, and `store` iterates it (`:6, :90`), so with three devices the order two of them hear in
  differs between runs.
- `Relay(clock:)`: stamps come from the gathering's iCloud clock, never backwards, the way
  `LocalPairStore.stamp` does (`K/Platform/LocalPairStore.swift:32-35`). Today the relay counts
  from 1,900,000,000 (`:11, :52-56`), three and a half years ahead of the mailbox, so a removal's
  stored time and a packet's stored time cannot be compared in one test.
- `handsOver: .once` (section 3, R2).
- `failNextSend(storing:)` and `failNextRefresh()` (R1, R3).

The gathering makes relays with `announces: false` (`:13-17`), so a device hears from its siblings
when it takes its turn and not inside another device's `send`.

**A4. A copy of a keychain.** `InMemoryKeychainStore.copy()` in `F/` returns a store with the same
device-only items over the same synchronized half. Needed only for an app that ends part-way
(scenarios 8 and 12). Copies of keys for "what a removed device could open" do not need it; they
use `chains[room]`.

**A5. Orders.** `T/TestOrders.swift`: every order of up to four names, the rotations of five, and
seeded shuffles (section 5).

**A6. A tag.** `manyDevices` in `T/Tags.swift`. `Scripts/tests-tagged.py` reads tags from the
source (`:16-17`), so `Scripts/test-tag.sh manyDevices` works with no script change (read, not run).

### Waiting

The only work a turn does not await is what the app starts in tasks nobody holds: publishing to the
relay (`A/AppSession+DeviceSync.swift:316-324`, a `Task` on the main actor) and `revoke`'s publish
(`A/AppSession+Identity.swift:584`). The gathering waits for them by looking, not sleeping: up to
a fixed count of `await Task.yield()` until no session has `publishing` or `publishAgain` set and a
`refreshDeviceSync()` brings nothing new, then fails naming the device still publishing. Inferred,
not run: the publish runs on the main actor and the relay is an actor in-process, so yields are
enough to let it finish. If they are not, the count is raised, never replaced by a sleep. This is
plan step 11 (`docs/pre-testflight.md:131-133`) for the new suites; the old helper is left to that
step.

### How a script says each thing

| The script wants | It writes | What happens |
|---|---|---|
| Five people, nobody met | `Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")` | `TestSession.make`, `load`, `createIdentity` each, a clock each |
| A room | `g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol"])` | `invite` and `redeem` as `join` does (`T/TestJoin.swift:12-13`), each side through its own door, then `settle` |
| A second device | `g.secondDevice("Alice's tablet", of: "Alice")` | `keychain.sibling()`, `syncDevices`, `load`, `approveNewDevice` |
| Rounds in an order | `await g.takeTurns("Carol", "Alice", "Bob")` | for each, `SyncRound.run` with `refreshDeviceSync` (skipped for a `mailboxOnly` device) and `sync(through: door, media: door)`, then the wait above. A turn that throws is reported, not thrown |
| Everything delivered | `try await g.settle()` | passes over everybody who is not away, until iCloud and every relay hold the same records as a pass ago and nobody is publishing. Fails after `passes`, naming the records still changing |
| Somebody whose phone is off | `g.away("Dave")`, later `g.back("Dave")` | `takeTurns` and `settle` skip Dave |
| Somebody's packet is late | `await g.door("Bob").cannotReach(g.id("Alice"))` for one turn | Bob's write to Alice fails, as a real `save` of one record does (`C/CloudKitMailbox+Packets.swift:25`), and goes on Bob's next round. Preferred over `cannotCollect`; see section 3 |
| Somebody with no network | `await g.door("Dave").stopAnswering()` | Dave's rounds run and every call throws |
| A device removed | `try await g["Bob"].revoke(g.device("Bob's tablet"))` | the app's own call (`A/AppSession+Identity.swift:560`), which rotates every room's key (`:594-597`) and the address (`:583`) |
| A person removed | `try await g["Alice"].remove(g.id("Erin"), from: room)` | `A/AppSession+Membership.swift:510` |
| A key changed | a removal, a departure, an admission or a device removal | never `advanceEpoch(of:)` from the script for an honest member: no screen calls it; its callers are `revoke`, the Outpost calls and membership (`A/AppSession+Identity.swift:596`; `A/AppSession+Outpost.swift:363, 465, 476`; `A/AppSession+Membership.swift:473, 565, 646`). A modified app may call it, and scenario 5 does |
| Coming back with a recovery key | a fresh session on a sibling keychain, `restore(fromRecoveryKey:)` | `A/AppSession+Identity.swift:267`, as `T/RestoringFromAKeyTests.swift:22` does |
| An app that ends | `g.endProcess(of: "Carol", atCall: n)`, a turn, `g.relaunch("Carol")` | at Carol's nth call her folder and keychain are copied and her door stops answering; `relaunch` builds a session from the copy |
| A device's clock is wrong | `g.clock("Dave").advance(by: -3600)`; `g.advance(by:)` moves every clock and iCloud's | each device has its own `TestClock`, and iCloud has one |
| The same thing on every phone | `try g.sameRoom(room, on: [...])` | compares members, **the key each device writes under** (`writingKey(of:)?.secret.fingerprint`, `A/AppSession+Peers.swift:198`), and the messages by author, text and order. A number is not a key: a device can hold several trusted keys for one number and writes under the one with the lowest fingerprint (`A/AppSession+Peers.swift:268-283`) |

**Why `settle` reads iCloud and not the report.** The report a round returns stops before the
repairs that round runs (`docs/testing.md:314-316`). What iCloud holds is in `storedRecords`
(`F/Fakes.swift:189-191`). Not checked: whether an idle round writes nothing. If one does, `settle`
says so on its first use, and that is a finding about the round.

**`join`, `RoomOfThree` and the six ways of making a fourth person stay.** A file moves onto the
gathering when it is next touched, in its own commit.

**Optional, decided by a measurement: a copy of the whole gathering.** If building five people
costs more than about half a second alone, add `g.copyOfEverything()` (every folder and keychain,
the cloud's store, a struct at `K/Platform/LocalPairStore.swift:3`, and the relays, with fresh
sessions loaded). Measure first (section 6, step 0).

---

## 3. Faults the fake must throw, and whether the fake fails the way iCloud does

Two facts frame this (research-code, section 4; both re-read).

- **Above the mailbox every thrown error is one case.** A person whose collect throws is skipped
  this round and the first error is kept (`A/AppSession+Sync.swift:29-35`). Only a `MailboxFailure`
  reaches the member (`:141-147`).
- **Nothing in the app reads a retry-after.** `retryAfter` appears nowhere under
  `Packages/Carpenter/Sources` or `App/` (grep), and the throttle codes are named once, in the
  account check (`C/CloudKitEntrySync.swift:236`).

### The mailbox

The last column is the check the review asked for: whether the fake's version fails the way the
real code fails.

| # | What iCloud does | Where `C/` meets it | Added to the fake | Fails like the real one? | Used by |
|---|---|---|---|---|---|
| F1 | One write fails: no network, zone busy, unavailable | `put` saves one record (`C/CloudKitMailbox+Packets.swift:25`); `save` throws (`C/CloudKitMailbox.swift:110-117`) | `door.fail(_ call:, times:, with:)` for any call; `cannotReach(peer)` exists | **Yes for writes.** A write is one record per call, so one person's write failing alone is a real shape | 1, 3, 4, 6, 7, 10 |
| F1r | A read fails | Every `fetch` and `sentPackets` first runs `refresh`, which reads **every** changed zone of both databases and throws if any read throws (`C/CloudKitMailbox.swift:40-50, 84-99`); a failed load does not mark the index fresh (`:172-180`) | `door.fail(.fetch, …)` fails every fetch that turn | **Only if it fails all of them.** `cannotCollect(from: Bob)` alone, Bob unreadable while Carol reads fine in the same turn, is not a shape the real mailbox produces from a failure. It is kept for the 19 existing call sites; new scenarios say "late" with F1 on the writer instead | 3, 11 |
| F2 | A throttle starts part-way through a round and lasts. `serviceUnavailable` or `requestRateLimited` with a retry-after; an early retry fails again (https://developer.apple.com/tutorials/data/documentation/technotes/tn3162-understanding-cloudkit-throttles.json) | Not handled (`CloudKitEntrySync.swift:236-238`) | `door.stopAnswering(after: n)` and `relent()` | Yes: every call after n throws, as F1 and F1r | 11 |
| F3 | No room in iCloud: every save is refused | `refusal(for:)`, `C/CloudKitMailbox.swift:17-31`, thrown at `:115` | `refuse` covers every save: packets, receipts, rings, uploads, new spaces. Today it stops `put` only (`F/HookedMailbox.swift:26`) | Yes for saves. Whether iCloud refuses a **delete** over quota is not verified; the scenario runs once with withdrawals allowed and once refused | 17 |
| F4 | Signed out. A write gives `.notSignedIn`; a read throws the raw error | `C/CloudKitMailbox.swift:21, 25-27`; reads unmapped at `:41-46` | `refuse(.notSignedIn)` also fails reads with a plain error | Yes | 17 |
| F5 | Some zones of one write succeed. Zones are atomic one at a time (SDK `CKModifyRecordsOperation.h:104-106`) | A photo's copies are one record per person's zone (`C/CloudKitMailbox+Attachments.swift:15-31`); `save` throws on the first failed record (`C/CloudKitMailbox.swift:113`) before `index.wrote` runs | `door.landCopies(_ count:)`: uploads that many copies, then throws | Yes | 21 |
| F6 | The write lands and the answer is lost (https://developer.apple.com/tutorials/data/documentation/cloudkit/ckerror/code/serverresponselost.json) | Not handled; thrown | `door.fail(call, landing: true)` | Yes | 20 |
| F7 | One record in a zone read fails and is skipped without a word | `try? result.get()`, `C/CloudKitMailbox.swift:91` | `door.skip(_ packet:)` for one `fetch` | Yes | 9, 24 |
| F8 | Records stored in the same instant come back in name order, and a packet's name is a random `UUID` | Sorted by first-stored time, then name (`C/CloudKitMailbox+Packets.swift:93-95`) | `cloud.sameInstant(within:seed:)`: records stored within the window come back in an order drawn from the seed, **not** from their names, because the names are random per run | Yes, and replayable. Premise not verified: that the server gives two records in one zone the same creation date | 9 |
| F9 | A read up to two seconds old: a refresh within two seconds of the last returns the cached index | `Date()` in `C/CloudKitMailbox.swift:174`; only `join` clears it (`C/CloudKitMailbox+Pairs.swift:98`) | `door.holdView()` / `door.refreshView()`: reads come from a copy of the store taken at the hold | Easier in one way: a held view still shows what a sibling wrote into the member's own spaces | 2, 10 |
| F10 | Link not ready (`.notYetNamed`); accepting throws; reader's account not found (`unknownPeer`); share with no URL (`.unavailable`) | `C/CloudKitMailbox+Pairs.swift:20, 30, 85-89, 95-97, 222-243` | `door.answerJoin(.notYetNamed, times:)`; F1 on `join` and `space` | Yes | 13 |
| F11 | Saving a share compares change tags whatever policy is asked (SDK `CKModifyRecordsOperation.h:20`) | `name` and `stopSharing` handle no conflict (`C/CloudKitMailbox+Pairs.swift:116-127, 205-219`). Inferred | F1 on `space` or `stopSharing` | The retry half only; the collision itself needs two real devices of one member | 19 |
| F12 | A packet's stored time is the record's **modification** date | `packet.storedAt = cached.modified`, `C/CloudKitMailbox+Packets.swift:100` | `InMemoryMailbox.fetch` restamps each packet from the record's last-stored time, inside `F/` | **No, today**: the fake reports the first-stored time (`K/Platform/LocalPairStore.swift:246`), so a packet a removed device rewrote is dated before the removal on the fake and after it on iCloud. Must be fixed before scenario 5 | 5 |

Left alone: receipts swept at once where the real one waits `sweepAge` by wall clock
(`C/CloudKitMailbox+Packets.swift:111-124` against `K/Platform/LocalPairStore.swift:233-240`); the
fake is harsher. Change tokens: an expired one is not handled in `C/` either.

**F12, the route.** `K/Platform/LocalPairStore.swift` ships in `CarpenterKit` and is called only by
the two fakes and `FileMailbox`, which is in `F/` (research-code, "Noticed"; `F/FileMailbox.swift:53`).
Changing its line 246 is changing app-module code only tests call. The restamp in
`InMemoryMailbox.fetch` stays in `F/`. `FileMailbox` keeps the old dating, which is section 9, item 6.

**Not modelled: a space made twice.** Two devices of one member can each make a space for the same
new person; on the next refresh every device keeps the lowest-named one and deletes the rest,
whatever they hold (`C/CloudKitMailbox.swift:102-108, 199-204`). The lowest name is a random share
link, so which space survives is a coin flip per run on iCloud too. The fake finds or makes in one
step (`K/Platform/LocalPairStore.swift:60-63`). Modelling it needs about ten lines in
`LocalPairStore`, in `CarpenterKit`. Section 9, item 3.

### Device sync

| # | What iCloud does | Where `C/` meets it | Added to the fake | Fails like the real one? | Used by |
|---|---|---|---|---|---|
| R1 | A send fails | `sendChanges` throws (`C/CloudKitEntrySync.swift:162-167`); the session logs it and does not commit its plan (`A/AppSession+DeviceSync.swift:403-410`) | `failNextSend(storing:)` | Whole failure, yes. Whether per-record failures are thrown by `sendChanges` or only reported in an event is not verified | 3 |
| R2 | A fetch hands over what changed since the last one (SDK `CKSyncEngineState.h:19`; `CKSyncEngineEvent.h:154`) | State restored at `C/CloudKitEntrySync.swift:58-63`, saved at `:281-283`, fetch at `:187` | `Relay(handsOver: .once)`, remembered per device name so a relaunch does not reset it | **No, today**: the fake hands every record over on every refresh (`F/InMemoryEntrySync.swift:106-115, 156-160`). A session keeps nothing from a record it could not use (`A/AppSession+DeviceSync.swift:55-60, 104-108`), so the fake retries for it and the engine does not | 3, 7 |
| R3 | A fetch fails | thrown at `:187`, logged (`A/AppSession+DeviceSync.swift:285-293`) | `failNextRefresh()` | Yes | 3 |
| R4 | Arrival in any order | whatever the engine gives | join order by default, seeded on request | Yes | 6, 18 |
| R5 | iCloud's clock | `creationDate`, `modificationDate` (`C/CloudKitEntrySync.swift:305-310, 338-341`) | `Relay(clock:)` | **No, today** (a separate counter); yes after A3 | 5, 6 |

**What the relay cannot be made to do.** The conflict retry (`C/CloudKitEntrySync.swift:164-167,
317-329`) and the rule against calling the engine from its callback (`:331-356`) live in the adapter
the fake replaces. They stay with `LiveSiblingFeedTests` (E3). Real `start` has no path that throws
(`:54-88`). The engine is configured not to sync on its own (`:65`), so a round is the only time it
fetches, as on the fake.

**No push.** A ring is recorded and wakes nobody (`F/Fakes.swift:151, 267-270`). `Ring.reached`
names the accounts that could have been pushed (`:135-139`).

### Real failures from CLAUDE.md that these suites still cannot catch

Plainly, so nobody reads a green many-device run as covering them:

- A field left off `scannedFields`: the fake reads whole records. Held only by `ScannedFieldsTests`
  and E3.
- Calling `CKSyncEngine` from inside its callback: the adapter is replaced. Held only by E3.
- Writing to CloudKit unsealed: caught in process only where a test reads the bytes the fake
  stored; the relay stores `Data`, the mailbox stores wire fields. `encryptedValues` and Advanced
  Data Protection behaviour: live only.
- CloudKit keeping a record's `creationDate` through a rewrite. F12, the authority records and
  `WritingOldDatesIntoICloudTests` all assume it from CLAUDE.md; nothing in process can check it.
- Same-instant order on the server (F8's premise) and the two-second index's real timing.
- A whole refresh failing because one zone's read fails, for example a share the other person
  deleted between listing and reading. Inferred from `C/CloudKitMailbox.swift:40-50, 84-99`; the
  fake has no zone that can fail alone. F1r on every fetch is the nearest shape.
- Throttle timing and retry-after, push and the notification extension, the App Group's second
  process, iCloud Keychain hand-off and Octagon, the software keyboard, `#if DEBUG` leaks, and
  anything in the app target, such as a method binding to a libc name or `media: cloud` at
  `App/Carpenter/AppRootView+Sync.swift:60`.

### How the fake stays honest

`RULED 2026-09-13 by Griff`: "we need the fake to be as hard as the real thing" (`docs/decisions.md:6223-6226`).
A fake "must have its own tests", run "against both the real implementation and the fake"
(https://abseil.io/resources/swe-book/html/ch13.html).

1. **A rule both must obey lives once, in the kit.** `MailboxRules` already holds the record
   ceiling and the sweep age (`K/Platform/Mailbox.swift:64-78`). A later candidate, Griff's call
   because it edits `C/`: the order rule at `C/CloudKitMailbox+Packets.swift:93-95`.
2. **The pure parts of the adapter are tested without an account.** `AccountCheckErrorTests`,
   `MailboxRefusalTests`, `CloudKitPacketRecordTests` exist; add `ScannedFieldsTests`.
3. **One contract, run against both.** Below.
4. **Every fault names its line and its source.** The tables above. A fault iCloud cannot be made
   to produce rests on Apple's page: "Some errors cannot be verified by a contract test"
   (https://pythonspeed.com/articles/verified-fakes/).
5. **Every fault is seen to fire.** `T/TheDoorDoesWhatItWasToldTests.swift`: each fault call fires
   once, on the door it was set on. A fault that does not fire is a test that cannot fail.

### The contract: one set of tests against both

It lives in `F/MailboxContract.swift`, in `CarpenterKitTesting`, which both the package tests and
the app's test target already link (`App/Carpenter.xcodeproj/project.pbxproj:274-279`). A check
throws an error that names the rule it broke, so the library does not need `Testing`. Each check
takes the mailbox and a closure to run after a write; on the fake it does nothing, on iCloud it
waits out the two-second index.

Own space, one account (part of E3). Run by `TheFakeIsNoEasierTests` against `InMemoryMailbox` and
by `CloudKitMailboxTests` against `CloudKitMailbox`:

| # | Rule |
|---|---|
| C1 | A packet put is listed by `sentPackets` with the same recipients and digest. |
| C2 | A packet over the ceiling is refused before anything is stored; one at the budget is accepted. (Exists on both sides: `T/TheFakeIsNoEasierTests.swift:16, 38`; `App/CarpenterTests/CloudKitMailboxTests.swift:114`.) |
| C3 | `withdraw` takes it out of `sentPackets`. |
| C4 | Asking twice for a person's space gives the same link. A space for a code is new each time, and `claim` makes it that person's. |
| C5 | A photo is one copy per person; `storedCopies` names who each is for; a rewrite keeps the first-stored time (`T/TheFakeIsNoEasierTests.swift:51`). |

A pair, two accounts (part of E1). Steps for two roles, values passed on a board. In `swift test`
one driver runs every step against one `InMemoryMailbox`; on the rig each side runs its own steps
and the board is the folder `LivePair` already uses (`App/CarpenterTests/LivePairTests.swift:17-32`):

| # | Rule |
|---|---|
| C6 | `join` says `.notYetNamed` before the reader is named and `.joined` after. One's own link, or a link from the wrong account, is `.gone`. |
| C7 | A packet A puts for B comes back to B with the same bytes, `from` A, and a stored time equal to when iCloud last stored it (F12). |
| C8 | Packets come back in the order first stored. |
| C9 | After B acknowledges, A's `sentPackets` shows the receipt and when it was stored, and B's next fetch carries it. |
| C10 | A ring is not returned by `fetch`. |
| C11 | After `stopSharing`, `leave` or `close`, `reads` is false and `fetch` returns nothing. |

---

## 4. The scenarios

Cast: Alice, Bob, Carol, Dave, Erin. A second device is "Bob's tablet". Every scenario ends with
`settle` and asserts on every device named. "Same room" means `sameRoom`: the same members, the same
key written under, the same messages in the same order. "A copy of X's keys" means `chains[room]`
copied from X's session at the point named, checked with `entry.opened(using:)` on every entry
written after the settle.

Each is watched failing before it is trusted (`docs/style.md`, "Tests"): either it fails today and
goes to Griff, or a deliberate local break, named under the scenario, makes it fail. A scenario
whose break does not make it fail is cut.

Where a scenario is expected to fail on today's code, it is written with `withKnownIssue` and the
case goes to Griff as a question with a recommendation (section 9). It never becomes a "known
limit" in a doc (CLAUDE.md, "Before building", rule 2).

### First build: scenarios 1 to 12

Chosen because reading the code says each is likely to find a real fault, or because it is the
only test of a rule that has broken before on the rig.

**1. A room's new key, passed on by a friend before the device removal that caused it reaches
anyone, does not open on the removed device; and a friend a round behind on a member's new phone
still gets the key to that phone.**
- Devices: Alice; Bob's phone and tablet; Carol; Dave. One room, Lanterns.
- Script, first half: Bob's tablet is `mailboxOnly` (a thief's modified app). A copy of the
  tablet's keys is taken. Bob's phone removes the tablet and takes a turn. Carol takes a turn and
  passes Bob's new key on. Alice's turn: Bob's write to her failed once (F1 on Bob's door), so she
  collects from Carol and not from Bob; she now holds the new key and still lists two devices for
  Bob, and in the same turn passes the key on to Bob. The tablet takes a turn. Settle. Alice,
  Carol and Dave each send.
- Script, second half: Bob replaces his phone (a new device approved by the old, then the old
  removed) while Alice is away. Alice comes back and takes one turn before she hears; then settle.
  Alice sends.
- At the end: Alice, Carol, Dave and Bob's phone same room, writing under the key Bob's phone made
  at the removal. None of the three messages opens on the tablet or with the copy; all open on
  Bob's phone. After the second half, Alice lists one device for Bob and her message opens on his
  new phone.
- Faults F1. Orders: which of Alice, Carol and Dave is late from Bob (three cases); the second half
  once.
- Why: revocations travel only in their own member's packets (`A/AppSession+Sync.swift:136`;
  `A/AppSession+Authority.swift:39-50`). Every holder passes a new key on to every member, sealed to
  the devices its own phone lists (`A/AppSession+Peers.swift:146-160, 302-308`), and the check
  before passing on is about room entries the maker had seen (`:189-196`), which a device removal is
  not. Inferred, not run: the first half fails. Whether Bob's changed address alone keeps Alice's
  packet from the tablet was not traced. The second half rests on the receipt naming the devices
  (`:310-319`), so a grant to new devices is owed again; no test holds that.
- From: review finding 1; `T/WhatRemovingADeviceCutsOffTests.swift:62, 86` have one friend, who
  has already heard.

**2. A member's second device that sends before device sync has told it what the first device
collected does not write under the key a removed member holds.**
- Devices: Alice; Bob's phone and tablet; Carol; Erin. One room.
- Script: Alice removes Erin and takes a turn. Bob's phone takes a turn: it collects the removal
  and the new key and signs for the packets. Bob's tablet, which has run no device sync since, calls
  `send(_:to:after:)`. Settle.
- At the end: the tablet's message does not open with a copy of Erin's keys taken before her
  removal, no packet for Erin was written by the tablet, and Alice, Carol and both of Bob's devices
  same room with the message.
- No fault. One case.
- Why: the read before a send is a mailbox round only (`A/AppSession+Messaging.swift:36-38, 48-58`).
  It skips every packet a sibling signed for (`A/AppSession+Sync.swift:196, 468-478`), and nothing on
  the send path refreshes device sync (`App/Carpenter/AppRootView+Ready.swift:135`). Inferred, not
  run: it fails, against the ruling of 2026-11-10 (`docs/decisions.md:1500-1510`). `withKnownIssue`
  and section 9, item 1.

**3. A room's key changes twice while Dave is away, and his first message back is sealed under the
newest.**
- Devices: Alice; Bob's phone and tablet; Carol; Dave; Erin.
- Script: Dave away. Alice removes Erin. Alice and Bob send. Bob's phone removes his tablet (a copy
  of the tablet's keys taken first). Carol sends. The first sibling `send` on Bob's account fails
  once (R1) and the first relay refresh of Bob's phone fails once (R3); the relay hands over once
  (R2). Dave back; in his first turn one of Alice, Bob and Carol cannot reach him (F1 on their door),
  so a later key can reach him before an earlier one. Dave sends with `send(_:to:after:)`.
- At the end: Alice, Bob's phone, Carol and Dave same room with every message. Dave's message opens
  on Bob's phone and not with the tablet copy, and Dave lists one device for Bob. Erin's phone shows
  nothing sent after her removal, holds neither new key, and shows she was removed.
- Faults F1, R1, R2, R3. Orders: which of the three is late (three cases).
- Break: skip the device removal's rotation of the room key in `revoke` (`A/AppSession+Identity.swift:594-597`); Dave's message then opens with the tablet copy.
- From: CLAUDE.md, "A removed member still holds the old key"; review finding 4.

**4. A friend away longer than a packet waits still gets the new key when he comes back, with
nobody relaunching and with somebody relaunching.**
- People: all five, one room.
- Script: Dave away. Alice removes Erin, so the new key is in packets for Dave from Alice, Bob and
  Carol. `g.advance(by: SyncSession.packetWaitsFor + 3600)` with turns for everybody present, so all
  three withdraw those packets. Case two relaunches Alice before Dave returns. Dave back. Alice
  sends; Dave sends.
- At the end: Dave opens Alice's message, Dave writes under the same key as Alice, and Alice, Bob,
  Carol and Dave same room.
- No fault. Two cases.
- Why: a packet waits nine days (`K/Sync/SyncSession.swift:205`); an expired one is withdrawn
  (`A/AppSession+Sync.swift:583-592`). The mark that a key was handed out is cleared only for packets
  altered or vanished (`:608, :621`) and otherwise lives in memory until the app restarts
  (`A/AppSession.swift:195`). Inferred, not run: case one fails. `withKnownIssue` and section 9,
  item 4. `T/ChangingYourHiddenAddressTests.swift:143` has a friend away ten days and never asks
  about the key.
- From: review finding 6.

**5. A phone Alice removed, still signed in to her iCloud and running a modified app, writes a
message, a key of its own, an approval dated last week and a new body under an old packet's name,
and none of it counts anywhere, in either order of hearing.**
- Devices: Alice's phone, tablet and old phone; Bob; Carol.
- Script: the old phone is `mailboxOnly` and away; a copy of its keys is taken. Alice's phone
  removes it. The old phone, never told, sends, calls `advanceEpoch` (a modified app can), writes an
  approval with an early date as `T/WritingOldDatesTests.swift:236-262` does (per research-code),
  and an old packet in Alice's space for Bob is rewritten with `tamper(packet:)`
  (`F/Fakes.swift:339-341`). Bob and Carol each collect the old phone's writes before or after they
  hear of the removal. Settle. Bob, Carol, Alice's phone and her tablet each send.
- At the end: those four same room, writing under the key Alice's phone made at the removal,
  without the old phone's message. Each lists two devices for Alice. None of the four messages opens
  on the old phone or with the copy. The old phone, then given a full turn, erases itself.
- Faults F12 (required), R2, R5. Orders: two by two (four cases), each run **ten times** with the
  run's key fingerprints printed, because whether the old phone's key or Alice's sorts lower is
  random per run (section 5).
- Why: a friend who has not heard of a removal takes a key the removed device signs
  (`docs/crypto-brief.md:475-477`; the check is once, at adoption, `A/AppSession+Peers.swift:380-387`),
  and among keys of one number the lowest fingerprint is written under (`:268-283`). Inferred from
  `:285-300`, not run: if the old phone's key arrived first and sorts lower, Bob writes under it.
  `T/ForgingAKeyTests.swift:75` covers only a friend who had heard (`:113`).
- From: CLAUDE.md, "The identity proves the person, never the device", "A date a device writes is
  not an order"; review finding 3.

**6. Two of Alice's devices remove each other at once, and her laptop, Bob, Carol and Dave, who was
away through both, all keep the same one.**
- Devices: Alice's phone, tablet and laptop; Bob; Carol; Dave.
- Script: Dave away. The tablet's clock is set back an hour. The phone removes the tablet; the
  gathering waits for its publish to reach the relay; then the tablet removes the phone. So the
  relay stores the phone's first, scripted, not left to the unawaited publish
  (`A/AppSession+Identity.swift:584`). The phone's first write to Dave fails (F1); by its next turn
  it has heard the tablet's removal, so Dave's first packet from Alice carries both. Dave back.
- At the end: the laptop, Bob, Carol and Dave name the same surviving device, the phone. The tablet
  has erased itself. The phone sends and all read it.
- Faults R4, R5, F1. Orders: which removal is stored first (two cases; the clock is set back on the
  loser).
- Why: a member's own devices time a removal by the relay record's created time
  (`A/AppSession+Authority.swift:52-65`); a friend times it by the stored time of the packet that
  carried it (`K/Sync/SyncSession.swift:528-530`), and a packet carries every removal its writer
  knows (`A/AppSession+Authority.swift:39-45`; `K/Crypto/DeviceRegistry.swift:148-158`). Two
  removals in one packet share a stored time, and the registry then orders them by the dates the
  devices wrote (`K/Crypto/DeviceRegistry.swift:366-374, 443-448`). Inferred, not run: Dave counts
  the tablet. `withKnownIssue` if so, and section 9, item 5.
- From: `docs/decisions.md:1311`; review finding 5.

**7. A tablet whose disk refused its sibling's mail and then restarted still ends up with it.**
- Devices: Bob's phone and tablet; Alice.
- Script: as `T/NothingGoesOutThatIsNotOnDiskTests.swift:347-378` up to the refused write. Then the
  tablet's app ends before the disk recovers, and it is relaunched with the relay remembering what
  it already handed over (R2).
- At the end: the tablet shows the message. The phone's cursor for the tablet has moved.
- Fault R2. Not known whether it passes today; if not, `withKnownIssue` and section 9, item 2.

**8. Alice's app ends between writing a removal and handing out the new key; reopened, everybody
who stays gets the key and Erin never does; and with no relaunch, a failed write is still owed.**
- People: all five.
- Script, case A: Alice removes Erin. Her next turn ends at call n. Relaunch. Alice sends.
- Script, case B, no relaunch: Alice removes Erin; her door fails at call n and relents; one more
  turn for Alice.
- At the end: Bob, Carol and Dave each hold the new key and read Alice's message. Erin holds no key
  after the old one and is told once. Alice shows nothing unsent.
- Fault: the app ends (A), F1 (B). One case per call of that turn, for each.
- Why case B: the mark that a key was handed out lives in memory (`A/AppSession.swift:195`), so a
  relaunch clears it whatever the code did; only case B can catch "mark every owed key when any
  packet lands" (`A/AppSession+Sync.swift:150-153`). `T/PacketCapTests.swift:90` holds it only while
  keys ride in the first packet.
- From: review finding 11.

**9. A burst stored in one instant comes back in any order with nothing missing, and a wish
changed twice in that instant ends as the later one.**
- People: all five; Erin away.
- Script: Alice sends 120 long messages, as `T/AMessageReachesEveryoneItIsForTests.swift:105` does,
  and takes one turn, so several packets are stored without the clock moving. Alice calls
  `setNotified(true, about: Erin)` (`A/AppSession+Outpost.swift:275`) and takes a turn, then `setNotified(false, about: Erin)` and takes
  a turn, the clock still. Erin back; one record skipped in her first read (F7).
  `g.advance(by: AppSession.holeSettlingDelay + 1)` and one more settle.
- At the end: Erin and Alice same room. Erin's `missingHistory` is empty and no repair started.
  `Erin.wantsOutpostBellFrom(Alice)` is false on every seed.
- Faults F8, F7. Orders: twenty seeds.
- Why: messages merge the same in any order (`ConvergenceTests` runs twenty seeds). What depends on
  order is the wish list, taken whole from each packet, last read wins (`K/Sync/SyncSession.swift:509`;
  `A/AppSession+Sync.swift:241-251`), and sent again only when it changes (`:131`). An automatic
  repair starts only after a hole has sat 120 seconds of the test clock
  (`A/AppSession+HistoryRepair.swift:94, 117`). Inferred: the wish assertion fails on some seeds,
  on iCloud as well if two records can share a creation date. `withKnownIssue` if so.
- From: CLAUDE.md, "Iterating a dictionary is not an order, and the fake had one"; review finding 9.

**10. A message sent within two seconds of a round still waits for a removal stored in between.**
- People: Alice, Bob, Carol.
- Script: Bob takes a turn and his door holds its view (F9). Alice removes Bob and takes a turn. Bob
  calls `send(_:to:after:)`.
- At the end, by `docs/decisions.md:1506-1509`: Bob writes nothing and is told he was removed.
- Fault F9. Read, not run: the read before a send goes through the same cached index
  (`A/AppSession+Messaging.swift:48-51`, `C/CloudKitMailbox+Packets.swift:32`,
  `C/CloudKitMailbox.swift:174`), so it is expected to fail. `withKnownIssue`; section 9, item 1.

**11. A round cut off by a throttle after any number of calls loses nothing and repeats nothing;
and a message sent at any point of a round is on every phone once.**
- People: all five.
- Script, sweep A: Alice has just let Erin in, so keys are owed, and everybody has a message
  unsent. Carol's door stops answering after call n. The others take turns. `relent`.
- Script, sweep B: Bob calls `send` at call n of his own turn (`door.before(call: n)`).
- At the end, on all five: same room, each message once. Erin holds the key. No packet without a
  receipt. Carol's `cannotSend` is nil. In B, nothing that arrived in Bob's turn is missing.
- Fault F2. One case per call of the turn, for each sweep, printed by `callsByName` on failure.
- From: CLAUDE.md, "Never copy main-actor state across an `await`" and the grants trap;
  `T/ReplicaRaceTests.swift:51` and `T/SendRaceTests.swift:31` each try one point on one device.

**12. Carol's app ends at each call of a round in turn; reopened, she has every message, and
nothing she acknowledged is missing from her disk.**
- People: Alice, Bob, Carol, Dave.
- Script: Alice, Bob and Dave send. Carol's turn ends at call n. Relaunch.
- At the end: Carol and Alice same room. On the copy made at call n: every packet that has Carol's
  receipt in iCloud carried only entries that a session loaded from that copy holds.
- Fault: the app ends. One case per call.
- Break: move the acknowledgement above `writeDownOrReport` (`A/AppSession+Sync.swift:266-279`).
- From: CLAUDE.md, "An acknowledgement is a promise that the entry is on disk" (rig, 2026-09-09).

### Later: scenarios 13 to 26

Built after the first twelve pass or are reported, in this order.

**13. Five people join one at a time; the "not yet named" answers and relaunches make no extra
space.** All five. Alice makes Lanterns and invites Bob; Bob invites Carol; Carol invites Dave;
Alice invites Erin, whose first two `join` answers are `.notYetNamed` (F10,
`A/AppSession+Pairs.swift:136-141`). Carol is relaunched twice. End: same room on all five;
`spaceCount(of:)` for Carol unchanged across both relaunches; each space one reader
(`F/Fakes.swift:205-211`). Orders: five rotations. What `T/MembersOverTimeTests.swift:35` and
`T/EachPairHasASpaceOfItsOwnTests.swift:45, 58` already hold is not repeated.

**14. A removal and a message at the same moment.** Erin sends m1; Alice collects it. Erin sends m2
and takes a turn. Alice removes Erin without collecting. Bob, Carol and Dave each collect from Erin
first or Alice first. End: same room, m1 shown and m2 not, `canWrite(in:)` false on Erin. Eight
orders. Break: the date comparison the removal's vector clock replaced. From: `RULED`,
`docs/decisions.md:3974-3980`.

**15. A removed member who invites a second identity of her own gets nobody in.** Alice removes
Erin. Erin invites Eve before she hears, through `invite` (`A/AppSession+Membership.swift:181`).
For "after she hears" the session refuses to write (`A/AppSession.swift:375-379`;
`T/RemovalTests.swift:471`), so a modified app is modelled: Erin's invitation entry is written by
hand and put in iCloud directly, as `T/ForgingAKeyTests.swift:115-127` does for a key. Erin's
packets reach Dave before or after the removal. End: four members, no invitation pending, no key
sealed for Eve in any space Eve reads. Four orders.

**16. Carol comes back with her recovery key while Dave is away.** All five; Bob holds history for
people who come back. Carol's phone is lost; she restores on a new device (`restore(fromRecoveryKey:)`,
`A/AppSession+Identity.swift:267-321`). Alice then removes Erin. Dave back. End: the new phone reads
the next message from each of the others; a copy of the old phone's keys opens nothing written
after the restore; Alice, Bob, Dave and Erin each list one device for Carol. Orders: which
friend her new phone reaches first. Rests on `T/WhoCanSendYouAKeyTests.swift:130` (a first key only
from the inviter) and `T/BeingToldAboutARestoreTests.swift:295, 316`. Review finding 7; it is later
only because the first twelve already hold the removal-plus-new-device shape (scenario 1, second
half), and is the first of the later list.

**17. A member with no room in iCloud reads everything, is told why, and catches up.** Alice, Bob,
Carol, Dave. Dave's door refuses every save (F3). The others send; Dave sends one. Turns. `relent`.
While refused: the three senders' packets stay until Dave has room, their delivery marks do not
move early, Dave's `cannotSend` is `.noRoomInICloud`. End: same room, nothing collected twice. A
second case with F4. What `T/NoRoomToSendTests.swift:36-81` already holds is not repeated.

**18. Two of Alice's devices approve her new laptop at once.** Phone, tablet, laptop; Bob. Both
call `approveDevice` (`A/AppSession+Approval.swift:24`); the first publish is settled before the
second device acts, so the relay order is scripted. End: three devices each listed once on all
four; the laptop opens Bob's next message; `deviceRequests` empty. Two orders.

**19. Two of Alice's devices name Dave the reader of her space for him in one round.** F11 on the
tablet's `space(for:naming:)` once. End: one space for Dave, read by Dave alone; a message each way
on all four.

**20. A write that landed while its answer was lost is not made twice.** F6 on Alice's first
`put`, Bob's `acknowledge`, Alice's `upload`. End: each message and the photo once; every packet in
its sender's `sentPackets`, none left once acknowledged.

**21. A photo whose copies land for two of four and fail for two reaches all four, and no copy
stays.** F5. End: same bytes on four; after `sweepAge` and a settle, `storedCopyCount` is zero.

**22. A friend let into a room and onto an Outpost in one round gets both keys, on both
devices.** Break: forward only the last key to the sibling on the path where a key the collecting
device cannot open is passed on (`A/AppSession+Peers.swift:426-429`). Cut if that break does not
make it fail; the plain-subscript break is already caught by `T/EpochDistributionTests.swift:215`.

**23. A reply, an edit, a reaction and a key that arrive a round before what they depend on all
apply.** Dave away; Alice sends m and edits it; Bob reacts and replies; Carol sends under a key
Alice made. Dave back with Alice's write to him failed once.

**24. A post, a photo and comments reach four readers; a reader turned away reads nothing posted
afterwards.** F7 on Carol's first read; Erin away for `revokeOutpost`. From:
`docs/proofs-a-rig-cannot-run.md:48-49`.

**25. When a reader removes one of his devices, the Outpost's next post does not open on it, with
the owner away.** Alice away when Bob's phone removes his tablet (`mailboxOnly`; a real second
session approved with `approveNewDevice`, not a made-up device as
`T/ARemovedDeviceAndTheOutpostsItReadTests.swift:38` does). Alice back, one turn in which Bob's
write to her fails, then posts; then a turn that reaches Bob, then posts again. End: the second post
does not open on the tablet or with its copy. The first is expected to: a post has no read before it
(`A/AppSession+Messaging.swift:37`, room nil), and the rotation is owed only once Alice collects
from Bob (`A/AppSession+Sync.swift:215-220`). That half is section 9, item 7, not an assertion.

**26. A hole is filled by whoever holds it; blocking among five.** The repair (`forget(packet:)`,
Alice away, `startRepair(in:)`) and the block-then-unblock walk (`docs/simulator-rig.md:396-408`)
from the first draft, unchanged.

Cut from the first draft: "five people away for different stretches" (no assertion named a mistake
and its "no repair" could not fail without moving the clock; scenario 9 now covers both).

### What Griff listed, and where it is

| His list | Scenarios |
|---|---|
| A share made and accepted | 13; contract C6; E1 |
| A key change while one person is offline | 3, 4 |
| "Carol's key changes", read as her identity coming back | 16 |
| Somebody offline who comes back | 3, 4, 6 |
| A removal that races a message | 14, 15 |
| A removed device | 1, 5, 6, 25 |
| One member's two devices sharing an inbox | 2, 7, 22 |
| Packets out of order | 9, 23 |
| A conflicting write | 6, 18, 19 |
| Throttling in the middle of a round | 11 |
| A process that ends between writing and acknowledging | 8, 12 |
| History repair across five | 26 |
| An Outpost with several readers | 24, 25 |

---

## 5. Trying more than one order, the same way every run

No wall clock and no randomness that cannot be replayed, except where the app's own random
identifiers break a tie (below).

1. **The order of turns is an argument.** `@Test(arguments: Orders.every(["Alice", "Bob", "Carol"]))`.
   Each order is its own case and can be run alone. Up to four names is every order (24); five is
   the five rotations, or seeds.
2. **A seed is an argument.** `@Test(arguments: 0..<20)` with `SeededGenerator` (`F/Fakes.swift:25-39`),
   as `ConvergenceTests` does (`T/ConvergenceTests.swift:11-13, 77`, per research-code). The seed
   picks the settle order, the order of same-instant records (F8) and the relay's order (R4). A
   failure prints its seed.
3. **A step at every call in turn.** `door.before(call: n) { … }` generalises `onPut` and `onFetch`
   (`F/HookedMailbox.swift:16-17`). A first run with no fault reads `door.calls.count`; the test then
   runs once for each n. Scenarios 8, 11 and 12. Every session is on the main actor, so another
   device's code runs only while this one is suspended, and the suspensions that matter between
   devices are calls to iCloud.
4. **Who is late.** One writer's put to one reader fails for one turn (F1).
5. **When a sibling hears.** Relays have `announces: false`, so the script decides.

**What still varies between runs, and how the scenarios live with it.** Keys and identifiers come
from the system's random source (`CryptoKit`, `UUID()`, e.g. share links at
`K/Platform/LocalPairStore.swift:55`). So:

- A sweep's call n reaches a different peer in a different run, because the app orders peers by
  identifiers. Every n is tried, so each run covers every point, but a failure at n=7 may be a
  different call next time. On failure the test prints `callsByName`, which names the call.
- Where the app picks between two keys by fingerprint (scenario 5), the case runs ten times and
  prints which key sorted lower. A pass on all ten has both orders with probability 1 − 2⁻⁹. This is
  a coin, not a seed; it is said so in the test's name of the argument.
- No assertion may depend on such a tie unless the scenario is about the tie.
- No dictionary is iterated to decide order anywhere in the harness: devices are an array; the relay
  becomes an array (A3). `InMemoryMailbox.copies(of:)` filters a dictionary (`F/Fakes.swift:169-171`);
  only `tamper` and `change` use it and both act on every copy, so order does not matter there.

Time is `TestClock` only. `SyncRound.run` takes `now:` (`A/RootDecisions.swift:69`) and is given the
device's clock. The mailbox gets the gathering's clock, not its `SystemClock()` default. The only
wait is counted yields (section 2, "Waiting").

What this does not reach: two tasks inside one device that never call iCloud between them
(`ReplicaRaceTests`, `SendRaceTests`, `NothingGoesOutThatIsNotOnDiskTests` hold those); work off the
main actor truly in parallel, which is the sanitizer steps' job.

---

## 6. Files, time, and what to run

### First build

Steps, each its own commit or commits, no cleanup mixed in:

0. **Measure**: a five-person room built on today's helpers, alone, with `--filter`, and one
   `settle` with nothing to do. That number decides `copyOfEverything` and the caps below.
1. **The harness**: A1 (all four tests moved, own commit), A2, A5, A6, the counted-yield wait, and
   `TheDoorDoesWhatItWasToldTests`. Done when the four moved tests pass and every door fault is seen
   to fire.
2. **The faults the first twelve use**: F1, F1r, F2, F7, F8, F9, F12 (the `F/` restamp, with C7
   against the fake); A3 (ordered relay, `clock:`, `handsOver: .once`, `failNextSend`,
   `failNextRefresh`); A4.
3. **Scenarios 1 to 12**, in the order 3, 1, 2, 4, 5, 6, 10, 9, 11, 12, 8, 7. Each is watched failing
   (today, or under its break) before it is kept. Those that fail today get `withKnownIssue` and go to
   Griff; none is "fixed" in this build.

Later: F3 to F6, F10, F11, the contract against both, `ScannedFieldsTests` moved,
`Scripts/smoke-two-accounts.sh`, scenarios 13 to 26, docs.

### Files

| File | Change | When |
|---|---|---|
| `T/TestGathering.swift` | new (A1) | first |
| `T/TestOrders.swift` | new (A5) | first |
| `T/AMessageReachesEveryoneItIsForTests.swift` | its private `Gathering` (`:14-66`) goes; four tests use the shared one. Own commit | first |
| `T/Tags.swift` | `manyDevices` | first |
| `F/HookedMailbox.swift` | `MediaMailbox`, `calls`, the gate, the fault calls | first |
| `F/InMemoryEntrySync.swift` | ordered members, `clock:`, `handsOver:`, `failNextSend`, `failNextRefresh` | first |
| `F/Fakes.swift` | `sameInstant(within:seed:)`; the held-view copy; the F12 restamp in `fetch`; `InMemoryKeychainStore.copy()`. `FailingMailbox` (`:440`, used nowhere) goes, own commit | first |
| `T/TheDoorDoesWhatItWasToldTests.swift` | new | first |
| Seven suites in `T/` for scenarios 1 to 12, named as sentences: `ARemovedDeviceGetsNoKeyThroughAFriendTests` (1), `ASecondDeviceSendsAfterWhatItsMemberCollectedTests` (2), `AwayWhileTheKeyChangesTests` (3, 4), `WhatARemovedDeviceWritesCountsNowhereTests` (5, 6), `ATabletRestartsBeforeItsDiskRecoversTests` (7), `TheOrderThingsArriveInTests` (9, 10), `ARoundCutShortLosesNothingTests` (8, 11, 12) | new, tagged `.sync` or `.membership`, and `.manyDevices` | first |
| `F/MailboxContract.swift`, `T/TheFakeIsNoEasierTests.swift`, `App/CarpenterTests/CloudKitMailboxTests.swift`, `App/CarpenterTests/LivePairContractTests.swift` | the contract | later |
| `T/ScannedFieldsTests.swift` | moved from `App/CarpenterTests/` | later |
| `Scripts/smoke-two-accounts.sh` | E1, E2, E3 in one command | later |
| docs | section 8 | later |

### How long the new suites may take

Not measured; proposals to be replaced by step 0.

- First build, about 150 cases: scenario 1 three, 2 one, 3 three, 4 two, 5 forty, 6 two, 7 one,
  8 two sweeps, 9 twenty, 10 one, 11 two sweeps, 12 one sweep. Sweeps capped at 40 calls each.
- Budget: 40 seconds alone at low load, which keeps the package suite under three minutes (112 to
  133 seconds today; every session test takes its turn on the main actor, `docs/testing.md:74-77`).
- A case over one second alone is looked at before it is kept. The counted-yield wait is what makes
  that possible; with the old 25 ms sleeps a five-device case would not get under a second.
- Each suite carries `.timeLimit(.minutes(10))` like the 33 that wait today (`docs/testing.md:270-271`).
- If the budget does not hold, cut the sweep caps, then seeds, before scenarios.

### What to run

```bash
cd Packages/Carpenter && swift test --filter "<the suite being worked on>"
```

```bash
Scripts/test-tag.sh manyDevices
```

```bash
cd Packages/Carpenter && swift test
```

```bash
./Scripts/lint-branding.sh
```

The first while working; the second for the many-device suites; the third and fourth before a
commit. Later, `Scripts/smoke-two-accounts.sh` before a tester build or after a change to the files
named in section 1. It erases every `Pair-` zone on both accounts (`docs/simulator-rig.md:43-48`),
so it needs Griff's two test accounts and his go-ahead each time the accounts hold anything.

---

## 7. Scripted real-account tests

### What the research verified, and what it did not

All from research-web, section 3. Nothing there was run against a live container.

Read on Apple's pages:

- Every user needs a person to sign in. Web Services tokens last 30 minutes, or two weeks with
  "Keep me signed in", and each is good for one request; a new one comes back in the response
  (https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html).
  A `cktool` user token is made "using an interactive login and cannot be automated"
  (https://developer.apple.com/icloud/cloudkit/automating/; `man cktool`).
- Both name the private and the shared database
  (https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/ModifyRecords.html).
- Accepting a share is documented for Web Services
  (https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/AcceptingShareRecords.html)
  and for CKTool JS (https://developer.apple.com/tutorials/data/documentation/cktooljs/promisesapi/acceptrecord.json).
- Creating a share is documented only in the 2016 Web Services reference, for a share of one
  record. A zone-wide share is not mentioned in it.

Not verified: that either call works from a script today; that either handles a zone-wide share,
which is what this app's spaces are (`C/CloudKitMailbox+Pairs.swift:170, 192`); the claim that an
app-made token is refused for the private database (four developers reported it between 2017 and
2022, three reported web sign-in working, Apple never answered:
https://developer.apple.com/forums/thread/84754; Apple's own article sends such a token to a
`/private/` path:
https://developer.apple.com/tutorials/data/documentation/cloudkit/changing-access-controls-on-user-data.json);
whether a `cktool` token can be had for an account not on the developer team.

### Recommendation: do not build it

- It would not run this app's code. `CloudKitMailbox`, `PairIndex` and `CKSyncEngine` are what has
  failed here, and none of them would be in the run.
- It is not unattended. Five users is five hand sign-ins that last hours.
- What it could do, check records against the fake, the contract does through the app's own
  adapter in the test host that already exists.

Build instead: `Scripts/smoke-two-accounts.sh` and the pair contract (in E1).

For several devices of one account Apple describes several sync engines on one development database
in one process, "to simulate multiple devices syncing back and forth" (SDK
`CKSyncEngineConfiguration.h:41-45`, per research-web; https://github.com/apple/sample-cloudkit-sync-engine).
Whether `LiveSiblingFeedTests` does so was not read.

What would change the recommendation: a fault that needs a third real account. Then a third
simulator on a third account without Advanced Data Protection is the tried route
(`docs/proofs-a-rig-cannot-run.md:58-64`).

---

## 8. What changes in the docs, and one question about a rule

Every chunk of `docs/testing.md` is `NEEDS HUMAN REVIEW`. A reworded chunk stays there; a new one
gets an id from `python3 Scripts/copy-review.py new-id`; a deleted one takes its markers with it.

### `docs/testing.md`

| Lines | Now | Change |
|---|---|---|
| 12-13 | "How four simulators are set up" | two |
| 38-50 | 2,009 tests in 348 suites; "A run on two accounts is the only evidence for anything that crosses the network" | 2,170 in 386; the three layers with what each proves. The sentence about evidence changes only if Griff says yes below |
| new | | "Many devices in one process": the gathering, a door per device, turns, `settle`, the counted wait |
| new | | "Trying more than one order": section 5, including what still varies between runs |
| 322-342 | six rows; `InMemoryMailbox` "is one pool" (`:341-342`) | the fault tables of section 3 with the "fails like the real one" column, the list of what they cannot catch, and the contract |
| 359-380 | says `CloudKitMailboxTests` covers record order | It has five tests and none is about order (`App/CarpenterTests/CloudKitMailboxTests.swift:76-150`); order is held by `LivePairTests.swift:149` and, once built, C8 |
| 386-405 | describes `LiveRig`, `LiveRoundTests`, `LiveOutpostTests` | Delete; gone since bd994f0 (research-code). Name E1 and E2 |
| 409-425 | names `+Share`, `+ReverseChannel`, `+Bell`, `PeerZoneDirectory` | none exists in `C/`; rewrite against the current files |
| new | | "The two-account smoke": E1 to E3, the one command, what it does to an account, when it runs |

### Other docs

- `docs/simulator-rig.md:53-55, 315-339`: once 1, 5, 6, 14 and 15 pass, the three-device removal
  walk has nothing left to show; retiring `Scripts/rig-walk-removals.sh` is Griff's call.
- `docs/proofs-a-rig-cannot-run.md:44-52`: the third-account rows get their in-process status. The
  page is `RULED` (`:24`), so the wording is his.
- `docs/decisions.md`: one `PROPOSED` entry, "Many-device stories run in one process, and the rig is
  a smoke set", with its cost: the fake has to be kept as hard as iCloud, and the contract says
  whether it is.
- `docs/style.md`, "Tests" (`:170`): a story with several people uses the gathering; an order or a
  seed is a test argument; no sleeps.
- `docs/open-questions.md`: each item of section 9 that Griff has not answered.
- `docs/roadmap.md` and `docs/epics/foundations.md`: the work and its status.

### A question for Griff about CLAUDE.md

**The rule.** "Anything crossing the network is **unproven** until it has run on two devices on two
Apple Accounts" (CLAUDE.md, "The rig, which is not optional"), and rule 3 of "Before building".

**Why it is there.** A green suite was wrong about CloudKit more than once, and one fake that was
easier than the real thing hid every epoch key going to CloudKit in the clear for four weeks.

**The question.** Once the contract is green against both the fake and iCloud, and F12 and R2 make
the fake no easier where section 3 says it is easier today, may a change that touches nothing under
`C/`, the schema, the entitlements, the app target's wiring of a round, the transport protocols or
the fakes be called proven when its guarantee sentences hold in the many-device suite, with the
two-account smoke run before every tester build and not for every change?

**Recommendation.** Yes, with those conditions met first. Until then the rule stands. Cost: the
rule becomes as good as the contract and the list in section 3 of what the fake cannot catch, so a
new call on `Mailbox` or `EntrySync` has to arrive with its contract rule and its fault. If he says
no, sections 2 to 6 are still worth building; they find faults sooner.

Two facts in the same file: "The rig is four booted simulators" and the install loop over four
UDIDs; there are two (`docs/simulator-rig.md:22-36`). And any scenario here that shows a real fault
earns a "Traps" entry once measured.

---

## 9. Found while reading, each for Griff

Rule 2 of "Before building": a gap is fixed or goes to him with a recommendation. None was run.

1. **The read before a send can miss a removal, two ways.** (a) It is a mailbox round only and
   skips packets a sibling signed for, with no device sync first (scenario 2; `A/AppSession+Messaging.swift:48-58`,
   `A/AppSession+Sync.swift:196, 468-478`). (b) Within two seconds of any round it reads a cached
   view (scenario 10; `C/CloudKitMailbox.swift:174`). Both are against `docs/decisions.md:1506-1509`.
   Recommendation: build scenarios 2 and 10; then run a device-sync refresh and a fresh index for the
   read before a send (one more refresh of each per send), rather than narrowing the ruling's
   sentence.
2. **The device relay hands every record over on every refresh; the engine hands a change over
   once** (R2; scenario 7). Recommendation: build `handsOver: .once`, use it in the new suites, run
   the old device-sync suites with it and read what fails before making it the default.
3. **A space made twice is swept whatever it holds** (`C/CloudKitMailbox.swift:102-108, 199-204`).
   Inferred: a link the other person joined, and its packets, go with it. Recommendation: say
   whether `LocalPairStore` may gain ten lines to model it, or move out of `CarpenterKit` first
   (item 6).
4. **A key handed out in a packet that expired is never offered again until a relaunch**
   (scenario 4; `A/AppSession+Sync.swift:583-592, 608, 621`; `A/AppSession.swift:195`).
   Recommendation: clear the mark for a key whose packet is withdrawn unread, the way an altered or
   vanished packet already clears it.
5. **Two device removals in one packet are ordered by the dates their devices wrote, on a friend's
   phone** (scenario 6; `K/Crypto/DeviceRegistry.swift:366-374, 443-448`). Recommendation: if the
   scenario shows a friend disagreeing with the member's own devices, a packet carries each removal
   with the iCloud time its own record was stored, and friends order by that.
6. **`LocalPairStore` ships in `CarpenterKit`** and only `F/` calls it (research-code, "Noticed").
   Its first-stored dating (F12) stays wrong for `FileMailbox` until it moves. Recommendation: move it
   to `CarpenterKitTesting`, as its own commit, then fix line 246 there.
7. **An Outpost post has no read before it** (`A/AppSession+Messaging.swift:37`), so an owner just
   back writes under the key a reader's removed device holds until a round reaches that reader
   (scenario 25). Recommendation: a post reads first, as a message does.
8. **A key a removed device signs is taken by a friend who has not yet heard**
   (`docs/crypto-brief.md:475-477`), and a removed device's key can reach a friend through a third
   person (scenario 1) or sort first among keys of one number (scenario 5). Recommendation: wait
   for scenarios 1 and 5; if either fails, the question is what a friend should check when a
   member's device list changes after a key was adopted.
9. **`App/Carpenter/AppRootView+Sync.swift:60` passes `media: cloud`** where
   `App/Carpenter/AppRootView.swift:99` has `media`. Read: under `--mailbox` a round looks for photos
   in CloudKit. App target only.
10. **`docs/testing.md` describes tests and files that are gone** (section 8).

---

## Findings not taken, and why

Every major finding of the 2026-11-11 review was taken. Where the spec took it differently from the
review's fix:

- **Finding 1 (key through a friend before the removal).** Taken as scenario 1. The removed tablet
  is `mailboxOnly` rather than "never told" by the harness withholding relay records, because a real
  tablet on the same account would get those records; only a modified app ignores them.
- **Finding 3 (`sameRoom` compares a number).** Taken. Added: the fingerprint tie is random per run,
  so scenario 5 repeats ten times and prints the tie (section 5); the review's fix did not say how
  to make it replayable, and it cannot be without app code only tests call.
- **Finding 4 (`advanceEpoch` from the script).** Taken in scenario 3. Scenario 5 still calls it,
  on the removed phone, because a modified app can.
- **Finding 7 (recovery key).** Taken as scenario 16, first of the later list, not in the first
  twelve: scenario 1's second half already puts a member's new device behind a friend a round
  behind, which is the shape the review named first. Moving it up is a one-line change if Griff
  reads "Carol's key changes" as this.
- **Finding 8 (Outpost with the owner away).** Taken as scenario 25, later; its first half is a
  question (section 9, item 7), not an assertion, because it asserts a behaviour Griff has not ruled
  on.
- **Finding 9 (scenario 13 cannot fail).** Taken into scenario 9. Scenario 4 of the first draft was
  cut rather than given a break.
- **Minor findings 10 to 12.** Taken: scenarios 13 and 17 trimmed to what is new; scenario 8 gains
  the no-relaunch case; scenario 22's break moved to the sibling path; scenario 15 writes Erin's
  entries by hand; all four `Gathering` tests move; the "send at call n" sweep is scenario 11B.

Not taken from the first draft's own claims, after the two checks: per-person `cannotCollect` as
the way to make somebody late (the real mailbox's read is all-or-nothing per refresh, section 3,
F1r); `settleDeviceSync` as the harness's wait (wall-clock sleeps); and the first draft's
guarantee that a run gives "the same result every time", which random identifiers make untrue
where the app breaks ties by them.

<!-- COPY END bcf7d5cc -->
