---
# COPY BEGIN e62fa78f [NEEDS HUMAN REVIEW]
title: Architecture
layout: default
nav_order: 3
---

# Architecture

{: .no_toc }

How a message gets from one phone to another with no Outpost server in the path.

This page covers the pieces and how they move. For what each key is, what it is derived from and
what an attacker in each position sees, read [The crypto, written down](crypto-brief.md). That page
was written from the code in `CarpenterKit/Crypto`; where the two disagree, trust it.

1. TOC
{:toc}

<!-- COPY END e62fa78f -->

<!-- COPY BEGIN 4842111d [NEEDS HUMAN REVIEW] -->

## The log

Everything a member does is an **entry**: a message, a reaction, a room rename, an admission, a read
receipt. Each entry is signed by the device that wrote it, linked by hash to the one before it in
that device's feed, and stamped with a vector clock. Any two devices holding the same entries build
the same result from them without talking to each other.

An entry's payload is sealed under the room's **epoch key**. The payload's type, version and text are
inside the ciphertext; only the epoch number sits beside it. The entry's author, device, position,
clock, time and room are outside that seal, and the whole entry then travels inside a packet sealed
again for its recipients. So the transport cannot tell a message from a reaction.

No member can remove another member's entry from the log. A deletion is an entry too.

<!-- COPY END 4842111d -->

<!-- COPY BEGIN 917cec80 [NEEDS HUMAN REVIEW] -->

## The mailbox

Each member keeps one **space** for each person they talk to, in their **own** iCloud private
database: a zone named `Pair-` and a random number, shared read-only with that person's account
alone. Nobody writes anywhere but their own iCloud. A space holds:

- **Packets** for that person: the entries sealed under a fresh content key, the key wrapped for
  that person under the secret the two share, addressed to a tag derived from it. A round writes one
  packet per person, or more when the round is bigger than a packet.
- One **ring** record, rewritten with random bytes when the round left something that should ring.
- **Receipts** for what was collected from that person's space. A reader never touches the sender's
  space; it writes a sealed receipt into its own space for the sender, and the sender takes a packet
  back once a device of the reader that still counts has signed for it.
- A **copy of each photo** sent to that person, cleared the same way.
- A `PairInfo` record whose `hint`, a keyed hash of the pair's secret, lets every device of the
  member tell which space is whose.

A space's link is exchanged in a code, in an invite, or, between room members who never swapped
codes, in a room entry sealed to the one person it is for. A contact is read only from the accounts
that a device of theirs that still counts has named. See
[Decisions](decisions.md#each-pair-of-people-gets-its-own-mailbox).

Readers read a zone's change feed, not a query. CloudKit's query index is eventually consistent, so
a record just written may not come back from a query. The change feed is consistent and needs no
schema.

A member's contacts' old `Outbox` zones, from before 2026-09-27, are still read until every contact
reads a space, and then the member's own old outbox is erased.

**Storage bills the sender**, in their own iCloud. The public database is never used, so the
developer's costs do not grow with the number of people using the app.

<!-- COPY END 917cec80 -->

<!-- COPY BEGIN af6d6fe5 [NEEDS HUMAN REVIEW] -->

### Addresses rotate, and readers look back

A tag lasts a day (`SyncSession.tagWindow`). A packet written at 23:50 and collected at 00:10 is
addressed to yesterday, so a reader asks for the last seven days and tomorrow, and acknowledges under
whichever tag matched. Asking for today alone once stranded messages: never found, so never
acknowledged, and never sent again, because the sender had recorded them as sent.

<!-- COPY END af6d6fe5 -->

<!-- COPY BEGIN f134eff4 [NEEDS HUMAN REVIEW] -->

### A hole is named and asked for

Feeds are numbered from one without gaps, and every entry's clock says what its author had seen, so
a device can list exactly which positions it is missing. A repair is that list, the device's heads
and a room, sent to one peer inside the sealed packet. The peer answers with the entries it holds and
names the ones it does not, so the asker can tell "sent and not arrived" from "nobody has it". A
member who joins late asks the inviter for the room's history as soon as they accept, because a
sender never offers an entry twice.

<!-- COPY END f134eff4 -->

<!-- COPY BEGIN 122c0d21 [NEEDS HUMAN REVIEW] -->

### A deleted room leaves its numbers spent

A member's feeds are shared across every room they are in. Deleting a conversation they are no
longer part of removes entries from the middle of those feeds, and the repair above would read the
gaps as holes and ask for them back. So `Replica.close(_:)` records each removed entry as a
`SpentEntry` (feed, number, hash and room). The gap index counts a spent entry as held, the frontier
includes it, and `integrate` answers a copy of it with `.alreadyPresent`. An entry for a closed room
that arrives later is spent the same way and not kept.

The closed rooms and the spent positions are saved before anything is removed. The rooms ride
`MemberPreferences.deletedRooms`, so the member's other devices close them too; the positions are in
`PersistedState.spentEntries`. A launch finishes a deletion that was cut off. A device whose newest
entry was spent continues its feed from that entry's link instead of reusing the number. Accepting a
new invitation to a closed room reopens it, so its history can be asked for again.

<!-- COPY END 122c0d21 -->

<!-- COPY BEGIN 26fdeeea [NEEDS HUMAN REVIEW] -->

## Device sync

A member's own devices converge separately, through `CKSyncEngine` over a `SiblingFeeds` zone in the
member's private database. Each device writes three kinds of record (`SiblingRecord.Kind`):

- **A state record**, one per device: the device certificates, the member's preferences, and how far
  this device has read each of its siblings' mail. It is rewritten when one of those changes.
- **Mail**: what this device wrote since its last mail, and any room keys it got since then. It is
  deleted once every other active device of the member has read it, or after 30 days.
- **A catch-up** for one device: everything this device has written and every room key it holds. It
  is written for a device that is new, or that was away long enough to miss deleted mail, and it is
  deleted once that device has read it.

Two more kinds carry approval: a new device writes a **request** (its public keys, not sealed), and
an approving device answers with an **approval** sealed to the new device, which deletes both once
it has read them. The state record holds certificates, removals and read cursors; the member's
settings travel in mail and catch-ups instead, so a device that isn't approved can't read them.

A device with no other devices writes only its state record. `SiblingMail` decides what to write and
delete, and `SiblingMailTests` holds it: one message uploads about 1.7KB however long the history
is, where it used to upload the whole history (71KB after 65 messages in the test). A new device is
caught up by another of your devices, so it waits until one of them is open.

Every record is sealed on the device before it is written: ChaChaPoly under a key derived from the
identity with HKDF-SHA256, with the member, the writing device and the record's kind as associated
data, so a record cannot be replayed into another device's slot or passed off as another kind.
`EntrySync` carries `SealedSiblingFeed` and nothing else, so the unsealed type cannot reach a
transport.

**The app seals it rather than using `CKRecord.encryptedValues`.** Apple's encrypted fields are
end-to-end only when the member has Advanced Data Protection on; otherwise Apple holds the keys. And
the CloudKit service key lives in iCloud Keychain, which is exactly what is missing when somebody
restores from a recovery key. The seal is under the identity, and the recovery key is the identity.

{: .warning }
> **Until 2026-09-13 this record was not sealed.** Every epoch key the member held went to CloudKit
> in the clear for four weeks, while this page said otherwise. See
> [the ticket](epics/identity-and-devices.md#the-sibling-feed-is-written-in-the-clear).

The app tells the engine when to sync instead of letting it schedule itself
(`automaticallySync = false`). Left to schedule itself, an explicit `fetchChanges()` returned in
milliseconds without asking the server anything.

<!-- COPY END 26fdeeea -->

<!-- COPY BEGIN dd42746f [NEEDS HUMAN REVIEW] -->

## Notifications

There are three subscriptions, each scoped to a record type. One of them is visible.

| Channel | Database | Kind | Record type | Push |
|---|---|---|---|---|
| `deviceFeed` | private | `CKDatabaseSubscription` | `SiblingFeed` | silent |
| `inbox` | shared | `CKDatabaseSubscription` | `SyncPacket` | silent |
| `ring` | shared | `CKDatabaseSubscription` | `PairRing` | alert, mutable content |

The transport cannot see inside a packet, so the packet channel wakes the app and shows nothing. The
**ring** is one record in the sender's space for each person, rewritten only when the round left a
message for them, or when the sender's devices changed. A watch limited to one record type rings for
nothing else: measured on Griff's phone 2026-09-27, where changes to other record types in the same
space woke nobody.

The notification service extension opens the message on the device and replaces the generic line with
the room and the sender. It writes nothing to the server.

**Turning notifications off is a supported way to use the app.** Every channel speeds delivery up;
none of them is how delivery happens. The app syncs when it comes to the front, while a conversation
is open, and on pull to refresh. With notifications off it works, and is not realtime while closed.
The app never treats that as an error.

<!-- COPY END dd42746f -->

<!-- COPY BEGIN b8c80004 [NEEDS HUMAN REVIEW] -->

## The seams

`CarpenterKit` depends on nothing but Foundation. Everything that needs a platform framework sits behind a protocol,
such as `Mailbox`, `KeychainStore`, `LogStore`, `DocumentStore`, `MediaStore`, `EntrySync`,
`MediaScreen`, `AccountRegistry` and `Clock`, so the
logic above it runs in tests without an account, a container or an entitlement.

A fake that is easier than the real thing proves nothing, and this project has paid for that twice.
The in-memory mailbox stores wire fields rather than the struct and counts every server operation,
because both gaps once hid a bug the whole suite passed. The same lesson went unapplied to
`EntrySync` for four weeks: the in-memory relay stored the unsealed struct, so no test could see what
the real implementation wrote, and the unsealed sibling feed passed 118 suites. The relay holds
encoded `Data` now. Every seam was checked against this rule on 2026-09-14; the table is in
[Testing](testing.md).

<!-- COPY END b8c80004 -->

<!-- COPY BEGIN 6bcfa419 [NEEDS HUMAN REVIEW] -->

## Where the source lives

One module is one concern. Inside `CarpenterApp`, `AppSession` is split into a file per epic, so a
review can be scoped to one:

| File | Holds |
|---|---|
| `AppSession.swift` | the type, its state, the projection cache, `append`, `refresh`, epoch persistence |
| `+Identity` | bring-up, restore, names, avatars, nicknames, the recovery key, devices |
| `+Membership` | invitations, admissions, the solo check, room access, removal, leaving |
| `+Verifying` | comparing codes with somebody after the introduction |
| `+Messaging` | sending, editing, reading, search, read receipts, hiding |
| `+DeletingRooms` | deleting a conversation and finishing a deletion that was cut off |
| `+Outpost` | the wall: readers, posts, comments, reactions, what is new |
| `+Attachments` | photos and clips out and back, and the sweep |
| `+Notifications` | notification levels, badges, Do Not Disturb |
| `+Etiquette` | the privacy check-up, blocking, what is announced into a room |
| `+Supporter` | the free year and the Supporter badge |
| `+Sync`, `+DeviceSync`, `+Peers` | the round, the feed between a member's own devices, and who can be reached with which key |
| `+HistoryRepair` | filling a hole, and the reverse channel |

`CarpenterApp/Push/` holds what a push carries, what it opens and what the badge counts.

The cost of the split is access: a property read from a sibling file cannot be `private`, so the
session's state is `internal` to `CarpenterApp`. That module holds the session and little else.

`CarpenterUI` has one folder per feature under both `Screens/` and `Components/`: `Identity`,
`Membership`, `Rooms`, `Messaging`, `Outpost`, `Notifications`, `Safety`, `Supporter` and `You`.
`Components/Shared` holds what every feature draws, such as `ChoiceRow`, `PersonRow`,
`SettingsChrome` and `AvatarView`. The large types are split the same way: `RootView` into phone,
rooms, Outpost and desktop files; `AppRootView` into one file per concern, with `+Ready` wiring the
main screen; `ConversationView` into menu, transcript and composer; `Projection` into a file per
thing it projects; and `CloudKitMailbox` into a file per seam, so which seams have a live test can be
read off the folder.

**Splitting a type across files has a trap that does not fail the build.** A `private` method whose
name matches a C function binds to the C function from a sibling file instead of failing to compile.
`sync()` did exactly that and stopped every round. After a split, delete the derived data and read
the warnings; the only sign is `no 'async' operations occur within 'await' expression`, and an
incremental build does not print it again. `CLAUDE.md` has the full account.

<!-- COPY END 6bcfa419 -->

<!-- COPY BEGIN 166592a6 [NEEDS HUMAN REVIEW] -->

## Nothing a render reads may do work

SwiftUI evaluates a view's body many times a second, and anything the body reaches runs that often.
On 2026-09-16 two things did real work there, and the app never went idle: taps stopped landing, the
status bar clock froze and every UI test query timed out. Both were found by sampling the running
app.

- **`roster(of:)` opened every membership entry in the room**, a ChaChaPoly open and a JSON decode
  each, and `AppRootView.body` reached it. The main thread measured 100% inside it. It is cached now
  beside the other opened reads (`cachedRosters`, `cachedOutOfRoom`, `cachedReadEvidence`,
  `cachedReporting`, `cachedOutpostAccess`), and `logChanged()` clears them all. **Nothing that
  depends on a preference belongs in those caches**: hiding, blocking and delivery marks change
  without the log changing, so they are applied to the cached result on every read.
- **`identityCode()` wrote to observed state.** Each call minted a nonce into
  `persisted.phraseNonces`, the write triggered a render, and the render called it again: 1,716
  main-thread samples against five idle, a disk write per pass, and a list growing without bound. A
  view reads `codeForSharing` now, which never mints; `prepareCodeForSharing()` mints outside a
  render. `PhraseCommitmentTests` checks that reading it twice does not mint.
- **Pairwise secrets are cached and never cleared.** Deriving one is an X25519 agreement and an HKDF,
  measured at 2,396µs, and `peers()` asks for one per peer on a path every conversation render
  reaches. Keeping them is safe because a `ParticipantID` is the SHA-256 of the keys the secret comes
  from, so an ID cannot come to mean different keys. Only a restore changes this member's own
  identity, and a restore rebuilds the session.
- **What an entry says is remembered by its hash, and rebuilding the projection does not forget it.** `OpenedPayloads`
  keeps each entry's plaintext and what it draws, so a rebuild reads nothing twice. An entry's hash
  fixes its bytes, so the only thing that can make a remembered answer wrong is losing the key that
  opened it: the memory is forgotten whenever any room's known epochs shrink or its chain goes. A
  placeholder for an entry that would not open is never remembered, so it cannot outlive the key that
  opens it (`OpenedPayloadsTests`).

`ProjectionCostTests` holds every screen read to a per-call limit, because a body may make several
calls and a 60fps frame is 16,700µs. The conversation screen's two reads are still over the limit
and are recorded as exceptions with their numbers; see
[the inbox](inbox.md#the-conversation-screen-still-costs-3500µs-a-read). **Any new state those caches
read needs `logChanged()` too.** Nothing fails if it is missed; the cache goes quietly stale.

<!-- COPY END 166592a6 -->

<!-- COPY BEGIN 31bd476c [NEEDS HUMAN REVIEW] -->

## What a round assumes about its own order

`AppSession.sync(through:media:mode:)` is about 270 lines in one function on purpose: most of what has
gone wrong in this app went wrong because two of its statements ran in the wrong order. It was read
line by line on 2026-09-14. This is what each ordering assumes and what checks it.

| The step | What it assumes already ran | Checked by |
|---|---|---|
| `issuedGrants.insert` when `packetsWritten > 0` | the grants rode the first packet, and a failure there threw before this line | `grantsAreOnlyMarkedIssuedIfTheyWent` |
| `roomsWithUnsentMessages.subtract` only when `sendFailure == nil` | a batch that failed still owes its bell | `partialFailureIsNotLoss` |
| `storage.log.append(owed)` before `session.acknowledge` | a failed write throws, so nothing is acknowledged | `aRefusedWriteLeavesThePacketOutstanding` |
| `entriesNotWrittenDown` carried into the next round | `integrate` already put them in the replica, so the next round has nothing to write and would acknowledge an entry no disk holds | the same test |
| `syncedFrontier.observe` only for `report.written` | an entry counts as sent only if its packet landed | `partialFailureIsNotLoss` |
| `outstandingPackets` filtered by `pendingDeliveries`, then this round's added | a collected packet stops counting as undelivered before new ones go in | `collectionIsReportedWhenItHappens` |
| `viewMayBeStale` set after the peer loop | the next round's `withholdsKeys` reads what this round refused | `RemovalTests` |
| `persisted.certificates = knownCertificates()` after the peer loop | a certificate that arrived this round is saved | nothing |
| `peersLastRound` assigned after `metSomebodyNew` is computed | "new" means new since the previous round | nothing |
| `saveState()` last | every change above it is in the file | nothing |

The three unchecked rules are ordinary "do this last" rules. Breaking one would leave a stale file,
not lose history. They are listed so the next person to move a line knows which were tested and which
were only read.

<!-- COPY END 31bd476c -->

<!-- COPY BEGIN 8aa03a7e [NEEDS HUMAN REVIEW] -->

## Two processes, one container

The app and the notification service extension are separate processes over one App Group container.
The app writes the log and the state file under a cross-process lock; a Swift actor serializes work
inside one process and does nothing across two. **The extension writes neither.** It opens the
container through the `readOnly` view of its `SessionStorage`, keeps what its round collects in
memory long enough to draw a banner, and leaves the packets unacknowledged for the app to collect. It
used to save its whole state file at the end of a round, which put the copy it had loaded back over
anything the app had saved in the meantime.

If the App Group is unavailable, the extension falls back to a directory inside its **own**
container, not the app's. That is a second private copy that is always behind, and it looks exactly
like a slow process. Both processes log which container they resolved.

<!-- COPY END 8aa03a7e -->
