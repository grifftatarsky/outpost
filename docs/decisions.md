---
title: Decisions
layout: default
nav_order: 11
---

# Decisions

{: .no_toc }

Every decision that binds the build, and why. An older log is [archived](archive/decisions-2026.md)
and may not be used to answer a question about the app.

An entry belongs here only when it binds: a rule about who receives what, a shape that cannot change
without breaking something, a trade-off taken on purpose. Every entry says who decided it.

- **RULED** — Griff decided it. It is a constraint.
- **PROPOSED** — Claude decided it, absent a ruling. It is a **default, not a constraint**, and may
  never be cited as a reason not to do what Griff asked for.
- **FACT** — a property of the platform or the protocol that nobody chose.

An entry that stops being true is deleted, not superseded. The code and the tests are the record of
what the app does; this file is only the record of why.

1. TOC
{:toc}

## Sync

### A device sends only what the reader is allowed to read

**RULED 2026-09-20 by Griff:** *"a user provides only what another user is allowed to see. Ideally, they
cannot retrieve something they will not be allowed to read."*

`AppSession.mayReceive` answers, for one entry, who may have it: a room's members and its founder; a
joiner whose invitation carried the history, and nothing below the floor of one whose invitation did
not; a removed or departed member only what was sealed before the key turned on them; an Outpost's own
posts only its readers, a comment written under a closed standing only the post's owner, and a change
to who may read an Outpost also the person it names. `addressed(_:)` groups peers by identical audience
and the round writes one packet per group. A device that cannot yet read a room writes to the person who
let it in, and nobody else.

The same rule governs what rides beside the entries: public keys, device certificates and revocations
only for the people a packet names; a wish to be told about an Outpost only to its owner; repair heads,
gaps and attestations only inside the conversation they are about.

**What it costs.** A member in four rooms writes up to four packets a round. The writes go to the
member's own private database, they are small, and each is deleted once every addressee acknowledges it.

`RepairScopeTests`, `EnvelopeLeakTests`.

### A reader told what it will not be given stops asking

**PROPOSED 2026-09-20.** A member invited from today sees an existing member's log start partway through,
and would ask for the rest forever. The sender states, in the same packet, the positions it is
withholding (`SyncEngine.Body.withheld`), and a repair answer says the same (`RepairAnswer.elsewhere`);
the reader keeps them in `PersistedState.elsewhere` and stops asking.

## The log

### A device keeps one log per conversation

**RULED 2026-09-21 by Griff:** *"I do believe that is enough."*

`FeedKey` is author, device and conversation. An entry's position counts from one within its
conversation, and `previous` links to the entry before it there. So no number on any entry says anything
about what its writer does elsewhere, and a clock names only its own conversation. Nothing folds,
draws or decides by order across conversations — that was measured before this was built.

**What it costs.** A count per conversation must never go backwards, or a device writes at a position
it already used and its message never leaves. This device's own head in every conversation is saved
(`PersistedState.ownHeads`), survives deleting the conversation, is kept in the device's summary record
in iCloud so it survives a reinstall, and moves forward whenever this device sees its own writing come
back from anywhere.

`EnvelopeLeakTests.positionsCountOnlyThisConversation`, `DeletingARoomTests.comingBackDoesNotReuseANumber`.

### A conversation is named by what kind it is

**RULED 2026-09-21 by Griff:** *"yes. I love an enum."*

`ConversationID` is `.room(UUID)`, `.solo(UUID)` or `.outpost(ParticipantID)`, and every entry carries
one. A post on your own Outpost is in `.outpost(you)`. A conversation's kind is read from its id and
nothing else. Every switch over it is exhaustive, so a kind left out does not compile. Nobody can post
straight onto somebody else's Outpost, and no device makes a key for an Outpost it does not own.
`ConversationIDTests` pins its bytes by hand.

**What it costs.** An entry of a type this build does not know is drawn, on an Outpost as in a room.

### Members vouch for each other's logs

**RULED 2026-09-21 by Griff**, on three questions: no time (*"No timestamp"*); a contradiction is
recorded, not an accusation; and one about a member who has asked to be restored is kept quiet, because
*"if somehow someone fakes a recovery, it's still there, and has the hold."*

A packet with entries carries, for each log in those rooms, the position and hash of its newest entry,
only where every recipient may already have it. A mismatch with what this device holds is a
contradiction: recorded, never called a fork, and followed by asking the attester for their copy. An
entry signed by the author at that position is the proof, and the fork machinery records it.
Unexplained contradictions show on the Integrity screen.

**PROPOSED** within that: an attestation carries no signature. The packet is authenticated to its
sender, and the proof of a lie is the author's signed entry, not a claim about one.

`AttestationTests`.

### A seal is always bound to its writer

**PROPOSED 2026-09-21.** A payload is sealed with its room, epoch and writer's feed key as associated
data, and opens only with all three. An entry opens only under the key of the conversation it names.

### A reinstall is the same device, if it is still correctly identified

**RULED 2026-09-21 by Griff:** *"A reinstall should become the same device - if it's still correctly
identified."*

**RULED 2026-09-21 by Griff:** *"Keep the log and state out of backups. And wait only for its own
record."* A restored device comes back as a reinstalled one does, holding its keys and nothing else,
and neither writes anything, in any conversation, until it has read its own records back from iCloud.

**PROPOSED 2026-09-21:** a device is correctly identified when three things hold. Its device key is in
this device's keychain, stored so that it never leaves this device. The key is stored with the member
it was made for. And no removal among the member's devices names it. A key made for another member,
or one with no owner found by a member who is new to this device, is dropped, and the device enrolls
as a new one. A device that reads its own removal enrolls as a new one. What this rules out: a new
phone restored from a backup being the old phone, and one device key answering for two members.

**PROPOSED 2026-09-22:** each device keeps two records in iCloud. The **summary** holds its position
in every conversation, including ones it deleted, the room keys it holds, the certificates and
removals of the member's devices, the people it knows, the member's preferences, uploads left for
others and departures already answered; and, for the device itself only, which rooms have greeted
the member, how the room list is arranged and how far each conversation has been read. The **entries**
record holds every entry the device wrote. The summary stays small however much is said; the entries
record grows with it, and Apple documents a record as holding at most 1 MB. What it costs: a second
record write whenever this device writes, and one push to the member's other devices for each.

**PROPOSED 2026-09-22:** a round sends an entry of this device's own only once a saved summary counts
it, so the summary is never behind anything another member holds. What it costs: a message waits for
one iCloud save before it leaves, not measured; and if the summary cannot be saved, nothing this
device writes leaves. A message held this way is drawn as not yet gone. The hold is on from the first
round of a launch, before device sync has attached (`AppSession.recordsAreExpected`). Devices on the
rig's directory mailbox have no Apple Account, keep no records and hold nothing back.

**PROPOSED 2026-09-22:** every start reads the device's own records, not only a reinstall's, and moves
forward to anything they hold that the device does not. Positions only ever go forward, whatever
told it. When the record was ahead, the History check says so, because it means another copy of this
device was writing.

**PROPOSED 2026-09-22:** of two certificates for the same device key, the earlier decides, whatever
order they arrive in. A reinstalled device issues itself a certificate before it has read its old
one, and without this its own earlier entries would stop verifying.

**What a reinstall loses.** Drafts, invitations it sent that had not finished, repairs in progress,
what the History check had noticed, and every photo it had collected: a photo lives only on the
devices that collected it, and a reinstall deletes this device's copies. A restore brings photos back,
because they stay in backups.

`ReinstallTests`, `EarliestCertificateTests`, `TheDeviceSyncFakeTests`, `IdentityStoreTests`,
`BackupExclusionTests`, and in the app-bundle suite `KeychainTests`.

**Proved on two Apple Accounts 2026-09-22.** On the rig, the app was deleted and reinstalled on
alpha (account A). It found its keys and nothing else, read back both of its records, knew its place
in both of its conversations and carried on at the next position. Quad on beta (account B) received
what it wrote and logged no fork. Quad's next message reached it, and the room's history came back.
Before that, a copy of alpha that `xcodebuild` had cloned wrote as the same device; alpha then found
its record one position ahead in one conversation and moved forward before writing.

**PROPOSED 2026-09-21:** "state" is everything that says what the log holds or where it came from: the
state file, both sync engines' saved state, and the learned list of other members' mailboxes. Left in
backups, the engines' state would tell a device with an empty log that it had already fetched
everything. Photos stay in backups: each is sealed, and a sender's upload is deleted once every
recipient has collected it, so a device that loses its copy has nowhere to fetch it again. The
pictures a member chose for themselves or for somebody else stay too, because nothing could bring
them back. `BackupExclusionTests`; on a simulator on 2026-09-21 the log, the state file, the engine's
state and the mailbox list each carried the exclusion after one launch.

### A key turn a removal owes is found in the log

**PROPOSED 2026-09-21.** A device that removed somebody from a room, or took its Outpost from somebody
it had let in, turns that conversation's key. Every full round it reads what it still owes from the
log as well as from the state file: a removal it wrote, still sealed under the newest key it holds, in
a conversation it is still in. Losing the state file does not forget the turn. What this rules out:
any other device, of the member or anybody else, finishing a turn another device owes, because two
turns at once write two secrets for one epoch. `OwedKeyTurnTests`.
