---
# COPY BEGIN f917ea56 [HUMAN REVIEWED, UNVERIFIED]
title: Open questions
layout: default
nav_order: 2
---

# Open questions

{: .no_toc }

Only what needs Griff's answer, each with a recommendation. An answered question leaves here: the
answer goes to [Decisions](decisions.md), the work to the [Roadmap](roadmap.md), and anything else
worth keeping to the [Inbox](inbox.md).

1. TOC
{:toc}
<!-- COPY END f917ea56 -->

<!-- COPY BEGIN 754e3ba8 [NEEDS HUMAN REVIEW] -->

## A thief can still fill the places a member's new devices need

Since 2026-11-04 every device that signs has its own allowance in a registry, so a stolen phone
cannot take a place of the member's own phone, and her removal of it and her restore are never
refused for want of room. But a stolen phone that still counts can approve 16 devices and have each
of them approve 16. That uses the 256 places the lineage has, and every contact then refuses a device
the member approves next, until she restores with the recovery key. Removing the stolen phone does
not give the places back, because if a removal did, a thief could approve and remove in turn and grow
the registry without end. Measured in a test on 2026-11-04 (two levels of 16 approvals, then the
member's phone approving a new one: refused); not run on the rig.

**Recommendation: let a removal that names the devices that stay drop every device it leaves out that
has written nothing this phone holds.** Dropping, not just stopping, keeps the registry bounded
however often a thief approves and removes, and a device that wrote nothing has no history to check.
It needs the replica to tell the registry which devices wrote what it holds.

<!-- COPY END 754e3ba8 -->

<!-- COPY BEGIN 2648f0dc [NEEDS HUMAN REVIEW] -->

## Nobody signs the link back to a room's older key

A room's key change carries a link: the old key, locked with the new one. The link only proves that
whoever made it held the new key, and every member does. So a member still in the room can send a
link with a wrong old key inside, and a phone that gets that one first keeps it and ignores the real
one.

What it costs that phone: it cannot read the room's history from before that key change. It does not
let anybody read anything they could not already read. Found by reading, 2026-09-26, not measured.

**Recommendation: build it.** The member who changes the key signs the link, and a phone takes a link
only with that member's signature. The app already decides who changes the key for each change, so a
phone can check it. It changes what a key hand-off carries.

<!-- COPY END 2648f0dc -->

<!-- COPY BEGIN 1b539bd8 [NEEDS HUMAN REVIEW] -->

## A remover who never said what they had seen can still cut everything

A removal names the last entry of each of the removed person's devices that the remover's phone holds,
and everything of theirs past that line stops counting, on Griff's ruling that the line is what the
remover's device had received. A modified app can name nothing. Since 2026-10-31 that cannot cut what
the remover's own phone had already named by hash in the room before the removal (a read receipt, the
heads a key change lists, a Solo answer), anything the removed person wrote before they left on their
own, or an invitation of theirs that another member had answered. What is still open: in an open
room, a member who never sent a read receipt, never changed the key and never answered a check can
remove somebody with an empty list, and every phone drops all of that person's words and everybody
they let in whom nobody else answered for. Nothing the remover signed earlier says otherwise, and the
dates and positions in the log cannot be used instead, because a removed person can sign a new entry
under a number they used in a room the remover is not in.

**Recommendation: build it.** Each device names the newest entry it holds from every device in a room
now and then, signed, the way a key change already does (for example on each read receipt, or once a
day per room). The line of a removal already reaches back to every entry the remover's earlier lists
named, so nothing else has to change. It changes what a read receipt carries, and costs 32 bytes per
device in the room each time: about 2 KB for thirty people with two phones each, worked out and not
measured.

<!-- COPY END 1b539bd8 -->

<!-- COPY BEGIN 8f4c521a [NEEDS HUMAN REVIEW] -->

## A phone with Advanced On Device Security on cannot collect while it is locked

Promise 2 says a message that arrives while the phone is locked is kept and joins the history at
unlock, so nothing is lost. The build collects nothing while locked, so a message older than nine
days is taken back before the phone ever sees it.

It cannot be met as written. To fetch, a phone needs the rotating addresses it fetches under, and
those come from the pairwise secrets in the keychain, which is exactly what the lock seals. iOS will
let the app write a file while locked; it will not let it read the keys it needs to ask for one.

Three ways out, and none is free:

1. **Keep the next few addresses in a file the phone can read while locked.** The phone could then
   fetch and spool the sealed bytes without opening them. The cost: somebody holding the locked phone
   learns which addresses in iCloud are this member's, which is the correlation the rotating
   addresses exist to stop.
2. **Let a sender hold a packet longer for somebody who has not collected.** No secret moves, but how
   long a packet waits becomes a signal about the recipient's phone.
3. **Accept it.** With the setting on, a message nobody collected in nine days comes back through
   history repair instead, and the member is told that is the trade.

**Recommendation: 3, and say so on the setting's page.** The setting already costs classic
notifications; a message older than nine days coming back the slow way is a smaller cost than
publishing the member's addresses to anybody holding the phone. 1 weakens the thing the setting is
for.

<!-- COPY END 8f4c521a -->

<!-- COPY BEGIN 5d82a14a [NEEDS HUMAN REVIEW] -->

## Outpost's own lock cannot seal the identity, because the other phones need it

Outpost's own lock now seals with a key wrapped by the code and by a key the Secure Enclave will not
hand over, so a copied file opens on no other phone
([Decisions](decisions.md#advanced-on-device-security-seals-what-this-phone-keeps-while-it-is-locked)).
That works for anything this phone alone keeps.

It cannot work for the identity. The identity lives in iCloud Keychain so the member's other phones
have it, and iCloud Keychain protects an item with the phone's own passcode. There is no way to ask
it for a code Outpost chose. So with Outpost's lock on and the phone's lock off, the identity is
protected by whatever the phone is protected by, and the rest is sealed by the code.

**Recommendation: say it on the page, in one line, and keep the choice.** Something like: *Outpost's
code seals what this phone keeps. Your identity stays with iCloud Keychain, which uses your phone's
passcode.* The alternative is to refuse Outpost's own lock unless the phone has a passcode, which
makes the setting nearly pointless, since the phone's lock is then available and stronger.

<!-- COPY END 5d82a14a -->
