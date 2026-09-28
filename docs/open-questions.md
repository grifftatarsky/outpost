---
# COPY BEGIN f917ea56 [HUMAN REVIEWED, UNVERIFIED]
title: Open questions
layout: default
nav_order: 2
---

# Open questions

{: .no_toc }

Settled decisions live in [Decisions](decisions.md).

1. TOC
{:toc}

## Questions
<!-- COPY END f917ea56 -->

<!-- COPY BEGIN f0e1c11a [NEEDS HUMAN REVIEW] -->

### What can a phone nearby do to a tap?

Raised 2026-09-28, writing tap-to-swap. The promise Griff confirmed is that a phone across the room
can't get your code or slip in its own, and that the characters you both read still decide. Two things
get part of the way past the distance check. The characters stop a code slipped in; they do not stop a
relay learning one, so accepting that needs Griff's yes.

**A relay.** A modified app within Wi-Fi range can pass the two phones' first messages between them,
so it sits in the middle while their real distance is measured. It is caught when the two phones also
find each other directly, since two phones then read as touching; in the moment before they do, it
could be handed a code. A code is made to be handed out, and one it swaps in shows as characters that
do not match.

**A shortened distance.** A USD 65 radio made two U1 chips 12 m apart measure 0 m in up to 4% of
tries ([Ghost Peak](https://www.usenix.org/conference/usenixsecurity22/presentation/leu)). Three
readings in a row and one touching phone at a time make it harder, not impossible.

Recommended: accept both, since the worst either does is learn a code that is meant to be shared, and
say in the app that the characters are still the check. The alternative, a short number shown on both
screens to compare during the tap, adds a step to every tap to close a window the characters already
close.

<!-- COPY END f0e1c11a -->

<!-- COPY BEGIN a41e8a48 [NEEDS HUMAN REVIEW] -->

### Should Outpost's own lock open with Face ID?

Raised 2026-09-28. Griff ruled both locks, and a PIN, each with a short note and a link to an article
on Face ID, PINs and passwords ([Decisions](decisions.md#advanced-on-device-security-seals-what-this-phone-keeps-while-it-is-locked)).
One thing is left. Face ID would need a second copy of the key behind Face ID, which the code's counted
tries do not guard, and erasing after wrong codes would erase the only copy. His own words on Face ID
("breached by cops ... not considered effective") point the same way.

Recommended: no Face ID for Outpost's own lock, and erasing works as it does now.

<!-- COPY END a41e8a48 -->

<!-- COPY BEGIN d041ce54 [NEEDS HUMAN REVIEW] -->

### What is left of a removed person's reach into a room's past?

Raised 2026-09-28, writing the room chain Griff ruled for. A removed device is answered (below); one gap
is left.

**Numbers from before chains.** An entry written before this build carries no link. Those count up to
the entry the chain begins at, which closes everything after it, but a removed person could still sign
an old-style entry under a number below that point that the room never held. Recommended: accept it. It
cannot grow, because every new entry is chained, and it covers only numbers from before a device's first
chained entry in that room. Griff asked for the gap closed with no new edge cases, so this needs his
yes. The way to close it without giving a remover any power: each device, the first time it chains in a
room, lists its own earlier entries there, which costs one entry per room per device, once.

<!-- COPY END d041ce54 -->

<!-- COPY BEGIN ddabe07b [NEEDS HUMAN REVIEW] -->

### Should an ask for a photo reach every one of the sender's devices?

Raised 2026-09-27. When somebody asks for a photo again, the ask reaches whichever of the sender's
devices collects it first, and only that device lists it. If the photo was sent from the phone and the
iPad collected the ask, the iPad can still send it when it has a copy of its own (it keeps any photo it
has shown), and otherwise says the photo is not on this device. Recommended: pass asks between a
member's devices the way room keys are passed, so the device that sent the photo always hears.

Also: asks work for photos in conversations and not on Outposts. Recommended: leave Outposts out until
somebody asks, since a new reader already gets every picture on the wall.

<!-- COPY END ddabe07b -->

<!-- COPY BEGIN ced635d1 [NEEDS HUMAN REVIEW] -->

### Who can send your device a room key it can't check yet?

Raised 2026-09-26 from a test.

How room keys work. Each room has a key, and messages are locked with it. When the key is rotated,
the member who rotated it sends the new key to everybody in the room, locked so only that person can
open it. With it they send a link: the old key, locked with the new key. Anybody with the new key can
open the link, get the old key and read older messages. A new member, or a restored phone, reads a
room's history by following those links back. Your device writes new messages with the newest key it
has, and passes that key on to the others in the room.

What was fixed on 2026-09-26. Your device used to accept a room key from anybody it had ever
exchanged keys with. Somebody removed from a room could make up a new key and send it to you. Your
device took it as the room's newest key, locked your next messages with it and passed it on, so the
person who made it up could read what you, and then the room, said next. `WhoCanSendYouAKeyTests`
shows it. Now a device refuses a key from somebody the room shows as removed or gone, never replaces a
key it already has, and takes a key to somebody's Outpost only from that person.

What is still open:

- **A device that can't read the room yet can't check who sent a key.** That is a device joining the
  room, or one restored from the recovery key. The member list is locked with the room key, so until
  the device has a key it can't see who is in the room. That is right: Griff ruled on 2026-09-26 that
  a device that hasn't been admitted doesn't see who is in the room. So it needs a different rule.
  Proposed: a joining device takes its first key for a room only from the member who invited it. It
  knows who that is from the invitation, so it needs no member list. Whether the inviter always sends that
  first key, in every admission setting, needs checking before this is built. After that it can read the room and check everybody else the
  normal way. A restored device has no inviter, so it still takes its first key from anybody.
- **A key that arrives early is kept.** Because a key never replaces one already held, a made-up key
  that reaches a device before the real one is the one it keeps. This only works on a device that
  can't check the sender yet, so the inviter rule closes it for joiners.
- **Any member can make a link.** A link only proves that whoever made it had the new key, and every
  member has it. So a member still in the room could send a link with a wrong old key inside. A
  device that gets it first keeps it and ignores the real one. From reading the code, not tested:
  that device can't read the room's history from before that rotation. It doesn't let anybody read
  what they couldn't already read. The fix is for the member who rotated the key to sign the link,
  and for a device to accept a link only with that member's signature. The app already decides which
  member rotates the key for each change, so a device can check it. That changes what a key and a
  link carry.

<!-- COPY END ced635d1 -->

<!-- COPY BEGIN ba7e3be3 [NEEDS HUMAN REVIEW] -->

### What a transient notice is, on iOS 26

Answered from Apple's guidance and ruled on 2026-09-15. Apple's [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
page says to avoid an alert that only informs and to "prefer finding an alternative way to communicate
it within the relevant context". So a message deleted by consensus leaves a permanent line in the
transcript where it was, not a notice that fades. Griff: "Yeah, I'm good with the permanent inline."
See [Decisions](decisions.md#a-deletion-leaves-a-line-in-the-transcript-not-a-notice-that-fades). It
applies when consensus deletion is built, which is [after TestFlight](after-testflight.md).

<!-- COPY END ba7e3be3 -->

<!-- COPY BEGIN ecfca29f [NEEDS HUMAN REVIEW] -->

### Raised and answered 2026-09-28

Griff's answers in the session before, read against the questions raised writing them:

1. **A phone locked longer than a packet waits** — nothing is lost: promise 2 of Advanced On Device
   Security. So a locked phone has to collect what arrives, keep it sealed, and add it at unlock. The
   build collects nothing while locked; this is owed.
2. **The app's preferences** — sealed too: promise 1 covers what Outpost keeps on the phone. Owed.
3. **Copies of one photo lining up in size and time** — accepted. It was named as the cost when Griff
   chose a copy per person ("Apple can tell one photo went to several people").
   [Decisions](decisions.md#a-photo-is-copied-for-each-person-it-goes-to-and-each-copy-is-sealed-apart).
4. **A removed device's reach into a room** — closed, on "Fix the removed people gap ... Make sure you're
   not introducing edge case vulnerabilities": the member's remaining device writes an entry in each room
   naming the removed device's last entry there, which tells nobody anything new. Owed.
5. **Outpost's own lock** — both locks, and a PIN, each with a short note and a link to an article on
   outpostmessaging.com. What arrives while the app is locked is kept sealed (promise 2). Whether the key
   made from the code is tied to the phone's hardware is measured on a phone before the PIN's note is
   written. Owed; the article is too.

<!-- COPY END ecfca29f -->

<!-- COPY BEGIN b2a90f66 [NEEDS HUMAN REVIEW] -->

### Raised and answered 2026-09-16

Seven questions came out of working the ticket list; Griff answered all of them the same evening.

1. **The camera ask** — the shape stands. The setting is off until camera access has actually been
   allowed, then saved on; *Not now* stops the asking; the setting lives in Behavior.
2. **The notification explainer** — one button, and the no is given to Apple. It already had one
   button; it can no longer be swiped away.
3. **The accent retint** — keep the fade, with the tab bar leading.
   [Decisions](decisions.md#the-accent-retint-fades-and-the-tab-bar-leads-it).
4. **"A fingerprint changed"** — cannot happen here, because an identity is its keys; somebody who
   starts over is a new person who has to be invited again. Replaced by a dated notice when somebody
   you talk to **adds a device** the ordinary way. Restores already have their own notice.
5. **The comparison sheet** — once per person, the first time a conversation with them opens after
   joining, skipped if you have already compared.
6. **One identity per account, offline** — wait until iCloud can be checked.
   [Decisions](decisions.md#a-first-launch-that-cannot-reach-icloud-waits).
7. **A disabled button's label** — keep Apple's look; the record is corrected.
   [Decisions](decisions.md#a-disabled-button-keeps-the-systems-look).

<!-- COPY END b2a90f66 -->

<!-- COPY BEGIN 5cccbb2c [NEEDS HUMAN REVIEW] -->

## Choices Claude made that Griff has not seen

Each of these is marked **PROPOSED** in [Decisions](decisions.md). They are defaults, not
constraints, and any of them may be wrong for reasons only Griff has.

**Sync and the log**

- How a round is packed, what a packet carries, and when it is acknowledged.
- A room announces what happened to it, in its own transcript.
- A key handed over carries the way back, or it hands over nothing.
- Somebody who stays rotates the key after somebody leaves.
- A tag the app keeps is derived, never filed.
- A purge is a tombstone, and the link survives it.

**Invitations and rooms**

- An invite travels as a link, and the link changes nothing about the invite.
- An invitation's lifetime bounds the offer up to the confirmation, and the room is not where it is
  asked.
- A confirmation answers one invitation, not one person.
- A conversation with one person is a solo, founded as one.

**Outposts**

- Access to a wall is a set of periods, and only one change is one-way.
- A comment belongs to the wall it lands on.
- A bell for a post is asked for by the reader, and the asking travels.
- A wall carries its own picture pointer, at the wall's own address.

**Identity and people**

- What you call somebody is yours, and so is the face you give them.
- Which picture is drawn for somebody, in one place.
- A shared photo is a standing attachment, not a log entry.

<!-- COPY END 5cccbb2c -->

<!-- COPY BEGIN b5eafc89 [NEEDS HUMAN REVIEW] -->

**Recent, 2026-09-17**

- Deleting a conversation reaches every device, waits for the leaving, and leaves photos for others.
- The notification extension writes nothing to the container it shares with the app.
- A color is measured on every ground it is drawn on, in both appearances.
- The source is published under the Mozilla Public License 2.0.
- The free Supporter year starts the first time an App Store build opens, the claim rides the member's
  preferences, TestFlight is detected through `AppTransaction`, and the badge travels as its own
  entry.
- The Classic drawing is offered in white on every accent too, beside the Antenna and Mailbox
  drawings Griff asked for.

**Honesty and interface**

- A failure the member could act on is reported to the member.
- A spinner is a claim, and it has to stop when the work does.
- Silence is a claim, and usually the wrong one.
- A wait must be able to end by itself.
- A seen mark is the first receipt that covered it.
- An accessibility floor is measured against what is actually behind the thing.
- Search is a tab at the trailing end, and the inline field is for sub-views.

<!-- COPY END b5eafc89 -->

<!-- COPY BEGIN 9d83b219 [NEEDS HUMAN REVIEW] -->

## Design commentary

Long-form design reasoning, kept because it is useful when picking a feature back up and separated
because it is not a decision and must not be cited as one.

<!-- COPY END 9d83b219 -->

<!-- COPY BEGIN 6d1038e9 [NEEDS HUMAN REVIEW] -->

### Where the app was changed away from a board without Griff seeing it

**The list row names no sender.** Ruled on 2026-09-13: the board is overruled and Messages' row
stands. See [Decisions](decisions.md#the-rooms-list-row-is-messages-and-board-53-is-overruled) for
what that costs.

**Search became a tab.** The first attempt was an inline field with
`.searchToolbarBehavior(.minimize)`, chosen for the collapsed glass magnifier. On a 402pt phone that
crams the clear and the dismiss into one capsule while a 440pt phone separates them — the same build,
two devices. Apple's guidance turns on the scope of the search: a search covering a whole app is a
tab, and the inline field under a title is for a search scoped to one section. Griff caught the first
answer and quoted the page.

**The notification defaults were Claude's and are now ruled.** New posts default to *By Outpost* —
only the walls a member has turned on. Replies on posts you commented on and comments on your posts
are on; replies on posts you *reacted to* and likes are off, and likes are the only kind that arrives
quietly. Confirmed 2026-09-13: the two that are on are somebody answering you, and the two that are
off are a tap and a thread you touched once.

<!-- COPY END 6d1038e9 -->

<!-- COPY BEGIN d254fcc5 [NEEDS HUMAN REVIEW] -->

### What the set does not settle, and neither does the app

**Nothing has been checked on a device at a real Dynamic Type size.** The boards are HTML
approximations drawn at 1:1, and the app's own accessibility pass covers targets, Dynamic Type and
contrast, and on 2026-09-16 every screen was walked at the largest type size on a simulator. A
phone at that size has not been looked at, and the VoiceOver walk waits for TestFlight on Griff's
ruling of 2026-09-17. A photo's reactions pill is not named in that pass and may not have been
looked at the largest size.

**Two platforms are undrawn, and the claim has changed rather than the app.** Ruled 2026-09-13: the
product is an iPhone app until TestFlight. The Mac window keeps working because Griff uses it; it is
not offered or described. Every Mac and iPad decision in it is still Claude's.

**Light mode is not drawn.** Two boards define the values and four use them. Every color the app
picks for itself was measured in both appearances on 2026-09-17, so light mode is measured rather than
inferred, but it was never designed screen by screen.

**Transitions are not drawn.** Sheets, tab switches and navigation use the system's motion. The one
motion the app adds, the accent retint, was recorded frame by frame and kept on Griff's ruling of
2026-09-16.

<!-- COPY END d254fcc5 -->

<!-- COPY BEGIN 182fa583 [NEEDS HUMAN REVIEW] -->

### Things tried and abandoned, so they are not tried again

**Swipe-to-remove, twice.** A swipe action is as wide as its content and the row slides by that much,
so on a person row whose name is one short word the swipe pushed the row off its own leading edge. It
left a member being asked to remove somebody whose name and face had scrolled out of view. A context
menu replaced it and is better: it draws the row as its own preview, so the person stays on screen
under the destructive verb.

**`.submitLabel(.send)` on the composer.** It renames the return key, takes the newline away, and
still does not submit — measured, then reverted. The arrow in the field sends; ↵ writes a second
line.

**The search glyph taking the app's accent.** `.tint()` does not reach `searchable()`, and
`UISearchBar.appearance().tintColor` does not reach iOS 26's collapsed search button. Both were tried
on device. The toolbar's menu glyph is drawn in the primary ink to match it instead.

<!-- COPY END 182fa583 -->

<!-- COPY BEGIN 19bfb2e1 [NEEDS HUMAN REVIEW] -->

## Not built

[The roadmap](roadmap.md) is the status of record. This is the short form, 2026-09-17.

**Every iPhone ticket is built to its status**, and what is left on most of them is proof — a rig
run that has not happened, a phone, or something outside the app existing. The one ticket marked
Incomplete is *Before TestFlight*, a checklist rather than a feature.

**Four tickets marked complete carried unmet criteria**, found reading the epics on 2026-09-17, and
all four are closed the same day: *Recovery from a lost device* (two were already ruled, two were one
sentence on the stalled screen), *Blocking a person* (*Block and Leave*), *Reactions on messages*
(one spoken sentence for a post's row, a *React* action on a message) and *A test seam that cannot
lie* (the fake screen, and the extension writing over the app's state file).

**The Supporter purchase is not built.** The TestFlight build grants a free year and shows the badge;
the App Store build has nothing to buy yet. It needs two auto-renewable subscriptions in one group in
App Store Connect — $12 a year, $1 a month — and a sign-up screen that meets Apple's list: the name,
the period, the price, and a way to restore.

**Decided against for now:** consensus hard delete and hard delete with a quiet desync (pushed out,
with the machinery both need now built), and an in-app lock (canceled). Reasons on
[After TestFlight](after-testflight.md).

**Desktop.** Its own [roadmap](desktop-roadmap.md), sequenced after TestFlight.

<!-- COPY END 19bfb2e1 -->
