---
title: Architecture
layout: default
nav_order: 2
---

# Architecture

{: .no_toc }

How a message gets from one phone to another, with no Outpost server involved, only your own iCloud!

This page covers the general functionality of the application.  
It tells you what each key is/does, what it is derived from and what an attacker in each position could see.  
It is recommended to read Outpost's [Cryptography Brief](crypto-brief.md), which is an explanation of `CarpenterKit/Crypto`.

1. TOC
{:toc}

## The Log

The Log is the basis of how group messaging (and Solo messaging, and Outposts) function securely and privately.  
Everything a member does is a log **entry**: a message, a reaction, a room rename, an admission, a read
receipt. Each log entry is signed by the writing device, linked by hash to the one before it in
that device's feed, and stamped with a vector clock. Any two devices holding the same entries fold
them into the same result without talking to each other.

Importantly, a log entry's payload is sealed under the room's **epoch key**. The payload's type, version, and text are
inside the ciphertext; **only** the epoch number sits beside it. The log entry's author, device, position,
clock, time, and room are outside that seal, and the whole entry, when sent, travels inside a packet resealed for its recipients.  

So, the transport cannot tell a message from a reaction. That's an important quality; as this travels through iCloud, Outpost's philosophy demands iCloud can't tell what kind of comm is being sent.

The other important philosophical agreement here: no member can ever remove another member's entry from the log (without agreement, which is not yet implemented). A deletion is an entry too—Outpost uses tombstones.

## Joining a Room

A room's key is a chain: each epoch's link wraps the previous,
so somebody holding the current key, and every link, can unwind an entire conversation.
There are two types of invitations in Outpost.
An invitation can carry the history and hand over all the links.  
An invitation can be sent without the history, meaning no links,
and that kind of invite turns the key as the new member joins.
It never hands over the older keys, so the new member cannot read the history.
It stays sealed.

In the second scenario, the earliest epoch a member can open is recorded in the log,
on admission. Every member's app reads it. One member turns the key,
as two turning it at once would write two different secrets for the same epoch (which would be bad).
Until that earliest epoch is recorded, every member withholds the room's keys from the new member.

As there is no stored list of who is in a room,
the app replays the room's log entries and applies the ones it can open.
A member who joined today can open none of the old ones,
so that replay function alone would show them an empty, nameless room.
To combat that, the member who admitted the new member provides that information as a new log entry when the new key is set. That entry contains:
- Who is in it
- Who started it
- What it is called
- The admission and approval settings

That restating entry sets allows the new member to get the shape of the room they've joined for their UI.
It's a claim of the room state, not proof, as it comes from the admitter.
Once new messages flow, the proper shape is proved.

## The Mailbox

Each member owns an `Outbox` zone in their **own** iCloud private database,
shared with their peers.
To send, a device writes one **packet** into its own Outbox,
the log entries within sealed under a newly-minted (fresh!) content key.
That key is wrapped separately, for each recipient,
addressed to a tag, aka, an address, derived from a secret the two members share.
One round writes one packet, regardless of however many log entries it carries.

Recipients read the zone's change feed—CloudKit's changelog
(See [Notifications](#notifications) for how they know to go get a new change).
Outpost does not use a query here—CloudKit's query index is *eventually* consistent,
so a newly written record may not come back from a query.
The change feed is consistent and needs no schema (right tool, right purpose).

After read,
the recipient acknowledges receipt by removing its tag from the packet's list of recipients.
When the list of recipients is empty, the packet is deleted.
Like an actual mailbox—cough, the logo—the Outbox only holds content to be delivered.
It does not retain or store history. Send-and-clean-up, to minimize risk and usage.

It is important to note that **only the sender's iCloud is used for the Outbox**.
The public CloudKit database is *never used*.
This is part of Outpost's philosophy—the developer has no data on users, nor really any interaction with users.
It is also so the developer is not subsidizing users and paying more and more as the app gains popularity.
A win for privacy, security, and a win for the developer's credit score.

### Rotation and Lookback

Outpost addresses—tags—are sort of a space time construction, to make it easier (hopefully) to understand.
Each user has multiple addresses. One per person they talk to, per day.
Each one of their addresses lasts a single day,
a fixed 86,400-second bucket (`SyncSession.tagWindow`),
not a rolling day.
This is best explained with an example!

It's October 5th.
Tomorrow, shockingly, is the 6th.
A packet is written into the Outbox at 23:50 on the 5th.
That packet is at the reader's address derived from October 5th.
So, a reader collecting it at 00:10 on the 6th will not find it under the sixth's addresses.

Because of that, the reader looks under eight addresses, rather than one:
the last seven days, plus tomorrow's,
in case the writer's clock is a little ahead of its own.
The reader acknowledges receipt under whichever address the packet was found at.

### Historical Repair

Entries in the log are numbered from one, without gaps,
and every entry's clock says what its author had seen.
So, a device can list *exactly* which positions it is missing.

Executing a repair is a request to a conversational member—the repairer—inside the sealed packet.
The request contains a list of gaps, the requesting device's heads,
and the conversation (room or solo) which needs repair.

The repairer answers a repair request with the entries it holds,
and names the ones it does not,
so the requester can discern "sent and not arrived" from "nobody has it".  

TODO: God. Uncovered a massive security and privacy risk Claude created. Yikes. This section will need updating.

This same mechanism is used for history backfill for new members by rooms which allow it.

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

## Device sync

A member's own devices converge separately, through `CKSyncEngine` over a `SiblingFeeds` zone in the
member's private database. There is one record per device, holding that device's entries, the device
certificates, the epoch keys it holds and the member's preferences.

The record is sealed on the device before it is written: ChaChaPoly under a key derived from the
identity with HKDF-SHA256, with the member and the writing device as associated data, so a record
cannot be replayed into another device's slot. `EntrySync` carries `SealedSiblingFeed` and nothing
else, so the unsealed type cannot reach a transport.

**The app seals it rather than using `CKRecord.encryptedValues`.** Apple's encrypted fields are
end-to-end only when the member has Advanced Data Protection on; otherwise Apple holds the keys. And
the CloudKit service key lives in iCloud Keychain, which is exactly what is missing when somebody
restores from a recovery key. The seal is under the identity, and the recovery key is the identity.

The app tells the engine when to sync instead of letting it schedule itself
(`automaticallySync = false`). Left to schedule itself, an explicit `fetchChanges()` returned in
milliseconds without asking the server anything.

## Notifications

There are three subscriptions, each scoped to a record type. One of them is visible.

| Channel      | Database          | Kind                       | Record type   | Push                   |
|--------------|-------------------|----------------------------|---------------|------------------------|
| `deviceFeed` | private           | `CKDatabaseSubscription`   | `SiblingFeed` | silent                 |
| `inbox`      | shared            | `CKDatabaseSubscription`   | `SyncPacket`  | silent                 |
| `bell`       | private, own zone | `CKRecordZoneSubscription` | `MessageBell` | alert, mutable content |

The transport cannot see inside a packet, so the packet channel wakes the app and shows nothing. A
**bell** is a separate record a sender writes into the recipient's zone only when it has left a real
message there for them. Nothing else writes that record type, so nothing else can produce a banner.

The notification service extension opens the message on the device and replaces the generic line with
the room and the sender. It writes nothing to the server.

**Turning notifications off is a supported way to use the app.** Every channel speeds delivery up;
none of them is how delivery happens. The app syncs when it comes to the front, while a conversation
is open, and on pull to refresh. With notifications off it works, and is not realtime while closed.
The app never treats that as an error.

## The seams

`CarpenterKit` depends on nothing but Foundation. Everything platform-shaped sits behind a protocol,
such as `Mailbox`, `KeychainStore`, `LogStore`, `DocumentStore`, `MediaStore`, `EntrySync`,
`MediaScreen`, `AccountRegistry` and `Clock`, so the
logic above it runs in tests without an account, a container or an entitlement.

## Where the source lives

One module is one concern. Inside `CarpenterApp`, `AppSession` is split into a file per epic, so a
review can be scoped to one:

| File                             | Holds                                                                                     |
|----------------------------------|-------------------------------------------------------------------------------------------|
| `AppSession.swift`               | the type, its state, the fold cache, `append`, `refresh`, epoch persistence               |
| `+Identity`                      | bring-up, restore, names, avatars, nicknames, the recovery key, devices                   |
| `+Membership`                    | invitations, admissions, the solo check, room access, removal, leaving                    |
| `+Verifying`                     | comparing codes with somebody after the introduction                                      |
| `+Messaging`                     | sending, editing, reading, search, read receipts, hiding                                  |
| `+DeletingRooms`                 | deleting a conversation and finishing a deletion that was cut off                         |
| `+Outpost`                       | the wall: readers, posts, comments, reactions, what is new                                |
| `+Attachments`                   | photos and clips out and back, and the sweep                                              |
| `+Notifications`                 | notification levels, badges, Do Not Disturb                                               |
| `+Etiquette`                     | the privacy check-up, blocking, what is announced into a room                             |
| `+Supporter`                     | the free year and the Supporter badge                                                     |
| `+Sync`, `+DeviceSync`, `+Peers` | the round, the feed between a member's own devices, and who can be reached with which key |
| `+HistoryRepair`                 | filling a hole, and the reverse channel                                                   |

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

## Nothing a render reads may do work

TODO: This whole section is historical crap rather than just how it works.

SwiftUI evaluates a view's body many times a second, and anything the body reaches runs that often.

- **`roster(of:)` opened every membership entry in the room**, a ChaChaPoly open and a JSON decode
  each, and `AppRootView.body` reached it. The main thread measured 100% inside it. It is cached now
  beside the other opened reads (`cachedRosters`, `cachedOutOfRoom`, `cachedReadEvidence`,
  `cachedReporting`, `cachedOutpostAccess`), and `foldChanged()` clears them all. **Nothing that
  depends on a preference belongs in those caches**: hiding, blocking and delivery marks change
  without a fold, so they are applied to the cached result on every read.
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

`ProjectionCostTests` holds every screen read to a per-call limit, because a body may make several
calls and a 60fps frame is 16,700µs. The conversation screen's two reads are still over the limit
and are recorded as exceptions with their numbers; see
[the inbox](inbox.md#the-conversation-screen-still-costs-3500µs-a-read). **Any new state those caches
read needs `foldChanged()` too.** Nothing fails if it is missed; the cache goes quietly stale.

## What a round assumes about its own order

TODO: Again, historical, and not a good justification for a 270 line method, wtf.

`AppSession.sync(through:media:mode:)` is about 270 lines in one function on purpose: most of what has
gone wrong in this app went wrong because two of its statements ran in the wrong order. It was read
line by line on 2026-09-14. This is what each ordering assumes and what checks it.

| The step                                                                      | What it assumes already ran                                                                                                      | Checked by                                |
|-------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| `issuedGrants.insert` when `packetsWritten > 0`                               | the grants rode the first packet, and a failure there threw before this line                                                     | `grantsAreOnlyMarkedIssuedIfTheyWent`     |
| `roomsWithUnsentMessages.subtract` only when `sendFailure == nil`             | a batch that failed still owes its bell                                                                                          | `partialFailureIsNotLoss`                 |
| `storage.log.append(owed)` before `session.acknowledge`                       | a failed write throws, so nothing is acknowledged                                                                                | `aRefusedWriteLeavesThePacketOutstanding` |
| `entriesNotWrittenDown` carried into the next round                           | `integrate` already put them in the replica, so the next round has nothing to write and would acknowledge an entry no disk holds | the same test                             |
| `syncedFrontier.observe` only for `report.written`                            | an entry counts as sent only if its packet landed                                                                                | `partialFailureIsNotLoss`                 |
| `outstandingPackets` filtered by `pendingDeliveries`, then this round's added | a collected packet stops counting as undelivered before new ones go in                                                           | `collectionIsReportedWhenItHappens`       |
| `viewMayBeStale` set after the peer loop                                      | the next round's `withholdsKeys` reads what this round refused                                                                   | `RemovalTests`                            |
| `persisted.certificates = knownCertificates()` after the peer loop            | a certificate that arrived this round is saved                                                                                   | nothing                                   |
| `peersLastRound` assigned after `metSomebodyNew` is computed                  | "new" means new since the previous round                                                                                         | nothing                                   |
| `saveState()` last                                                            | every change above it is in the file                                                                                             | nothing                                   |

The three unchecked rules are ordinary "do this last" rules. Breaking one would leave a stale file,
not lose history. They are listed so the next person to move a line knows which were tested and which
were only read.

## Two processes, one container

TODO: Also history. Not documentation.

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
