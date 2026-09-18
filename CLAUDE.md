# Working in this repository

Outpost is group messaging for iPhone with no server behind it. A message is sealed on the sending
device and left in that member's own iCloud; the people it is for collect it from there. It builds
and runs on a Mac, which is **not** an offered platform — Griff ruled on 2026-09-13 that the product
is iPhone until somebody draws the other two.

The source is named **Carpenter**. The product is named in `Config/Branding.xcconfig` and nowhere
else — a lint fails the build over it. "Carpenter" must never reach a screen, and "Outpost" must
never be written down in Swift.

## Read this first

`docs/` is maintained and it is the record. Do not re-derive what it already says.

| If you are | Read |
|---|---|
| new here | [docs/index.md](docs/index.md), then [docs/architecture.md](docs/architecture.md) |
| about to decide something | [docs/decisions.md](docs/decisions.md) — **and read its first section before citing any entry** |
| about to build something | [docs/roadmap.md](docs/roadmap.md) for status, the epic under `docs/epics/` for the story |
| looking for what is unfinished | [docs/open-questions.md](docs/open-questions.md) |
| about to touch a key, a seal or a signature | [docs/crypto-brief.md](docs/crypto-brief.md) — what each key is derived from and bound to, and the three failures that were all in the composition |
| about to test | [docs/testing.md](docs/testing.md), [docs/simulator-rig.md](docs/simulator-rig.md) |
| wondering why something is odd | [docs/inbox.md](docs/inbox.md) — noticed and parked |

**Decisions are attributed.** Every entry is marked `RULED` (Griff decided it), `PROPOSED` (Claude
did), or `FACT` (a property of the platform). A `PROPOSED` entry is a default, not a constraint, and
**may never be cited as a reason not to do what Griff asked for**. This rule exists because the
opposite happened: entries written in his voice were quoted back to him as his own rulings.

## There are no comments in this repository

19,000 lines of them were deleted on 2026-09-12. Griff's reason: "the comments only lie to you." The
failure was real and repeated — comments describing fixes that were no longer in the build.

So: **read the code, and trust the tests over any prose.** What a thing does is in the source; why it
is that way is in `docs/decisions.md` and in the traps below. Do not reintroduce explanatory
comments. Five comments survive because the lint reads them as mechanism (`cross-fade only`,
`divides regions`, `intentionally empty`, `reentrancy considered`) plus `// MARK:` and
`swift-tools-version`. Deleting those breaks the build or the lint.

If you learn something worth keeping, put it in a doc, not above a line.

The sharpest case, for anybody tempted to trust one: `CloudKitEntrySync` landed on 2026-08-16 at
12:04 saying *"what is stored is already sealed"*, which was true — the feed held entries and
certificates. At 19:32 the same day the epoch secrets were added to it and the comment was not
touched. Five days later that comment was restated, more confidently, in `architecture.md`. A seal
type was written the same evening and never called. Nobody re-derived any of it from the code for
four weeks, and every room key the member held went to CloudKit in the clear the whole time.

## Spend tokens like they are Griff's, because they are

- **Read narrowly.** `grep -n` for the symbol, then read the twenty lines around it. Do not read a
  6,000-line file to change one function.
- **Do not launch subagents** unless Griff asks in that message. He has said so more than once.
- **Do not re-run the full suite after every edit.** Run the filtered suite while working, the whole
  one before committing.
- **Verify before reporting.** A claim you did not measure is a claim that will be wrong in front of
  him.

## Commands

```bash
cd Packages/Carpenter && swift test
```

```bash
./Scripts/lint-branding.sh
```

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,name=outpost-alpha' build
```

```bash
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,name=outpost-alpha' -only-testing:CarpenterTests
```

`SKIP_SYMBOL_CHECK=1` skips the lint's slowest rule while iterating. CI runs all of it.

## The rig, which is not optional

Anything crossing the network is **unproven** until it has run on two devices on two Apple Accounts.
A green suite has been wrong about CloudKit more than once. The rig is four booted simulators; their
UDIDs, and which two hold an Apple Account, are in [docs/simulator-rig.md](docs/simulator-rig.md).

Build once, install everywhere, and never leave a stale build on a sim — Griff has caught one twice:

```bash
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter \
  -destination 'platform=iOS Simulator,id=<alpha-udid>' -derivedDataPath /tmp/carpenter-dd build
for D in <alpha> <beta> <trig> <quad>; do
  xcrun simctl terminate $D com.microgpt.carpenter 2>/dev/null
  xcrun simctl install $D /tmp/carpenter-dd/Build/Products/Debug-iphonesimulator/Outpost.app
done
```

**Turn the software keyboard on before touching any screen with a field in it.** A simulator driven
from this machine types on the Mac's keyboard, which no member has. Four defects hid behind that
until 2026-09-11 — see [docs/testing.md](docs/testing.md).

**Count to ten when hunting something intermittent.** Three clean runs of a one-in-two fault is a
one-in-eight coincidence, and it happened: a good commit was nearly reverted over it.

## The rules that have teeth

Each of these is enforced, and each exists because it shipped broken once. `Scripts/lint-branding.sh`
is the enforcement and its comments carry the history.

- **The name.** `Config/Branding.xcconfig` holds the product name and the URL scheme. No Swift
  literal may contain either; read them through `Branding.displayName` / `Branding.urlScheme`.
  "Carpenter" must never reach a screen, and "Outpost" must never be written down in Swift.
- **The HIG is the reference, and it is read, not remembered.**
  [developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines).
  Before choosing between two ways the system offers to draw something, go and read what Apple says
  about that component — and where the guidance turns on a question ("what is the scope of your
  search?"), answer that question about *this* app before picking. A modifier chosen because it
  looked tidier on the one screen it was tried on is a guess, and it is a guess that renders
  differently on the next device.
  **Deviating is allowed and recording it is not optional**: a deliberate departure goes in
  `docs/decisions.md` with what it costs, the way every other binding decision does. An undocumented
  departure is indistinguishable from not having looked.
  The failure this exists for, 2026-09-11: `.searchToolbarBehavior(.minimize)` was picked for the
  collapsed glass magnifier, and on a 402pt phone it crams the clear and the dismiss into one
  capsule while a 440pt phone separates them — the same build, two devices, and nobody had read
  that Apple's answer for a search scoped to one section is an inline field under the title.
- **Native first.** Anything the system draws, the system draws. A `VStack` of buttons with
  hand-painted hairlines is an inset-grouped `List` reimplemented worse — the lint rejects
  `Rectangle().fill(palette.separator)` unless the line says it divides *regions* rather than rows.
  Use `List` + `Section` + `.groupedRowSurface()`, and `ChoiceRow` for an option with a checkmark.
  A settings row is `SettingsRow` with its `IconTile`, one line, a short value; a page's
  explanation is a `SettingsHeaderCard` at the top of that page, never a footer on the root.
  `SettingsChrome.swift` holds all three, and a design audit on 2026-09-05 is why.
- **Liquid Glass goes in a `GlassEffectContainer`.** Apple's guidance, and the lint rejects a file
  with more than one `.glassEffect` and no container. A custom glass shape that is an *enabled*
  control also takes `.interactive()`. The container is the unit the system animates — putting glass
  in one is what makes the next OS release free rather than a migration.
- **Motion answers Reduce Motion.** Any file that animates must read `accessibilityReduceMotion` or
  declare on the line that what it animates is a `cross-fade only`.
- **A symbol name that does not exist draws nothing, silently.** Every `Image(systemName:)` is
  checked against the real catalogue, at lint time and in `SymbolNameTests`.
- **No empty `Button` actions.** Three dead controls have shipped. Say `intentionally empty` on the
  line if you mean it.
- **Copy a member reads carries `bundle: .module`.** Without it a `Text` defined in the package
  resolves against the main bundle, is never extracted, and ships untranslated — invisibly, because
  the English build looks perfect. `Text(verbatim:)` is the escape hatch for a code or a
  fingerprint. This rule was added after a `List` conversion silently dropped one.
- **Section labels are headings.** `.sectionHeading()`, never the font alone.
- **Filled accent buttons use `primaryAction()`**, so `.disabled` is visible before it is tapped.
- **A tint beats a role.** `Button(role: .destructive)` reddens the words and not the SF Symbol —
  the app tints its whole hierarchy, and a label's glyph takes that tint ahead of the role. Six
  controls shipped saying "Remove" in red beside a cheerful green icon. Any destructive button that
  draws a symbol says its colour: `.tint(palette.destructive)`, or `palette.destructive` on the
  symbol. `Scripts/lint/destructive-tint.py` enforces it.

## Traps this codebase has actually fallen into

Read these before touching sync. Every one cost real time.

- **Never copy main-actor state across an `await`.** `AppSession` is main-actor isolated, so the
  actor is *free* while a network call is suspended — and what runs on it is the member pressing
  send. Copy-modify-write silently ate their message. Fetch in an `async` call, apply in a
  **synchronous** one. See `SyncSession.integrate` and `ReplicaRaceTests`.
- **The fold is cached, and the cache is invalidated by `didSet` on `replica` and `chains`.** If you
  add a third piece of state the projection reads, it needs the same treatment — and no test will
  tell you, because a stale fold looks like a message that did not arrive. `ProjectionCostTests`
  guards the cost *and* the freshness.
- **A nil check does not survive an `await`.** Actors are reentrant, so `guard x == nil` followed
  by an `await` and then `x = …` lets two callers do the same bring-up. Hold the in-flight work as a
  `Task` and make the second caller await it. `Scripts/lint/reentrancy.py` enforces it.
- **A hand-written decoder is a list somebody has to remember to extend.** `PersistedState` decodes
  field by field with `decodeIfPresent`, on purpose, so a state file from an older build still opens
  — and the price is that a new property is silently dropped until somebody adds a line to
  `init(from:)`. `greetedRooms` was missed, so every launch decoded it as empty and the next save
  wrote the empty array back: the app introduced a member to the same room, by name, every time they
  opened it. The forward-compatibility test could not catch it — tolerating a *missing* key is a
  different question from reading a key that is there. `decodingPersistedStateKeepsEveryFieldItWasGiven`
  is the guard, and it fails if a field this test cannot populate is added without being named.
- **An optional field added to a canonical form must be absent, not marked absent.**
  `CanonicalBytes.optional` emits a presence byte, which is right for a field that has always been
  there and wrong for one being *added*: `optional(nil)` is one field, not none, so the encoding of
  an old value silently changes. Adding two of them to `SealedPayload` changed the associated data
  every existing payload was sealed against and the canonical bytes every existing signature was
  taken over — every entry on every device stopped opening and stopped verifying, and the app
  offered onboarding to accounts with months of history. Fields are length-prefixed: append only
  when present. And a round-trip test proves nothing here, because it seals and opens with the same
  build — pin the old layout by writing it out by hand, as `SealBindingTests` now does.
- **A `desiredKeys` list is a list somebody has to remember to extend.** The mailbox scans a zone
  with named fields so photo blobs stay out of the routing read. The day it arrived it named no
  share-offer field, so every offer came back as a bare record, `sealed` read as nil, and the
  rendezvous reported "found 0 offer(s)" for an afternoon while a fresh offer stood in the zone.
  A field left off that list is not an error anywhere; it is a record that looks empty. When a
  record type is added to the scan, add its fields to `CloudKitMailbox.scannedFields`.
- **ImageIO keeps a source's tags with the thumbnail it makes.** A `CGImage` from
  `CGImageSourceCreateThumbnailAtIndex` handed to a destination copies the Exif block — lens,
  original time — into the "clean" file. `ImagePreparer.redrawn` draws into a fresh context first,
  and `identifyingMetadata(of:)` is the contract a test holds it to.
- **The palette's neutral fills are translucent.** `neutralFill` and `neutralFillStrong` are a
  grey at sixteen to thirty percent, made for avatar discs. Anything that has to *cover* what is
  under it — a tapback over a bubble's corner — needs `palette.background` laid under the fill, or
  the bubble shows through and the mark reads as being behind it.
- **`try?` is for what costs a banner, never for what costs history.** A write that keeps entries,
  a room key or a certificate goes through `persistOrReport`, which counts it into
  `IntegrityReport.writesFailed` and logs it. Silence there is a member watching their history
  arrive and vanish on the next launch.
- **An acknowledgement is a promise that the entry is on disk.** It is what lets the sender stop
  offering the packet, and no transport ever offers one twice. The round used to acknowledge from
  inside its peer loop and write the log after it — several `await`s later — so a process ending in
  between lost the entries *and* the sender's copy, silently. Measured on the rig 2026-09-09: a
  comment acknowledged at 16:59, that device's log last written at 16:53, and the comment gone from
  both ends. Write first, acknowledge second, and carry what a failed write held (`entriesNotWrittenDown`)
  — because `integrate` has already put it in the replica, so the next round sees `alreadyHad`, has
  nothing to write, and would acknowledge an entry no disk ever held.
- **Clearing derived state does not make an entry unusable.** A removal cleared the invitation it
  ended out of the roster — and the entry carrying that invitation is still in the log, so any member
  could append it again and put the offer back on the table. `requests`, `admissions`, `refusals` and
  `confirmations` are all derived from entries anybody in the room can replay, so forgetting an answer
  is not the same as ending a question. Record what is finished (`RoomRoster.spent`), do not merely
  forget it.
- **A key that is a person answers a question about a person.** `confirmations` was
  `[ParticipantID: Date]`, so "has this joiner confirmed" outlived every membership and the phrase
  gate was permanently open for anybody ever removed, anybody who left, anybody whose offer was
  withdrawn or superseded. A `JoinConfirmedBody` names one signature; the map has to key on what the
  body claims, not on who sent it. `admissions` and `refusals` had the same shape and were fixed the
  same way on 2026-09-14: an `AdmissionBody` now names the invitation it answers, and the maps key on
  that. The leak was an invitation *replaced* rather than removed — removal cleared the old maps, a
  superseding `joinRequest` did not, so a vote for a dead offer admitted somebody to the live one.
- **A dictionary keyed by recipient holds one value.** `SyncEngine.pack` addressed epoch grants into
  `[RecipientTag: Data]` with a plain subscript, so a round owing one person keys to two rooms
  delivered the last and dropped the rest — and the sender then marked every owed grant issued,
  because a packet had been written. A reader let into a room and an Outpost the same afternoon got
  the room and never got the Outpost, with no error anywhere. Grants are a list per address now.
  Anything else addressed per peer must be too.
- **A green suite proves nothing about CloudKit.** It has been green while the app did not work,
  more than once. A fake that is *easier* than the real thing proves less than nothing — the
  in-memory mailbox stores wire fields and counts every server operation for exactly this reason.
  **That lesson was applied to one seam and not the other**, and it cost
  four weeks: `InMemoryEntrySync` stored `[UUID: SiblingFeed]`, the struct, never serialised — so when
  `CloudKitEntrySync` wrote the feed to CloudKit as plain JSON, carrying every epoch secret the member
  held, no test in 118 suites could see it. Both are fixed: the relay holds encoded `Data` now, and
  every seam's fake was audited against the rule on 2026-09-14. If a fake does not produce the bytes
  the real one produces, it cannot fail the way the real one fails — hold any new one to that.
- **Nothing is written to CloudKit unsealed, and the app seals it rather than CloudKit.**
  `record[key]` is not encrypted, and `record.encryptedValues[key]` is end-to-end **only when the
  member has Advanced Data Protection on** — otherwise Apple holds the key. Its service key also
  lives in iCloud Keychain, which is exactly what is gone in the case a recovery key exists for. So
  every payload is sealed in `CarpenterKit` before the bytes reach a transport: ChaChaPoly under an
  HKDF-SHA256 key with its own domain, canonical bytes as associated data. Any new `record[...] =`
  has to carry something already sealed. The one that did not is
  [the sibling feed](docs/epics/identity-and-devices.md#the-sibling-feed-is-sealed-before-it-is-written),
  which leaked every epoch key its member held for four weeks.
- **Gating a debug control's call site does not keep it out of the build.** `#if DEBUG` around the
  place a view is *used* makes it unreachable and leaves it *compiled*, so its words reach the
  shipped binary and the string catalogue a translator works from. Measured 2026-09-15: `strings` on
  a Release build returned "Blur every photo", "Rotate mailbox share" and "Show message delay", every
  one of them behind a gated call site. Wrap the debug screen's **whole file**, and run
  `Scripts/check-release-leaves.sh` rather than reading the gates.
- **Two constructions of the same view will drift, and the drift is silent.** A SwiftUI initialiser
  with fifty defaulted parameters accepts an argument list that has quietly lost one; the omitted
  binding becomes `.constant(false)` and the control it feeds moves under the finger and writes
  nothing. That is exactly how *Help on every screen* was broken on iPhone while working on the Mac —
  twice, because the first fix went to the path Griff does not use. The same audit found a room
  invitation reaching only the wrong tab on a split inbox. If a view is built in two places, make it
  one `var` and call that from both.
- **A `private` member whose name exists somewhere else does not fail to compile — it binds to the
  other thing.** Three times in one day, 2026-09-14, all while splitting a type across files:
  `sync()` bound to Darwin's `sync(2)`; `acknowledge(recordNamed:)` bound to the `acknowledge(_:by:)`
  overload beside it and reported an *argument label* error; `help` bound to SwiftUI's
  `View.help(_:)` and reported "cannot conform to View". Only the first failed silently, but all
  three sent the diagnostic somewhere other than the access level, which is where the fault was. The
  rule: after splitting, if a member is now used from a sibling file, widen it deliberately rather
  than waiting for an error to name it — and give it a name nothing in Darwin, Foundation or SwiftUI
  already has (`syncNow`, `acknowledgeRecord(named:)`, `gettingHelp`).

  The original, because it is the one that shipped working and did nothing: splitting `AppRootView`
  left `private func sync()` in one file and seven `await sync()` calls in two others. That is an access error in any other case, and the compiler
  says so. Here it silently bound to Darwin's `sync(2)`, which flushes the filesystem buffers and
  returns — so the app built clean, the suite stayed green, and **every round stopped**: the
  foreground loop, pull-to-refresh, becoming active and a push arrival all flushed a disk instead of
  syncing. Found on the rig 2026-09-14 when a message would not cross, four commits after it
  landed. The only signal was `warning: no 'async' operations occur within 'await' expression`, and
  an incremental build does not reprint it — `rm -rf` the derived data after splitting a type across
  files, and read the warnings. The method is `syncNow()` now, because a name libc does not have
  cannot be shadowed by one it does.
- **Iterating a dictionary is not an order, and the fake had one.** `recordZoneChanges` hands its
  results back in `modificationResultsByID`, a `Dictionary`, and the mailbox built its array by
  iterating it — so a zone's packets came back in a different order on different runs. Measured
  2026-09-14: four packets written, fetched back with the sort removed, out of order in two runs of
  four. `InMemoryMailbox` keeps an `order` array and replays write order, so every test in the suite
  saw an order the server never promised. `SyncSession.integrate` accumulates nearly everything a
  delivery carries, but takes `notifyWalls` whole from each packet — last one wins — and a peer only
  re-sends that list when it changes, so the wrong order leaves a stale wish standing for good.
  `everything(in:)` sorts by `modificationDate` now, with the record name as a tiebreak.
- **CloudKit's query index is eventually consistent.** "Write it, then read it" is not a guarantee
  it makes. Read a zone's change feed, or fetch a record by ID. A query cost a week once.
- **Rotating tags rotate.** Anything keyed by a `RecipientTag` is keyed by *today's* address. A
  packet found under yesterday's is still that peer's.
- **The extension is a second process** over one App Group container. Both processes log which
  container they resolved; `appGroup=false` means it is reading a private, permanently-behind copy.
- **The rig types on the Mac's keyboard, and no member has one.** Everything a software keyboard
  does — the return key's label and what it does, covering the control under the field, placing a
  caret by tapping, a sheet that has to grow — was unexamined until one was finally raised on
  2026-09-11, and four things were wrong at once. Worse, `.submitLabel(.send)` on a
  `TextField(axis: .vertical)` renames the key, takes the newline away and still does not submit:
  measured, then reverted. The arrow in the field sends; ↵ writes a second line; `.onSubmit` is for
  the Mac. Turn the software keyboard on before looking at any screen with a field in it —
  [docs/testing.md](docs/testing.md) has the table.
- **Two Apple Accounts are needed to prove anything peer-to-peer.** An account cannot participate in
  its own share, so the second account is not optional. That much stands; the rest of what this
  entry used to say about simulators was wrong and cost a session — see
  [docs/simulator-rig.md](docs/simulator-rig.md) for what a simulator can actually do, which as of
  Xcode 26 includes real CloudKit against a live account, real APNs push, and the notification
  extension. It still **cannot receive an iCloud Keychain hand-off** — verified 2026-09-01: every
  CKKS view sits in `waitfortrust` because a simulator cannot join the Octagon trust circle, and the
  "Sync this iPhone" toggle silently refuses. Same-account multi-device is hardware-only.
- **Advanced Data Protection makes a simulator useless for this app.** With ADP on, the whole
  private database is end-to-end encrypted through PCS, PCS needs the keychain trust a simulator
  cannot get, and every zone write fails `PCSNoPublicIdentity` with `bytesUploaded=0`. Measured on
  two accounts the same afternoon: the ADP account wrote nothing, the non-ADP account ran seven zone
  operations clean. Sign simulators into a dev account **without** ADP.
- **An account remembers members that no longer exist.** `hasExistingMember()` asks whether any
  device ever published a feed, and a feed outlives the device that wrote it — deleting a simulator
  does not delete its feed. An account littered with dead feeds makes every fresh device wait
  forever for a key nobody holds. `--reset-account` is the way out and it is **destructive to the
  Apple Account**, not just the device: it erases the CloudKit zone and removes synchronizable
  keychain items, which propagates to every real device signed in. Read the warning in the rig doc
  before running it on a personal account.

## Honesty rules for anything a member reads

The product's whole proposition is that its claims are true, so overstating costs more than a
missing feature. This governs the docs *and* the UI copy:

- **Present tense means it is in the build.** Designed, half-built, or built-but-unproven gets a
  callout, not a sentence.
- **Never report an inference as a measurement.** If a number was not measured, say what is known,
  including "not measured".
- **A mark is only ever what was observed.** Never infer delivery or reading.
- **A photo that was not screened is not "clear".** `ScreeningVerdict.notScreened` is its own
  answer, drawn as an ordinary photo and explained in the Safety footer. Collapsing it into
  `clear` is the app claiming a look it did not take.

## The layout

| Module | What it is |
|---|---|
| `CarpenterKit` | The log, the crypto, the sync engine. **No framework dependency beyond Foundation** — every platform thing sits behind a protocol (`Mailbox`, `KeychainStore`, `LogStore`, `DocumentStore`, `EntrySync`, `Clock`). |
| `CarpenterApp` | `AppSession`: storage, rooms, membership, and what a sync round does. Main-actor isolated. |
| `CarpenterUI` | SwiftUI screens. No idea where their data came from. |
| `CarpenterCloudKit` | The mailbox and device sync, on CloudKit. **Not covered by `swift test`** — it needs an account, a container and entitlements. |
| `CarpenterKeychain` | The one place that talks to Security.framework. |
| `CarpenterMedia` | Photos and clips: ImageIO and AVFoundation to prepare one for sending (scaled or re-encoded, stripped of every tag), and Apple's on-device screening — image and video — behind the kit's `MediaScreen` seam. |
| `App/Carpenter` | The composition root (`AppRootView`) and the notification service extension. |

Tests live in `Packages/Carpenter/Tests/CarpenterKitTests`, one suite per concept, named as
sentences. `TestSession` builds a session; `CarpenterKitTesting` holds the fakes.

`App/CarpenterTests` is the second suite: the things that need a real app bundle, which today means
`SystemKeychainStore` against Security.framework. `swift test` does **not** run it — the third
command above does, and so does CI.

## When you finish

- A decision that binds → `docs/decisions.md`, marked `RULED` only if Griff actually said it.
- Something unbuilt or uncertain → `docs/open-questions.md`, as a question for him.
- Work → an epic under `docs/epics/`, and its status on `docs/roadmap.md`.
- Noticed and parked → `docs/inbox.md`.
- Anything crossing the network is **unproven** until two devices on two accounts have run it. Say so
  rather than implying a passing suite covered it.
