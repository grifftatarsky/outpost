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

**What it costs.** Griff accepted 1 and 3 on 2026-11-10 and answered 4 the same day by ruling the
two factors (below). 2 and 5 are still his to accept or change.

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
   Until 2026-11-11 only the Face ID wrapping asked for that; the code's wrapping asked for nothing
   but an unlocked phone.
5. Left in the clear: the lock's own record, the choice of when files open, and the outside of each
   entry in the history file (which device wrote it, when, and in which room, by number). What each
   entry says, and every photo, is sealed under room keys, which the lock now seals.

**4 was answered.** Griff ruled on 2026-11-10 that the code counts only after Face ID or the phone's
passcode has passed, and that somebody who knows the phone's passcode is out of scope
([Decisions](decisions.md#the-locks-code-is-tried-only-after-the-phone-has-checked-face-id-or-its-passcode)).
It was built on 2026-11-11 and is held by package tests against a stand-in. No note about
passphrases and no *Face ID only* mode were added. The simulator walk above was made before this
change and has not been repeated.

**Found while building it, and Griff's to decide.**

1. *A check the phone already passed may be reusable.* Apple lets an app accept a recent unlock of
   the phone by Touch ID or Face ID in place of a new check, for a period up to a maximum Apple sets
   ([Apple](https://developer.apple.com/documentation/localauthentication/lacontext/touchidauthenticationallowablereuseduration)).
   The app does not ask for that. A modified app could, so code running as the app shortly after
   the owner unlocked the phone might use the code's key with no sheet. Not tested.
   **Recommendation:** try it on the iPhone first. If it holds, accept it: that person has the
   phone within minutes of the owner unlocking it and still has every code to guess.
2. *Turning the phone's passcode off may delete the code's key.* If iOS does that, the code never
   works on that phone again and the recovery key is the only way in. The app now says so when it
   happens. Whether iOS deletes the key is not verified. **Recommendation:** require the recovery
   key to be saved before the lock can be turned on.
3. *Forgot the code?* erases this phone's copy with no check by the phone, so anybody holding it
   unlocked can erase it. **Recommendation:** ask for Face ID or the phone's passcode first, and
   skip that on a phone with no passcode.
4. *Changing the code* retires the old key without first opening the new lock. Turning the lock on
   does prove the new lock opens; changing the code does not. **Recommendation:** prove it the same
   way, at the cost of one more sheet.
5. *Erasing after wrong codes when the app started behind the lock* still cannot tell the member's
   other devices, as before. Nothing was built for it.

**What only an iPhone can show.** None of this has run:

- that the Secure Enclave refuses the code's key until the check passes, and that its key
  agreement gives the same result as the app's own arithmetic;
- that the Face ID or passcode sheet makes the app inactive and never sends it to the background,
  and that iOS cancels the sheet when the app does go to the background;
- that turning the phone's passcode off deletes the code's key, and what the app then shows;
- that a Face ID lockout leaves *Face ID alone* switched on;
- whether a key that asks for the enrolled faces offers a passcode fallback on its sheet;
- the reuse period in 1.

The hosted test `TheVaultOnTheRealKeychainTests` raises two real sheets on an iPhone, so a person
has to be there to answer them.

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

**Designed on 2026-11-11, not built.** [The design](designs/room-history.md) was written against
today's code and reviewed once. Its first page has the four promises for Griff to confirm and six
decisions, each with a recommendation and what it costs. A time window can only honestly say "no
more than N days", because one key covers everything written while it was the newest. Nothing is
built until he answers.

<!-- COPY END 5bab6014 -->

<!-- COPY BEGIN 79bfab59 [NEEDS HUMAN REVIEW] -->

## Formats after the first tester build, and telling a member to update

Asked by Griff on 2026-11-10: keep old message formats accepted without much new code, support one
prior format, and tell members to update after one release has passed, with no server and nothing
shared with Apple. [The design](designs/formats-and-updates.md) answers it and nothing is built.

**The plan in four lines.** Saved messages are never converted, and every form ever written stays
readable, because a signature is taken over the bytes. What phones hand each other (packets, keys,
invitations) is read in today's form and the one before it. This phone's own state file is converted
once, at the first launch of a new build. Each phone puts the format number it reads inside the
sealed packet it already sends, and a phone that hears a higher number tells its member to update.

**What the notice shares.** Nothing with Apple and nothing with a server. Everybody a phone writes
to learns its format number and roughly when it changed. The App Store opens only when the member
taps.

**For Griff:** confirm the thirteen promises in the design's section 2, and five decisions on its
first page.

1. Old messages are never converted, and a fixed rule ships as a new kind of message. *Recommend yes.*
2. A release reads a new form one release before any release writes it. *Recommend yes.*
3. Whether the notice compares only the format number, which changes rarely, or also the App Store
   build number, which tells contacts the exact build. *Recommend adding the build number.*
4. A room takes no writes while a current member has written something this build cannot read.
   A member with a modified app could use that to stall a room until removed. *Recommend yes.*
5. No App Store lookup, which would tell Apple the phone's address at every launch; no public
   iCloud record edited by the developer, which is a server in all but name; no reminder by a
   build's age yet. *Recommend no to all three.*

<!-- COPY END 79bfab59 -->

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

<!-- COPY BEGIN 76b2ed08 [NEEDS HUMAN REVIEW] -->

## Five rulings were recorded on a branch that never merged

Found 2026-11-11. The branch `origin/desktop` (86 commits, 2026-09-18 to 2026-09-22, never merged)
has a `docs/decisions.md` with five entries marked RULED by Griff that are in neither this branch's
docs nor, as far as was checked, its code. The room history setting was a sixth and has
[its own question](#a-rooms-history-setting-was-built-on-a-branch-that-never-merged). Everything else
that branch held is in [the audit](desktop-branch-audit.md).

| Ruled | Griff's words, as that branch recorded them | What it asked for | On this branch |
|---|---|---|---|
| 2026-09-20 | "a user provides only what another user is allowed to see. Ideally, they cannot retrieve something they will not be allowed to read." | A device sends each person only the entries they may read | Not here. `mayReceive` is in no file |
| 2026-09-21 | "I do believe that is enough." | One numbered log per conversation, so no number on an entry says anything about a member's other conversations | Not checked beyond the entry being absent. It changes the bytes of every entry |
| 2026-09-21 | "yes. I love an enum." | A conversation is named by what kind it is: a room, a Solo or an Outpost | Not here. `ConversationID` is in no file |
| 2026-09-21 | "No timestamp" | Members vouch for each other's logs, and a mismatch is recorded, not called an accusation | Not checked beyond the entry being absent |
| 2026-09-21 | "A reinstall should become the same device - if it's still correctly identified." and "Keep the log and state out of backups. And wait only for its own record." | A reinstalled or restored phone comes back as the same device and writes nothing until it has read its own records back | Not checked beyond the entry being absent |

**Why it matters before a tester build.** The second and third change what an entry is made of, and
after the first tester build a change like that has to be carried as a format step.

**Recommendation.** Griff says which of the five still stand. The ones that do go back into
`decisions.md` as his rulings and onto the plan ahead of the tester build, starting with sending
each person only what they may read, because the room history setting leans on it.

<!-- COPY END 76b2ed08 -->

<!-- COPY BEGIN 0fc0cd18 [NEEDS HUMAN REVIEW] -->

## Twelve faults the many-device tests found

Found 2026-11-11 by the tests that run five people and their devices in one process against the fake
iCloud. Griff asked for them fixed the same day: "Complete the faults." **All twelve are fixed**, each
in a commit that ends by deleting its known-issue mark, and the whole package suite passes. What has
run on two accounts is in [the rig's record](simulator-rig.md#what-outpost-alpha-and-outpost-beta-showed-on-2026-11-11).
Most of these need three people or two devices on one account, which the rig does not have, so for
those the package suite is the only evidence.

| # | What happened | What changed |
|---|---|---|
| 1 | Bob's tablet sent before his phone told it of a removal, and wrote under the key the removed member still held | The read before a send also takes the mail from the member's other devices. A device signs for a delivery only once what it carried is stored for those devices |
| 2, 5 | A friend away longer than a packet waits never got the new key, or the removal | When a packet is taken back uncollected, the keys it carried are owed again, and so are the entries in it that decide who is in a room. Messages still come back through history repair |
| 3 | A friend who had not heard that Bob removed his tablet sealed a key to it, and the room stayed on that key | A device writes down which keys it sealed to which device, and gives a room a new key if it sealed the current one to a device since removed. It also collects again from a peer whose address just moved, so a removal and the key that answers it arrive in one round |
| 4 | A removed phone with a modified app made a key, and friends kept trusting it after they heard | A key with no key-change record counts only on the word of the device that signed its grant, and only while that device counts. A key whose key change was refused or thrown out counts on nobody's word |
| 6 | Two of a member's devices removed each other, and friends kept the wrong one | A device tells friends only the removals whose target it shows as removed |
| 7 | A send inside two seconds of a round missed a removal stored in between | The read before a send drops what the mailbox last read |
| 8 | A tablet whose disk refused its phone's mail, then restarted, never got it | On launch, device sync reads everything stored, and skips mail it has already taken |
| 9 | A notification wish turned off a round after it was turned on stayed on | The wish list carries when it last changed, and the newest wins |
| 10 | A removed member's phone confirmed her old invitation on every round | An invitation the room shows as finished is not confirmed |
| 11, 12 | A write that landed with its answer lost was made twice, and nothing tracked the first copy | The next round looks for the packet before sending again |

**A review of the fixes, 2026-11-12.** Three reviewers read the fixes for who could still get
through, what they cost, and whether the tests held them. Seven of their findings were real and
are fixed, each with a test that fails without it:

- A removal written by a device already removed was still passed to friends once its target was
  removed for real. A removal is now passed on only when the device that wrote it is the one this
  phone shows as having removed the target.
- A friend's device removal never reached the member's other devices, so a tablet behind its phone
  kept sealing keys to the removed device. Device mail now carries them.
- A write of device mail that failed for one record without an error let the phone sign anyway. It
  signs only when iCloud reports the mail record stored.
- The phone wrote its device mail and waited once for every friend who had delivered something. It
  now writes once a round and signs for the round together.
- A fresh look at iCloud joined a read already under way, which could have begun before the removal
  it was looking for. It now waits that read out and starts its own.
- Between two people, a lost answer still sent the message twice, and the look for the packet
  could read a view two seconds old.
- The test of a removed phone's key no longer checked which key the room ended on in the cases
  where a friend had handed it to the removed phone. It does now.

**Found while fixing, and not fixed.** Each is Griff's to decide, with what I would do.

1. **A removed device can sign for a friend's packets until that friend hears of the removal.** A
   member's devices share one inbox, and the first to sign for a packet ends the offer. A removed
   device that still signs is believed by any friend who has not heard, so the member's other
   devices never see what the packet carried. Read in the code, not shown by a test. *I would:* have
   a friend who hears of a removal owe again whatever that device signed for.
2. **A device approved moments ago gets no mail from the member's other devices until they have
   seen it.** A message sent from it in that gap can miss a removal the phone collected. *I would:*
   have the approving device write the new device's first catch-up as part of approving it.
3. **One member's own devices can hand a key to a sibling that was just removed**, the same way a
   friend could in fault 3, if the phone collects a key before it hears of the removal. Read in the
   code. *I would:* add what goes in device mail to the list of keys sealed.
4. **A removed device that reaches a friend before the member's other devices do is believed by
   that friend.** This is the other half of fault 6. Two devices each say the other was removed, and
   a friend has only the order the two arrived in to choose by. *I would:* say so in the crypto
   brief and leave it; the recovery key is the way out. A fix needs a time both sides can trust, and
   there is none between two Apple Accounts.
5. **If the replacement key after a device removal never arrives, every friend makes one.** Each
   friend sealed the old key to the removed device when it still counted, so each replaces it. The
   room ends on one of those keys. *I would:* leave it; it needs the member's phone to stop between
   announcing the removal and sending the key.
6. **If the app restarts between a lost answer and the next round, one message goes out twice.**
   Nothing is shown twice. *I would:* leave it.
7. **A member's phone does not know which keys her tablet sealed.** The list of keys sealed to each
   device is kept per device. If Alice's tablet sealed a room key to Bob's removed tablet, only her
   tablet replaces it, and until it runs a round her phone writes under that key. Found by the
   review, read in the code. *I would:* put the list in device mail, so any of her devices that
   hears of a removal can act on what all of them sealed.

**Seen once and not confirmed.** A device approved moments earlier, with its clock an hour behind
iCloud's, could not write anything: its entries were refused as coming from a device not yet approved.
Whether a real phone can get into that state was not checked.

<!-- COPY END 0fc0cd18 -->

<!-- COPY BEGIN 7e8fde84 [NEEDS HUMAN REVIEW] -->

## A phone restored with the recovery key reaches nobody when the old phone is gone

Found 2026-11-12 by a many-device test (`CarolComesBackWithHerRecoveryKeyTests`), every run, and
confirmed by reading `restore(fromRecoveryKey:)`. Not run on the rig.

Carol's only phone is lost. She installs the app on a new phone and types her recovery key. She is
the same member again, with a new device. And that is all: the new phone holds no rooms, no keys
and nobody to write to, and nothing ever arrives. Her friends still list her and keep writing to her.

Why. A restored phone learns its rooms and its people from the member's old phone, which hands them
over when it hears it was replaced. The tests that hold the restore all leave the old phone running.
With it gone, what it left in iCloud for its sibling is sealed to devices that no longer exist, the
new phone's list of people in touch is empty, and a round only talks to people on that list.

[The identity page](epics/identity-and-devices.md) says the only device being gone is "the case the
key exists for". On the same Apple Account the new phone could do better: the old phone's small
state record is readable with the identity alone and names the people she knew, and her own spaces
for them are still in her iCloud. From those it could find her friends and ask them for what was
said. What they then send her, room keys included, is not written down anywhere and needs deciding
with it.

**I would:** build it before a tester build, starting from three sentences for Griff to confirm:
a member who restores on the same Apple Account finds the people she knew without the old phone;
each of them sends what the rules already let a restored member have; a stranger with the recovery
key and a different Apple Account gets nothing from iCloud and has to be let in again.

**Found beside it, by a throwaway probe and not held by a test.** Two restores of one member are
put in order by the dates the restoring phones wrote. A phone restored with its clock two hours
behind the lost phone's certificate was treated as the older one, counted as replaced, and erased
itself: six runs of six. With no clock difference it did not happen. This is
[a date a device writes is not an order](crypto-brief.md) again. *I would:* order restores by when
iCloud stored them, as approvals and removals already are, and hold it with a test.

<!-- COPY END 7e8fde84 -->

<!-- COPY BEGIN 80133628 [NEEDS HUMAN REVIEW] -->

## A removed member who has not heard can hand her room keys to a second identity

Found 2026-11-12 by a many-device test (`ARemovedMembersSecondIdentityGetsNobodyInTests`), in the
two cases where Erin invites Eve before Erin has heard she was removed. Erin's phone still counts
Eve as let in, makes a new key and hands Eve every key it holds. The room is not fooled: its four
members show four members and no open invitation, and nothing written after the removal opens for
Eve. What Eve gets is history Erin could already read and could have copied out by hand.

**I would:** leave it and say so. Stopping it needs Erin's own phone to refuse, and her phone is the
one that has not heard. The test is kept as a known issue until Griff says it is not a fault.

<!-- COPY END 80133628 -->

<!-- COPY BEGIN 2b4bfabc [NEEDS HUMAN REVIEW] -->

## Blocking somebody does not stop them reading you in a room you share with others

Found 2026-11-12 by a many-device test (`AHoleAndABlockAmongFiveTests`), every run. The decision on
blocking, which is **PROPOSED** and Griff has not been asked, promises: "While you block somebody,
they cannot read anything new you write." That holds between two people. In a room of three or more
it does not: Carol blocks Dave, her own phone stops sending to him, and Alice, Bob and Erin pass her
messages on, sealed under the room key Dave still holds. They do not know she blocked him, and
telling them would tell the room.

The app's own words are already the true ones. The alert on blocking says the person "no longer
appears anywhere on your devices" and that "what they can read of yours doesn't change."

**I would:** change the decision to say what the app says. Blocking hides somebody from you and
stops their rings. To stop them reading you in a shared room, remove them from it or leave it. The
other way, giving the room a new key that Dave is not sent, is a removal under another name, and
the room would see it.

The test is kept as a known issue until the decision says which.

<!-- COPY END 2b4bfabc -->

<!-- COPY BEGIN 770379fb [NEEDS HUMAN REVIEW] -->

## A reader let in "from now" when the owner posts from two devices

Found 2026-11-11, by review of that day's fix and then by tests. An Outpost reader let in *from now*
is recorded as coming in at a key's **number**. Two of the owner's devices that are out of touch can
each make a different key at the same number, so a number cannot say which key the reader came in
at. Three cases, each a test in `WhatAnOutpostReaderIsHandedTests`, all in the package suite only.

| Case | Before 2026-11-11 | Now |
|---|---|---|
| The other device's key has a lower number and was made **before** the reader came in | The reader was handed it and read the earlier posts | **Closed.** A key numbered below where the reader came in is not sent |
| The other device's key has the **same** number and was made before the reader came in | The reader may be handed it, reads the earlier posts, and may then be unable to read anything newer until the key next changes | **Unchanged.** Happens when that key reaches the reader first; one run in six |
| The other device's key has a lower number and was made **after** the reader came in, while it was out of touch | The reader was handed it and read that device's new posts | **Worse.** The key is withheld, so the reader cannot read what that device posted until it catches up. Every run |

So the fix is a trade: it stops one way of reading older posts, and it costs a reader the posts an
out-of-touch second device makes. It was kept because reading what "from now" promised to keep back
is the worse failure. **Griff decides whether it stays.**

**Recommendation.** Record the exact key a reader came in at, not its number, in the entry that
lets them in, and hand a reader only that key and keys made by a device that had seen them let in.
That closes all three. It is decision 2 on the first page of
[the room history design](designs/room-history.md), and it changes what that entry carries, so it
belongs before a tester build.

**Three smaller things the same review found**, none shown by a test:

- A room flagged for a new key before anything is written clears the flag before the key change
  is finished. A message sent in that gap may be written under the old key. The reviewer judged it
  unlikely by the order tasks run in; it was not measured. Recommend holding the key change as a
  task that a second writer waits for.
- A person who accepted two invitations to one room, got in by the second and was then removed
  still confirms the first one every round. The fix of 2026-11-11 quiets only the invitation she
  came in by. Recommend recording a replaced invitation as finished, after checking that a member
  cannot use that to shut somebody out by repeating an old invitation.
- No test holds two key changes that overlap. The code was read and is right; a test needs a log
  store that can be held open.

<!-- COPY END 770379fb -->
