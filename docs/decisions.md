---
title: Decisions
layout: default
nav_order: 11
---

# Decisions

{: .no_toc }

Started fresh on 2026-09-20. The old log ran to four thousand lines, described behaviour the build no
longer had, and was cited back at Griff as though it were his own ruling. It is
[archived](archive/decisions-2026.md) and may not be used to answer a question about the app.

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

**RULED 2026-09-20 by Griff**, after the opposite was found in the build: *"I think the ideal design
is that a user provides only what another user is allowed to see. Ideally, they cannot retrieve
something they will not be allowed to read."*

**What was wrong.** The round collected every entry this device had not yet sent — across every room
and every solo — sealed them into one body, and wrapped that body's key for every peer. The
addressing was per recipient and correct; the contents were global. So a member of any one room
received every entry their peers wrote everywhere else, sealed, and kept it on disk. History repair
leaked the same history a second way: `Replica.fill` served a named author's log *whole*, ignoring the
room the request named, and the answer never consulted the asker's history floor, so a member invited
from today was sent the entire backlog they had just been refused. Measured before any change: a
three-member fixture put a second room's entries on a device that was never in it, and a forward-only
joiner held nine sealed entries from before they were let in.

**How it works.** `AppSession.mayReceive` answers, for one entry, which peers may have it: a room's
members and its founder; a joiner whose invitation shares history; a former member only up to the
epoch their removal or departure was sealed at; a wall post only to that wall's readers; a comment
written under a closed standing only to the post's owner; an access change also to the person it
names. `addressed(_:)` groups peers by identical audience and the round writes one packet per group. A
device that cannot yet read a room — a joiner holding only the epoch they were let in at — addresses
the person who let them in, and nobody else.

**Saying what will not be sent.** A member's log is one chain per device across every room, so a peer's
clock names positions they will never be given, and gap detection reads those as holes. A sender
states the positions it is withholding in the same packet (`SyncEngine.Body.withheld`); the reader
records them in `PersistedState.elsewhere` and stops asking. Repair answers carry the same list as
`RepairAnswer.elsewhere`. Without it, both fixes would have left every member asking every hour for
history nobody will ever hand over.

**What it costs.** A member in four rooms writes up to four packets a round where they wrote one. The
writes are to the member's own private database, they are small, and `acknowledge` deletes each packet
once every addressee has it. `WriteBudget.provisionalDailyCeiling` is a number this repo invented and
is not a reason to widen an audience.

`RepairScopeTests` holds the three cases: no entry from a room the reader is not in, nothing below a
joiner's floor, and no permanent phantom hole afterwards.

### The envelope names only the conversation it belongs to

**RULED 2026-09-20 by Griff:** *"I'd like you to fix the problem where the whole count/existence is
legible."*

**What was wrong.** An entry's payload was sealed, but the envelope around it was not, and it said
too much. `AppSession.append` stamped `replica.frontier` — every log the writing device held, across
every room and Outpost, as person and device. One message from a room you share told you how many
other conversations its writer keeps, who is in them, and how far each had got. A single entry was
enough to draw its writer's social graph. Three other things went to every peer for the same reason:
the public keys of everyone this device had ever met, their device certificates, and the list of
whose Outposts this member follows. A repair request and its answer carried heads taken across every
conversation, so asking one peer to fill a hole told them the top position of every log involved,
everywhere.

**How it works.** A clock is the frontier of its own entry's room. Keys, certificates and revocations
are cut to the people the packet itself names — the authors of the entries inside it and the members
of the rooms those entries belong to. A wall wish is written to the one peer it is about, so it says
"I want yours" and never names a third party. Repair heads are taken inside the room or the Outpost
the request names. Peers owed nothing in a round no longer share a packet, because sharing one was
itself an introduction.

**What it costs.** Nothing on disk or on the wire changed shape, so an older entry still decodes and
still verifies. The relay sees less correlation and more structure: a member who talks in four rooms
writes four records where they wrote one, and the sizes of those records are the sizes of their
rooms. That trade is stated in [the crypto brief](crypto-brief.md#what-the-relay-is-actually-handed).

**What is still legible.** A position number is counted per device across every conversation, so the
numbers alone still say roughly how much their writer writes — closing that needs a separate hash
chain per conversation, which would let a device drop or reorder its own history without anyone being
able to tell. And until a peer has settled what it is owed, a repair request can name a position that
turns out to belong to another room, because the asker genuinely cannot tell which room a position it
does not hold belongs to. Both are in [the inbox](inbox.md).

`EnvelopeLeakTests` holds five cases, and each one fails with its fix reverted.

## The log

### A device keeps one log per conversation

**RULED 2026-09-21 by Griff**, after asking what a device-wide log bought: *"If we do per room, why does
that scope matter?"* It didn't — see below — and he answered *"I do believe that is enough."*

**What it was.** A device kept one hash-linked log across every room, solo and Outpost, numbered from
one forever. The position was in the clear on every entry, so one message told its reader roughly how
much its writer wrote everywhere else.

**What it bought, measured.** Scoping the sorter's dependencies per room and running the whole suite:
nothing reads order across conversations — no fold, no screen, no rule. The only thing lost is that
somebody sharing two rooms with a writer can no longer cross-check the two numberings, which attestations
replace with every member of the room.

**How it works.** `FeedKey` names author, device and conversation. `Entry.seq` counts within that, and
`Entry.previous` links to the entry before it there. The fold got three and a half times faster at three
hundred entries across four rooms, because the sorter no longer chases dependencies between conversations.

**What it costs.** A count per conversation can go backwards where a count per device could not. A device
that deleted a room, relaunched, was invited back and relaunched again would count from one below its own
record of what it had sent, and the message would never leave. Its own head in each conversation is
therefore saved and never goes backward (`PersistedState.ownHeads`). A reinstall — keys kept, data lost —
still reaches the same place if it writes before its history comes back; that is in
[open questions](open-questions.md).

`EnvelopeLeakTests.positionsCountOnlyThisConversation` fails on the commit before the change.
`DeletingARoomTests.comingBackDoesNotReuseANumber` fails five times in five without the saved head.

### A conversation is named by what kind it is

**RULED 2026-09-21 by Griff:** *"yes. I love an enum."*

`ConversationID` is `.room(UUID)`, `.solo(UUID)` or `.outpost(ParticipantID)`, and every entry carries
one — never nil. A post on your own Outpost used to have no room at all while a comment on it named the
Outpost, so one conversation had two spellings; that is gone, and so is `wallOf`. A conversation's kind is
read from its id, never from a profile entry written into it. Every switch over it is exhaustive, so a kind
left out is a compile error. Its bytes are pinned by hand in `ConversationIDTests`.

**What it costs.** The address used to tell a post (no room) from wall machinery (the wall's id), so a
future plumbing type stayed hidden from an older build. An unknown type on an Outpost now draws, as it
always has in a room.

**Two refusals it made necessary.** Posting straight onto somebody else's Outpost is refused, and so is
making a key for an Outpost this member does not own — without the second, a post aimed at another
Outpost minted a fresh key for it.

### Members vouch for each other's logs

**RULED 2026-09-21 by Griff**, on three questions: attestations carry **no time** (*"No timestamp"*); a
contradiction is **recorded, not an accusation**; and a contradiction about a member who has asked to be
restored is kept quiet, because *"if somehow someone fakes a recovery, it's still there, and has the hold."*

A packet with entries carries, for each log in those rooms, the position and hash of its newest entry,
only where every recipient may already have that entry. A mismatch is recorded as a contradiction, never
as a fork, and this device asks the attester for their copy; an entry signed by the author is the proof,
and the fork machinery records it.

**PROPOSED** within that: attestations carry no signature, because the packet is already authenticated to
its sender and the proof of a lie is the author's signed entry, not a claim about one.

### A seal is always bound to its writer

**PROPOSED 2026-09-21.** The fallback that opened a payload sealed without its writer's feed key is
deleted, and the writer is required at every seam. It existed so entries sealed before 7 September still
opened; after the wipe no honest client makes one. The fallback that tried every key this device held
when an entry's own conversation's key failed is deleted too — it let an entry's envelope name one
conversation while its payload was sealed for another.
