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
