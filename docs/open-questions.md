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
not give the places back, because if a removal did, a thief could approve and remove one after the other
and grow the registry without end. Measured in a test on 2026-11-04 (two levels of 16 approvals, then the
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
they let in whom nobody else answered for. A removed member can do the same with the old key by
writing a clock that hides that they had read their own removal: a removal of the founder that names
only the founder's entries up to the member's own invitation ends the remover's invitation, and with it
the removal (found 2026-11-04). Nothing the remover signed earlier says otherwise, and the
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

<!-- COPY BEGIN 2983233d [NEEDS HUMAN REVIEW] -->

## A recording of iCloud still opens everything under the pair's secret

Since 2026-11-05 every key handed to a device is sealed with X-Wing, so a recording of iCloud cannot
later yield a room key or the words in a room unless ML-KEM-768 is broken too
([Decisions](decisions.md#a-key-handed-to-a-device-is-sealed-with-x-wing)). The pair's secret is still
X25519 between the two identities' agreement keys, and packets, receipts, links to each other's spaces,
photo copies and the comment copy for a wall's owner are sealed under it. Whoever records them and
later breaks X25519 learns who talks to whom, which rooms people share and when they wrote, and reads
the words of a comment or reaction left on somebody's Outpost from outside its room.

One way to close it gives each identity an ML-KEM key from the recovery secret and mixes an
encapsulation into the pair's secret. A KEM is not an agreement both sides can compute alone, so one
side still has to send the other a ciphertext, and the identity's new public key has to be in the
`ParticipantID`. Every ID would change, so every account, room membership and signed entry would be
reset; codes would grow by about 1,200 bytes, which is a much denser QR code; and the invitation
phrase and every comparison code would change. A removed device keeps the identity, so the address
salt would still be needed on top.

The other way leaves identities alone. Each member's device makes a random 32-byte seed for each
contact and sends it the way an address salt goes now: sealed with X-Wing to each of the contact's
devices, signed by a device, and adopted only from a device that counted when iCloud stored it. The
pair's secret becomes HKDF over the X25519 output and both people's seeds, and a pair with no seeds
keeps the current secret byte for byte, so it can be turned on pair by pair. `ParticipantID`, codes,
phrases and comparison codes do not change, because the seed is vouched for by a device signature that
leads back to the identity the two people already compared. What it still leaves: the first packets
between two people, before a seed has arrived, go under X25519 alone; a restore loses the member's own
seeds, so contacts re-send theirs and the member makes new ones; the comment copy for a wall's owner
is kept in the log for good, so it can only use the commenter's seed, which the commenter re-sends
after the owner restores; and signatures stay Ed25519, which is a question about a future forger, not
about a recording. Nothing recorded before it becomes any safer. It costs one announcement per contact
whenever either person's devices change, about 1.6 KB per receiving device (a grant sealed for two
devices measured 3,751 bytes of JSON), a seed per contact in the keychain, and more rules in the
address code, which already has the subtlest ones: the nine-day overlap, the stored-time order, and
re-sending until signed for.

**Recommendation: the second way, with a seed per pair.** Reusing the per-member address salt is
cheaper but not enough, because every contact learns a member's salt: somebody in touch with both
people who could also break X25519 could work out their secret. The first packet to a new contact
should carry the seed, so X25519 alone covers one exchange.

<!-- COPY END 2983233d -->

<!-- COPY BEGIN 6836a24f [NEEDS HUMAN REVIEW] -->

## The record a member's devices share grows with every device the member knows

The state record a member's devices write for each other carries the certificate of every device of
everybody the member knows, and since 2026-11-05 each certificate carries a 1,216-byte X-Wing key.
Measured in the package on 2026-11-05: one certificate is 2,171 bytes of JSON, against 578 with the
X25519 key, and a sealed state record with 200 certificates is 294,411 bytes, against 49,963. CloudKit
holds at most 1 MB in a record outside its assets, so at that rate, about 680 known devices, the state
record would stop being written. Mail and catch-ups carry the same certificates, and nothing splits a
record between a member's devices by size. Not measured on the rig.

**Recommendation: keep only the member's own certificates and removals in the state record.** Other
people's certificates already arrive in their own packets, and a new device gets them in its catch-up.

<!-- COPY END 6836a24f -->

<!-- COPY BEGIN 4f2530e3 [NEEDS HUMAN REVIEW] -->

## Does X-Wing change the export self-classification?

The export finding rests on everything being standard cryptography
([App Store](app-store.md#the-finding-that-everything-else-rests-on)). Since 2026-11-05 the app also
uses HPKE (RFC 9180), ML-KEM-768 (NIST FIPS 203), AES-256-GCM, and X-Wing, which is an individual
Internet-Draft in the Independent Submission stream, not adopted by the IETF. The definition quoted
there counts as non-standard only what is neither adopted by a recognised body nor otherwise
published, and X-Wing is published. All of it is CryptoKit.

**Recommendation: it stays standard; record X-Wing in the self-classification as published, not
adopted.** This is a reading of the rule, not legal advice.

<!-- COPY END 4f2530e3 -->
