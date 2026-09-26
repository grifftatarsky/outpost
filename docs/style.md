---
# COPY BEGIN 91a604a1 [NEEDS HUMAN REVIEW]
title: Style and usage
layout: default
nav_order: 5
---

# Style and usage

How code in this repository is written, and the patterns to reach for. [CLAUDE.md](https://github.com/grifftatarsky/outpost/blob/main/CLAUDE.md)
holds the rules the lint enforces and the traps; this page is the everyday shape of the code around
them. Where the two overlap, CLAUDE.md wins.

## Reading the code

- There are no comments. A name says what a thing is, a test says what it must do, and
  [Decisions](decisions.md) says why. The only comments are the lint's mechanism phrases,
  `// MARK:`, `swift-tools-version`, and the copy review markers.
- A test suite is one concept, and every test's name is a sentence a reader can check against the
  app: "Saying no rotates nothing", not `testNoRotation`.
- A type splits by concern into `Type+Concern.swift` (`AppSession+Sync.swift`). After a split, a member
  used from a sibling file is widened on purpose, and never takes a name Darwin, Foundation or
  SwiftUI already has.

## Where work happens

- `CarpenterKit` depends on Foundation, CryptoKit and OSLog only. Every platform service is a
  protocol there (`Mailbox`, `EntrySync`, `KeychainStore`, `LogStore`, `DocumentStore`, `Clock`), with
  a fake in `CarpenterKitTesting` that produces the bytes the real one produces.
- `AppSession` owns state and is main-actor isolated. Fetch in an `async` call, apply in a
  synchronous one; never carry session state across an `await`.
- Views in `CarpenterUI` take values and closures. When a screen needs more than two or three actions,
  they travel as one struct (`DebugActions`, `TestProfilesControl`), so a new action is one field
  rather than a new parameter on every view in the chain.

## What a render may cost

SwiftUI reads the session many times a second, so anything a body reads answers from what is already
known.

- A computed `var` is cheap: a field, a lookup, arithmetic. Anything that walks the log, derives a key
  or decrypts is a `func`, and the session caches its answer.
- Anything derived from a value's own fields is computed once, when the value is made, and stored:
  `Entry.hash`, `Identity.id`, `DeviceKeys.id`, `Projection.members`. Each of these used to be
  recomputed on every access, and each was the slowest thing on a screen.
- Group once, then look up. `Projection` indexes its entries by room when it is built; a question
  about one room walks that room, never the whole log.
- A key agreement goes through `pairwiseSecret(with:)`, which caches it. Never derive one in a loop.
- Find an entry by its hash through the projection's index (`entry(_:)`), never with
  `first { $0.id == … }` over the log: what is still editable is always at the end of it.
- Work over the whole log that is pure — checking every signature, decoding the log, sealing the
  feed between devices — runs off the main actor, with `Array.inParallel` or a `@concurrent` function.
- Ask the cheapest question that answers the caller: `hasSomebodyToReach` stops at the first
  contact; `peers()` builds them all.
- Budgets for what a render reads, and for sorting and naming at scale, live in
  `ProjectionCostTests` and `CausalOrderTests`.

## Caches and what a screen is told

- The projection is rebuilt only when the log really changed. `Replica.revision` is a fresh value on
  every real change, and every mutating method on the replica sets it unless it provably changed
  nothing. The session's `replica` rebuilds when the revision moves, not on every write.
- Derived caches are `@ObservationIgnored` and sit behind one observed counter, `projectionGeneration`.
  `logChanged()` bumps it when the log changes, and `projectionInputsChanged()` when something the
  projection reads outside the log changes (a name, a nickname, the show-names choice, who you have
  met). A per-room cache goes through `cached(_:_:_:)`, which reads the counter for you. A new cache
  that does not go through it, or read the counter itself, serves a stale answer that looks like a
  message that never arrived.
- Shared state is written only when it differs: `update(_:to:)`. Observation tells every screen that
  read a property when it is assigned, equal or not, and a sync round that reassigns its own values
  redraws every open screen for nothing. Mutating calls count as assignments, so check before
  `removeAll` or `removeValue`, and integrate into a copy of the replica when nothing may be added.
- `WhatAScreenIsToldTests` holds all three: an unrelated read is quiet, an empty round is quiet, and
  a new message or a new name is heard.

## What arrives from somebody else

A packet, an entry or a grant is written by somebody who may be running a different client, so
nothing in it is trusted because the app would never have written it.

- A number is not a loop bound and a conversion does not trap. Missing history is span arithmetic
  (`normalized`, `intersecting`, `subtracting`), a walk visits only positions this device holds,
  counts saturate, and a date clamps (`Int64(exactly:)`) before it becomes canonical bytes.
- Only members can change who is in a room. An entry type that changes who is in a room checks that
  its author is in the room at that point in the log, and a vote counts only while its author is still
  in the room.
- A room key never replaces one already held, and one from somebody the room shows as removed or
  departed is refused.
- `ClaimedHistoryTests`, `DatesPastTheEndOfTimeTests`, `WhoCanAddPeopleToARoomTests` and
  `WhoCanSendYouAKeyTests` show the shape of a test for each.

## State that persists

- `PersistedState`, `TestProfiles` and any other stored document decode field by field with
  `decodeIfPresent` and a default, so an older file still opens. A new field needs its line in
  `init(from:)` and in the test that fails when a field goes unnamed.
- A file that cannot be read is set aside, never written over (`TestProfileStore.load()`).
- A type the log is written in keeps its encoded fields exactly. `Entry` stores its hash but names its
  coding keys so the hash is never written; `EntryHashTests` pins the key set.
- Canonical bytes are append-only: an optional field added later is absent when nil, never marked
  absent. Pin the old layout by writing it out by hand in a test.
- A write that keeps history, a key, a certificate or anything a flow needs after a relaunch goes
  through `persistOrReport`, never `try?`.
- `saveState()` skips a state equal to the last one that landed, so call it freely; do not guard call
  sites. A launch writes nothing it already kept (`WhatALaunchWritesTests`), and an idle round writes
  nothing at all (`WhatARoundWritesTests`).

## SwiftUI

- Native first: `List`, `Section`, `SettingsRow`, `SettingsToggle`, `SettingsHeaderCard`,
  `ChoiceRow`. A page's explanation is a header card at the top of that page.
- Copy a member reads is `Text("…", bundle: .module)`, or a `LocalizedStringKey` or `Text`
  parameter. A helper that takes copy as a `String` draws it verbatim, and it is never translated.
  `Text(verbatim:)` is only for codes, fingerprints and fixed formats.
- A view built in two places is one `var` called from both.
- `@State` is for what the view owns. An `@Observable` object handed in is `@Bindable` (or a plain
  `let`), and a value the session owns arrives as a `Binding` into the session, never a `@State` copy
  seeded from it: the copy goes stale the moment the session changes it, and its next edit writes the
  stale copy back.
- A `@State` initial value is evaluated every time the view is made, even though SwiftUI keeps only
  the first. A store shared by many views (a bubble's favourites) is made once, above them.
- A debug-only screen wraps its whole file in `#if DEBUG`; gating the call site leaves its words in
  the release binary.
- Filled accent buttons use `primaryAction()`, section labels use `.sectionHeading()`, and a
  destructive control that draws a symbol states its colour.

## Copy

- Every string a member reads sits between `COPY BEGIN <id> [<status>]` and `COPY END <id>`. Only a
  person moves a status forward. New copy takes a new id from `Scripts/copy-review.py new-id`.
- Present tense means it is in the build. Control labels are sentence case.
- The product name is never written in Swift. The same word also names a member's feed, which the
  lint allows, so the lint cannot catch the product name used in a sentence: read for it.
- Write plain English, the way you would explain it to another engineer. Say what the code does and
  what happens to the member. No metaphors for technical events: say exactly what happens, for example a
  key is sent, made up, accepted or refused.
- Key rotation is "key rotation" or "rotate the key", never "turn".
- Never "fold". Say what happens: the member list is built from the log, the log is rendered, the
  projection is rebuilt.
- Never "shape" as a verb, in docs or code. As a noun it means a model or a data layout, nothing else.
- A decision or an open question is plain paragraphs: what the app does now, why, and what it costs.
  No sub-headings inside it.

## Tests

- Write the test that fails first, and watch it fail against the code before the fix. A test that
  cannot fail proves nothing: a naming-cost test that asked for the viewer's own name took an early
  return and passed against the slow code; an emoji-order test whose `try? #require` found nothing
  compared nothing.
- Wait for a condition, with a cap; never sleep for a fixed time. `settleDeviceSync()` waits until
  nothing is publishing.
- A measured gap that needs a design decision is recorded with `withKnownIssue`, so the suite stays
  green and flags the day it is fixed.
- A test that fakes time advances the clock between changes a last-writer-wins merge has to order.

<!-- COPY END 91a604a1 -->
