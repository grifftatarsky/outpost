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
(`PersistedState.ownHeads`), survives deleting the conversation, and moves forward whenever this device
sees its own writing come back from anywhere.

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

{: .warning }
> **Not built.** What "correctly identified" means, and how a reinstalled device learns where it had
> got to before it writes, is in [open questions](open-questions.md).
