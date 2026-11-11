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

## What a removal can still cut, and when a removed member can still answer it

A removal names the last entry of each of the removed person's devices that the remover's phone holds,
and everything of theirs past that line stops counting, on Griff's ruling that the line is what the
remover's device had received. The app always names everything it holds. A modified app can name less.

**Closed on 2026-11-10.** A removed member could undo their removal with the old key: a removal of
whoever let the remover in, naming a line just before that invitation and hiding what its author had
read. Every phone then dropped the remover and put the removed member back. Now a removal that this
phone had first stands against anything its subject writes afterwards, whatever that later entry
claims. A phone goes by the time iCloud stored each one as it saw them itself, by its own clock for a
removal it wrote, and, when it saw neither first, by the times other members wrote down when they
read them. Griff's words for the rule: a removal takes place when it reaches the first person who is
not the one removed. `ARemovalCannotTakeBackWhatTheRemoverSawTests` holds it in the package. Not run
on two accounts.

The fix first recommended here was different: have every device sign, now and then, the newest entry
it holds from every other device. It was checked and not built. It only binds a device that ran the
real app before it turned hostile, and the app already names everything it holds when it removes
somebody. It would also add a signal, on every entry, of what each phone had received.

**Still open, three cases:**

1. A phone that gets its copy of the removal after the removed member's answer. A removal is written
   to the remaining members before the removed person is told, so this takes a failed write to one
   member. That member's phone then believes the answer, and shows the member as out of the room, until
   another member's note of the removal reaches it.
2. A phone with nothing to say which came first: no stored time of its own and no member's note. None
   has been found; a test keeps the case as a known issue.
3. A member who is still in an open room, with a modified app, can remove somebody with a short line
   and every phone drops that person's later words and everybody they let in whom nobody else
   answered for. In an open room that member could remove each of those people one at a time anyway;
   what the short line adds is that their words go too.

**Recommendation for 3: keep an entry of the removed person's that another member's phone had
already named before it heard of the removal,** the way an invitation another member answered is
kept today. It needs a rule for who counts as another member when the removal itself decides who is
in, and a ruling on a room where nobody does: whether the remover's line or the inviter's side wins.

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

The same holds while Outpost's own lock is shut, since 2026-11-10.

**Recommendation: 3, and say so on the setting's page.** The setting already costs classic
notifications; a message older than nine days coming back the slow way is a smaller cost than
publishing the member's addresses to anybody holding the phone. 1 weakens the thing the setting is
for.

<!-- COPY END 8f4c521a -->

<!-- COPY BEGIN 29bd829c [NEEDS HUMAN REVIEW] -->

## The Focus filter shows room names to the system's settings

Choosing which rooms may notify during a Focus happens in Settings, so iOS asks the app for the name
of every room to draw the list, and keeps the rooms the member picks, with their names, in that
Focus's settings, where nothing the app seals reaches and erasing the app does not clear them. Since
2026-11-05 the filter is hidden from Siri, Spotlight and Shortcuts (`isDiscoverable = false`), which
Apple documents; it does not say whether the Focus settings still list a filter marked that way, and
nobody has looked on a phone.

**Recommendation: look on the rig first.** If the filter is still listed, keep it and say on the
Focus page that the chosen rooms' names are kept by iOS. If it is gone, the choice is between a
filter that names rooms to the system and no filter: drop the room list and keep only *Show what was
said*, which names nothing.

<!-- COPY END 29bd829c -->

<!-- COPY BEGIN 5d82a14a [NEEDS HUMAN REVIEW] -->

## Outpost's own lock seals what the phone keeps, and what that costs

Connected on 2026-11-10. With the lock on, the state file and every key kept only on this device
(the identity, the device key, every room key, the address book) are sealed under a key that opens
with the code, with Face ID if chosen, or with the recovery key, and only on this phone: each
wrapping also needs a Secure Enclave key. Checking a code is opening that key; the lock no longer
keeps anything else that says whether a code is right. While the lock is shut the app reads nothing,
writes nothing and collects nothing. Turning the lock off, or opening with the recovery key, puts
everything back in the clear first. The package holds it in `TheLockSealsWhatThisPhoneKeepsTests` and
`TheLockScreenDrivesTheVaultTests`, against a fake Secure Enclave.

An earlier entry here said the lock could not seal the identity because the identity lives in iCloud
Keychain. The code keeps the identity on this device only, so the lock seals it.

**Not proven.** The Secure Enclave half has never run: a simulator has none, and a simulator build
uses a stand-in that keeps its key in the keychain and protects nothing. The lock screens were
walked once on a simulator on 2026-11-10 (`RigChecks.testANewMemberSavesTheKeyAndLocksTheApp` on
`outpost-alpha`): the lock set at setup, a wrong code, the right code, the app stopped and started
again behind the lock, the member's name still there once it opened, and *Forgot the code?* erasing
the phone. Changing the code, Face ID and the recovery key were not walked, and nothing has run on a
phone.

**What it costs.** Griff accepted 1 and 3 on 2026-11-10; 2, 4 and 5 are still his to accept or
change.

1. With the lock on, a notification can only say that something arrived. The notification extension
   runs in its own process and never has the key. Accepted: "it does still allow for anon push
   notifications? That's nice."
2. Nothing is collected while the lock is shut, the same as a locked phone under Advanced On Device
   Security, so a message nobody collected in nine days comes back through history repair.
3. The key stays in memory from an unlock until the lock screen next comes up. *Require the code*
   in the lock's settings says when that is: immediately, or after one, five or fifteen minutes
   away. Accepted: "The key staying in mem until the app is closed or the phone is locked makes
   sense to me."
4. A six-digit code can be guessed on the phone itself by somebody who can run their own code as
   the app, which takes a jailbroken phone that is unlocked. The app counts wrong codes (five free,
   then waits of a minute, five minutes, fifteen minutes and an hour, and *Erase after* 1, 5 or 10
   wrong codes if the member turned it on), and a modified app skips the counting. Each guess then
   costs one Secure Enclave operation and 600,000 rounds of PBKDF2, the count OWASP gives
   ([OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)).
   Measured on an M1 Mac on 2026-11-10, the PBKDF2 alone is 0.067 seconds a guess: every six-digit
   code in about 18 hours, every four-digit code in about 11 minutes. Not measured on a phone, and
   the Secure Enclave's share was not measured.
   Apple's own passcode does not have this problem because the Secure Enclave counts the attempts
   and enforces the waits itself
   ([Apple Platform Security](https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web)).
   An app cannot ask the Secure Enclave to count guesses of the app's own code. Signal's answer is a
   server that counts them ([Signal](https://signal.org/blog/secure-value-recovery/)), and Outpost
   has no server. What an app can do is make the Secure Enclave refuse to use the vault's key until
   iOS has checked Face ID or the phone's passcode, which the Secure Enclave does count
   ([Apple](https://developer.apple.com/documentation/security/secaccesscontrolcreateflags/userpresence)).
   Today only the Face ID wrapping asks for that; the code's wrapping asks for nothing but an
   unlocked phone.
5. Left in the clear: the lock's own record, the choice of when files open, and the outside of each
   entry in the history file (which device wrote it, when, and in which room, by number). What each
   entry says, and every photo, is sealed under room keys, which the lock now seals.

**Recommendation for 4, three parts.** Make the code's wrapping ask for the phone's own check
first (Face ID, or the phone's passcode), so somebody without those gets no guesses at all: that is
two factors, and it costs a second prompt when Face ID fails. Say beside the code that a passphrase
is what stops a thief who knows the phone's passcode. Offer *Face ID only*, with the recovery key as
the one way back, for a member who wants that thief stopped outright. None of it can be run on a
simulator, so it is built with the first iPhone run.

<!-- COPY END 5d82a14a -->

<!-- COPY BEGIN 5bab6014 [NEEDS HUMAN REVIEW] -->

## A room's history setting was built on a branch that never merged

Griff ruled on 2026-09-19 that a room should offer what an Outpost offers: "sharing all history, or
only forward history, when invites are issued." It was built that day as commit `f75295a` on the
branch `origin/desktop`, with `JoiningFromTodayTests`. That branch holds 86 commits from 2026-09-18
to 2026-09-22 and was never merged into `main` or this branch. Twenty of its test suites exist
nowhere else. Why it was left is not recorded.

So on this branch a room hands every newcomer the newest key, and the newest key opens every
earlier one. An Outpost does have the setting: a reader let in "from today" is handed only the keys
after that point (`Projection.outpostFloors`).

What Griff described on 2026-11-10 is wider than what was built: "rooms with settings so that people
were allowed time windows, all, or other settings per room." No record of time windows was found in
the docs or on either branch.

**What the build on the other branch did.** The invitation said, signed, whether it carried the
history. When a newcomer without history was let in, the inviter replaced the room's key and handed
them only the keys after that, so the older ones could not be worked out. Because that newcomer
cannot read the entries that made the room, the inviter also restated the room's name, members and
rule for them.

**What it does and does not change.** It decides what a newcomer can read. A member who was there
all along still holds every key they were given, so somebody who takes that member's unlocked phone
reads what that member could. Only deleting old keys, and with them the old messages on that phone,
changes that.

**Recommendation.** Bring the 2026-09-19 design to this branch as a setting on the room (everything,
or from when they join), written again against today's code and not cherry-picked, because 251
commits have landed since. Add a time window as a third choice only if Griff confirms it. It changes
what an invitation and an admission carry, so it has to land before the first tester build. The other
85 commits on that branch need their own pass to see what else never arrived.

<!-- COPY END 5bab6014 -->

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

<!-- COPY BEGIN 7146c022 [NEEDS HUMAN REVIEW] -->

## An invitation to somebody this phone already knows carries its own opening

Starting a Solo from the list of people, or picking people while making a room, never worked. The
app gave the invitation the person's bare key where it expected the code that person shares, and
decoding failed every time (seen on the rig 2026-11-04 as "Send a Solo opened nothing", fixed
2026-11-10). An invitation is signed over a commitment from the person joining, and somebody picked
from a list has not given one. For these invitations the inviting phone now makes the commitment
and puts its opening in the invitation.

What it is built to guarantee, for Griff to confirm:

1. Picking somebody this phone already holds a key for makes an invitation they can accept without
   a code of theirs.
2. Only the holder of that key gets in. Somebody else who gets the link cannot use it, and an opening
   that does not match what the invitation was signed over is ignored.
3. An opening in an invitation never replaces one the joining phone made for its own code.

What it does not do: the phrase the two phones show for one of these invitations cannot catch
somebody who had already swapped both people's keys before the invitation was made. The inviter
chose the opening, so such a person could search for an invitation of their own with a matching
phrase. A code handed over in person still catches that, and so does the Solo's own check.

**Recommendation: keep it, and treat the phrase on these invitations as a courtesy, not a check.**
`InvitingSomebodyYouAlreadyKnowTests` holds the three sentences in the package. Not run on two
accounts.

<!-- COPY END 7146c022 -->

<!-- COPY BEGIN cc829033 [NEEDS HUMAN REVIEW] -->

## Should the app stop copying and screenshots?

Griff asked on 2026-11-10 for this to be explored. Nothing has been looked into yet: what iOS lets
an app do about screenshots and screen recording, whether copying can be turned off for a room or
everywhere, and what either would cost somebody who needs a record of what was said to them. A
report is a copy, for one. Today the app does neither, and a report copied from the report screen
stays on the clipboard with no expiry.

**Recommendation: none yet.** Read Apple's documentation first, then bring back what is possible and
what each choice costs.

<!-- COPY END cc829033 -->
