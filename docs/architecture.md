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
that device's log, and stamped with a vector clock naming only the conversation it was written in.
Any two devices holding the same entries fold them into the same result without talking to each other.

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
One round writes one packet per audience—the people owed exactly the same entries share one—
regardless of however many log entries each carries.
Nobody is ever handed a packet holding a conversation they are not in.

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

### Who a Packet Is For

A device hands over only what its reader is allowed to read.
Not "sends it sealed and trusts the app not to draw it"—does not send it.

Before a round writes anything it asks, of each entry, who may have it:

- a room's entry goes to that room's members and its founder
- a joiner gets it if their invitation carried the history, and nothing older than their floor if it did not
- somebody removed or gone gets nothing sealed after the key turned on them
- an Outpost post goes to that Outpost's readers
- a comment written under a closed standing goes to the post's owner alone, and to nobody else
- a change to who may read an Outpost also goes to the person it names, so they learn of it

People owed exactly the same entries share a packet. Everybody else gets their own.

The same rule governs what rides alongside the entries.
A packet carries the public keys and device certificates of the people it actually names—
the writers of the entries inside it, and the members of the rooms those entries belong to—
and nobody else. A member's address book is not a thing anybody else gets a copy of.
A wish to be told about somebody's Outpost is written to that person alone,
so it says "I want yours" and never names a third party.

A device that cannot yet read a room—a joiner holding only the key they were let in at—
writes to the person who let them in, and to nobody else.

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

The repairer answers a repair request with the entries it holds **from that conversation only**,
and names the ones it does not,
so the requester can discern "sent and not arrived" from "nobody has it".
It never hands over an entry from somewhere else, and never one sealed below the asker's floor.

This same mechanism is used for history backfill for new members by rooms which allow it.

There is a wrinkle, and it is worth understanding, because it shapes the answer.
A device keeps **one** log, not one per room.
Every entry it writes goes into that single log, numbered 1, 2, 3, forever.
The room is a label on the entry.
That is what makes the numbering unbroken, and an unbroken chain is what makes tampering visible.

The price is that positions are shared out among every room that person is in.
Your view of somebody's log might hold 5, 9 and 12.
You will never be given 6, 7, 8, 10 or 11—they belong to conversations you are not in—
but a gap is a gap, and nothing in the numbers says which.

So a repairer states, in the same packet, the positions it is **withholding**.
The asker writes them down and stops asking.
Without that, every member would ask every hour, forever,
for history nobody will ever hand over.

### A deleted room leaves its numbers spent

A member's log is shared across every room they are in. Deleting a conversation they are no
longer part of removes entries from the middle of that log, and the repair above would read the
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

## Nothing a Render Reads May Do Work

SwiftUI evaluates a view's body many times a second, and anything the body reaches runs that often.
So nothing a body can reach is allowed to open a seal, derive a key, or write.

Three rules hold that line.

**What is opened is opened once.** A room's roster, who is out of a room, who has read what, who is
being reported, and who may see an Outpost are all built by opening entries. Each is cached beside
the fold (`cachedRosters`, `cachedOutOfRoom`, `cachedReadEvidence`, `cachedReporting`,
`cachedOutpostAccess`), and `foldChanged()` clears the lot. **Any new state those caches read needs
`foldChanged()` too**—nothing fails if it is missed, the cache just goes quietly stale, which looks
exactly like a message that did not arrive.

**Nothing a preference decides belongs in those caches.** Hiding, blocking and delivery marks change
without a fold, so they are applied to the cached result on every read instead of baked into it.

**Reading never mints.** A view reads `codeForSharing`, which is a stored string;
`prepareCodeForSharing()` mints the nonce behind it, outside any render. Anything that writes to
observed state triggers a render, and a render that writes is a loop.

Pairwise secrets are cached for the life of the session and never cleared. Deriving one is an X25519
agreement and an HKDF; `peers()` asks for one per peer, on a path every conversation render reaches.
Keeping them is safe because a `ParticipantID` is the SHA-256 of the keys its secret comes from, so
an ID can never come to mean different keys. Only a restore changes this member's own identity, and a
restore rebuilds the session.

`ProjectionCostTests` holds every screen read to a per-call limit, because a body may make several
calls and a 60fps frame is 16,700µs. The conversation screen's two reads are over that limit and are
recorded as exceptions with their numbers; see
[the inbox](inbox.md#the-conversation-screen-still-costs-3500µs-a-read).

## What a Round Assumes About Its Own Order

`AppSession.sync(through:media:mode:)` is one long function on purpose. A round is a sequence, and
most of what has gone wrong in this app went wrong because two statements ran in the wrong order.
Splitting it into small pieces would hide the sequence, which is the only thing about it worth
reading.

These are the orderings the round depends on, and what holds each one.

| The step                                                                      | What it assumes already ran                                                                                                      | Held by                                   |
|-------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| `issuedGrants.insert` when `packetsWritten > 0`                               | the grants rode a packet that landed, and a failure threw before this line                                                       | `grantsAreOnlyMarkedIssuedIfTheyWent`     |
| `roomsWithUnsentMessages.subtract` only when `sendFailure == nil`             | a batch that failed still owes its bell                                                                                          | `partialFailureIsNotLoss`                 |
| `storage.log.append(owed)` before `session.acknowledge`                       | an acknowledgement is a promise the entry is on disk, so a failed write must throw first                                         | `aRefusedWriteLeavesThePacketOutstanding` |
| `entriesNotWrittenDown` carried into the next round                           | `integrate` already put them in the replica, so the next round has nothing to write and would acknowledge an entry no disk holds | the same test                             |
| `syncedFrontier.observe` only for `report.written`                            | an entry counts as sent only if its packet landed                                                                                | `partialFailureIsNotLoss`                 |
| `outstandingPackets` filtered by `pendingDeliveries`, then this round's added | a collected packet stops counting as undelivered before new ones go in                                                           | `collectionIsReportedWhenItHappens`       |
| `viewMayBeStale` set after the peer loop                                      | the next round's `withholdsKeys` reads what this round refused                                                                   | `RemovalTests`                            |
| `persisted.certificates` after the peer loop                                  | a certificate that arrived this round is saved                                                                                   | nothing                                   |
| `peersLastRound` assigned after `metSomebodyNew` is computed                  | "new" means new since the previous round                                                                                         | nothing                                   |
| `saveState()` last                                                            | every change above it is in the file                                                                                             | nothing                                   |

The three unheld rules are ordinary "do this last" rules. Breaking one leaves a stale file rather
than losing history. They are listed so the next person to move a line knows which were tested and
which were only read.

## Two Processes, One Container

The app and the notification service extension are separate processes sharing one App Group
container. The app writes the log and the state file under a cross-process lock. A Swift actor
serializes work inside one process and does nothing at all across two, so the lock is the only thing
holding them apart.

**The extension writes neither.** It opens the container through the `readOnly` view of its
`SessionStorage`, keeps what its round collects in memory just long enough to draw a banner, and
leaves the packets unacknowledged for the app to collect properly. A second writer would put the copy
it loaded back over anything the app saved in the meantime.

If the App Group is unavailable, the extension falls back to a directory inside its **own**
container, not the app's. That is a second private copy that is always behind, and it looks exactly
like a slow process rather than a broken one. Both processes log which container they resolved, so
`appGroup=false` in the log is the answer.
