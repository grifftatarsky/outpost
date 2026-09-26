---
# COPY BEGIN 37cfee47 [NEEDS HUMAN REVIEW]
title: Board index
parent: Design
nav_order: 1
---

# Board index

Generated from `Outpost Mockups.dc.html` so the set is greppable — the HTML is not.

**Three columns and they are not equal.** *Intent* is the designer's annotation beside each board and
is the closest thing to a rationale. *Accessibility* is from `Component Blockers.dc.html` and is a
**requirement**, not a suggestion. The captions rendered on the canvas itself are marketing copy,
published verbatim, and are **not** reproduced here because they are not specifications.

Exact values — colours, sizes, corner radii, hit targets — live in `Component Blockers.dc.html` under
*Use exactly this*. Take them from there, never by measuring the canvas: the boards are HTML drawn at
1:1 with px named as pt, and nothing has been checked on a device at a real Dynamic Type size.

<!-- COPY END 37cfee47 -->

<!-- COPY BEGIN bf7e3a03 [NEEDS HUMAN REVIEW] -->

## 01 — Onboarding

Onboarding. The name is set once, on this device, and never leaves it in the clear. The mark
above it is the Outpost symbol in the accent, which is Verdigris until somebody changes it.

**Accessibility.** Name field is the first focus. The mark is decorative — hide it from VoiceOver rather than
labelling it.

<!-- COPY END bf7e3a03 -->

<!-- COPY BEGIN 429727aa [NEEDS HUMAN REVIEW] -->

## 02 — Rooms

Rooms list. The sync line is its own row directly beneath the navigation bar, so it can wrap at
large type sizes and disappear when there is nothing to report. It states what happened, never a
"last synced" scold.

**Accessibility.** Row reads name, then relative time, then sender and preview as one sentence. Unread is
announced, not implied. Sync row is a live region that speaks once.

<!-- COPY END 429727aa -->

<!-- COPY BEGIN 0d17934f [NEEDS HUMAN REVIEW] -->

## 03 — Conversation

Room conversation. Sent bubbles take the accent at full strength; incoming take a tint of the
same hue, so a room reads as one colour.

**Accessibility.** Each bubble announces sender, text, then delivery state. Group bubbles by sender so a run is not
re-announced.

<!-- COPY END 0d17934f -->

<!-- COPY BEGIN 98b6c2d5 [NEEDS HUMAN REVIEW] -->

## 04 — Wall

Your Outpost. Old-Twitter shape, plain text posts and comments. The audience sits above the
composer and names who can actually see this — including when the answer is nobody, which is a
fact about who you have added rather than a warning.

**Accessibility.** Post, then reaction summary as words. The audience line is read before the composer, not after.

<!-- COPY END 98b6c2d5 -->

<!-- COPY BEGIN bca5b76a [NEEDS HUMAN REVIEW] -->

## 05 — Color

Theme picker — one global accent, seven colours, Verdigris by default. Tap a swatch: the whole
board retints. Each colour ships a separately measured light and dark value, previewed side by
side, and every pair is tested against the contrast floor in both appearances.

**Accessibility.** Each swatch is a button labelled with its name, selected state on the chosen one. Never "swatch
3". Retint is the one animation — respect reduced motion by cutting to the new value. Swatches
draw at 40pt with a 44pt tappable region.

<!-- COPY END bca5b76a -->

<!-- COPY BEGIN d6b1593b [NEEDS HUMAN REVIEW] -->

## 06 — Room settings

Room settings. Packs are per-room toggles, all off. The invite row carries its consequence
inline rather than waiting for a dialog.

**Accessibility.** Grouped list semantics with real section headers.

<!-- COPY END d6b1593b -->

<!-- COPY BEGIN b601b0d7 [NEEDS HUMAN REVIEW] -->

## 07 — Invite

Invite. QR is the in-person path; the phrase is what the two of you say out loud. The history
warning is a full paragraph, on purpose.

**Accessibility.** Code is selectable, readable character by character on request, and has a copy action that
confirms in words.

<!-- COPY END b601b0d7 -->

<!-- COPY BEGIN b5b18a28 [NEEDS HUMAN REVIEW] -->

## 08 — Join check

Join verification. Every member checks independently (D4) — so this is a sheet each of them
sees, with refusal given equal weight, not a destructive-red afterthought.

**Accessibility.** The three words are one label, spoken as words with pauses, not spelled.

<!-- COPY END b5b18a28 -->

<!-- COPY BEGIN 5a33bd49 [NEEDS HUMAN REVIEW] -->

## 09 — Waiting

Waiting for a peer (§5.2). Not a spinner: it says which peers it is waiting on, what it will do,
and lets you leave the screen.

**Accessibility.** Live region announcing what changed, at most once per state.

<!-- COPY END 5a33bd49 -->

<!-- COPY BEGIN d06d758f [NEEDS HUMAN REVIEW] -->

## 10 — Previews

Notification previews (ADR-P3). A ladder of radio rows, each rung labelled with what it
discloses, and the sheet that appears on every increase. The banner is composed on the receiving
device after it decrypts locally, so nothing readable crosses the network — but what the banner
draws lands in the operating system's notification store, which this app cannot reach or erase.
That is what the ladder is choosing between.

**Accessibility.** Radio group. Each rung's disclosure text belongs to its option's label, so choosing without
sight still tells you what it leaks. At the largest sizes the sample banners stack under their
labels.

<!-- COPY END d06d758f -->

<!-- COPY BEGIN cf744bb2 [NEEDS HUMAN REVIEW] -->

## 11 — Outpost access

Who sees your Outpost. Nobody, until you say otherwise: access is an allow-list, and joining a
room grants nothing on its own. One row per person — what they can see, then the rooms you
share. A person's access is one thing, changed in one place.

**Accessibility.** Row reads person, then access, then shared rooms. Access is a value, never a colour.

<!-- COPY END cf744bb2 -->

<!-- COPY BEGIN 4e1cbcc8 [NEEDS HUMAN REVIEW] -->

## 11b — Change access, new

Change sheet, someone with no access yet. "Posts from a date" is selected and the date defaults
to today, so the common case is one tap.

**Accessibility.** Date picker is the system's. The permanence sentence is part of the confirming button's
accessibility hint.

<!-- COPY END 4e1cbcc8 -->

<!-- COPY BEGIN 8001419c [NEEDS HUMAN REVIEW] -->

## 11c — Change access, existing

Same sheet for someone already on a limited date — it opens on their locked date, not today. The
consequence of moving them up to Everything is stated on the row itself, before they tap it.

<!-- COPY END 8001419c -->

<!-- COPY BEGIN 89a4602d [NEEDS HUMAN REVIEW] -->

## 12 — Pairing

Superseded, and kept only for the device list at the bottom. There is no pairing step: iCloud
Keychain carries the identity to every device on the same Apple Account, so a new device signs
its own key and enrols itself. The list is what shipped; the six-character comparison above it
was removed.

**Accessibility.** Superseded. Device list rows read name, then this-device, then enrolment date.

<!-- COPY END 89a4602d -->

<!-- COPY BEGIN 71dea34a [NEEDS HUMAN REVIEW] -->

## 13 — Rooms light

Rooms, light. Each accent has a darker light-mode value so the tinted incoming bubble still
holds black text.

**Accessibility.** Same as 02 and 03; only values differ.

<!-- COPY END 71dea34a -->

<!-- COPY BEGIN 53f7e700 [NEEDS HUMAN REVIEW] -->

## 14 — Conversation light

Conversation, light, keyboard up.

<!-- COPY END 53f7e700 -->

<!-- COPY BEGIN c4a81cf9 [NEEDS HUMAN REVIEW] -->

## 15 — Desktop Wall

The Mac is the always-on peer (§3.1), so the desktop layout puts the Outpost in the middle and
the audience — the thing you can only reason about with room to see it — permanently on the
right. Same layout at iPad landscape; the right rail collapses to a sheet at iPad portrait.

**Accessibility.** Full keyboard path through sidebar, list and detail. Focus ring visible on every stop.

<!-- COPY END c4a81cf9 -->

<!-- COPY BEGIN 96bd4441 [NEEDS HUMAN REVIEW] -->

## 21 — Upgrade to Everything

The upgrade warning. Names the person, names the locked date, counts what becomes visible, and
Cancel is the bold default. This is the dialog ADR-P2 calls the most important one in the
product.

**Accessibility.** The irreversible fact is in the button's hint, not only in body text above it.

<!-- COPY END 96bd4441 -->

<!-- COPY BEGIN 132fca7d [NEEDS HUMAN REVIEW] -->

## 22 — Fingerprint

Fingerprint comparison, offered once and never blocking (§6). Skipping is a plain button, not a
nag, and the copy says what checking does and doesn't buy you.

**Accessibility.** Words spoken as words. Offer a compare-again action from the same screen.

<!-- COPY END 132fca7d -->

<!-- COPY BEGIN b9627ef7 [NEEDS HUMAN REVIEW] -->

## 23 — Leave, step 1

Leaving, first question: revoke this room's Outpost access? Both answers are stated as what they
do, and the footnote is the rule that keeps everything else simple — the group grant dissolves
into per-person access either way.

**Accessibility.** Each step announces which step of how many. Review step reads the full consequence list before
the confirm.

<!-- COPY END b9627ef7 -->

<!-- COPY BEGIN 3d4a6a2e [NEEDS HUMAN REVIEW] -->

## 24 — Leave, step 2

Second question, only if they kept access. "Stop at today" pins each person at the current
point; "keep allowing" leaves them where they are.

<!-- COPY END 3d4a6a2e -->

<!-- COPY BEGIN a383525d [NEEDS HUMAN REVIEW] -->

## 25 — Leave, review

The review step. Everyone who still has access, why they still have it, and the same Change pill
from 1k — no forced decisions, just the annotation for people who don't expect it.

<!-- COPY END a383525d -->

<!-- COPY BEGIN 5fbeb629 [NEEDS HUMAN REVIEW] -->

## 26 — Remove a member

Board 26, redrawn — it supersedes the earlier version, which is kept beside it as a retired
alternative. That one stated the forward-only stop and stopped there. Three facts have to be on
this screen and not behind a disclosure, because this is where the decision is made: everyone
who stays gets a new key and the removed person does not, so they stop receiving anything from
now on — and nothing they already collected comes back. The second fact is the one people assume
the opposite of. Removal is also visible to the room, since a member list that quietly shrinks
is worse than one that says what happened.

**Accessibility.** All three facts are spoken before either button. The check and info glyphs are decorative; the
sentences carry the meaning.

<!-- COPY END 5fbeb629 -->

<!-- COPY BEGIN 9e9d06e5 [NEEDS HUMAN REVIEW] -->

## 27 — Lost my devices

"I no longer have my other devices" (ADR-P4), reachable on a new device before any other setup.
You still hold your identity, so you sign this yourself — no authority is involved and the
screen says so.

**Accessibility.** Nominated friends are a list with names, not avatars alone.

<!-- COPY END 9e9d06e5 -->

<!-- COPY BEGIN fb6a8a11 [NEEDS HUMAN REVIEW] -->

## 28 — Keys are gone

Keychain reset (OQ-7) — rare, unrecoverable, and presented as a plain explanation rather than an
error. Two columns: what survived, what didn't.

**Accessibility.** The one screen that must not soften: the loss is stated in the heading, so it is the first thing
spoken.

<!-- COPY END fb6a8a11 -->

<!-- COPY BEGIN 94321f9f [NEEDS HUMAN REVIEW] -->

## 29 — Social recovery

Social recovery in progress: signers, the mandatory seven-day delay, and the cancel path that
makes collusion loud. Shown from the device that still holds the identity — which is who needs
to see it.

**Accessibility.** Signer list reads name and what they can and cannot do. Destructive action carries its own
confirming hint.

<!-- COPY END 94321f9f -->

<!-- COPY BEGIN e196ec61 [NEEDS HUMAN REVIEW] -->

## 30 — Locked

The in-app lock. Nothing on screen but the mark — no room names, no counts, nothing worth a
glance over your shoulder.

**Accessibility.** Reachable with the lock engaged; the unlock control is the first focus.

<!-- COPY END e196ec61 -->

<!-- COPY BEGIN 46ad61c2 [NEEDS HUMAN REVIEW] -->

## 31 — Composer

Outpost composer. The audience is stated above the text, not buried behind a button, because it
changes per person and the count is the only thing you would want to check before posting. With
nobody added yet the rail says so in the same place, plainly.

**Accessibility.** Audience is read before the text field. Post button disabled state announces why.

<!-- COPY END 46ad61c2 -->

<!-- COPY BEGIN ddebf2e7 [NEEDS HUMAN REVIEW] -->

## 32 — Comment thread

A post and its comments. Comments are entries like any other, so they carry the same delivery
honesty at the bottom of the thread.

**Accessibility.** Depth announced as a level, not conveyed by indent alone.

<!-- COPY END ddebf2e7 -->

<!-- COPY BEGIN d479327f [NEEDS HUMAN REVIEW] -->

## 33 — Storage

Storage and retention per room (E9) — the 500-image case. Retention is per room because that's
where the heavy rooms are, and deleting local media never deletes anyone else's copy.

**Accessibility.** Sizes spoken in full words. Retention control is a value picker, not a slider.

<!-- COPY END d479327f -->

<!-- COPY BEGIN 8ce64a0e [NEEDS HUMAN REVIEW] -->

## 34 — Rooms with pins

Unfiltered. Two pins on top in the order you dragged them, then everything else by recency. The
pin reads as a subscript badge on the avatar — same weight as an edit badge — so a pinned room
still looks like a row.

**Accessibility.** Pinned is announced as a trait on the row, since the badge sits on the avatar.

<!-- COPY END 8ce64a0e -->

<!-- COPY BEGIN 890d700f [NEEDS HUMAN REVIEW] -->

## 35 — Rooms filtered by tag

Filtered by Projects. Pinned rooms carrying the tag stay on top; the rest still sort by recency.
The count line replaces the sync line while a filter is on, so it is obvious the list is not the
whole list.

**Accessibility.** Filter row is a tab list; the active filter is announced on entering the list, so the shorter
list is not mistaken for missing rooms.

<!-- COPY END 890d700f -->

<!-- COPY BEGIN 80ee1f0c [NEEDS HUMAN REVIEW] -->

## 36 — List menu

The menu behind the ellipsis. Four items and no more: create, join, edit the list, manage tags.
Search is a separate icon because it is the one thing you reach for mid-thought.

**Accessibility.** System menu semantics. No custom trap.

<!-- COPY END 80ee1f0c -->

<!-- COPY BEGIN 49b4e6b0 [NEEDS HUMAN REVIEW] -->

## 37 — Edit list

Edit list. Pin toggle on the left, drag handle on the right, and the handle only appears here —
the list is never draggable by accident. Pinned rooms drag against each other; the unpinned
block stays on recency and shows no handle. Swipe reveals Leave.

**Accessibility.** Swipe actions also reachable from the row's actions rotor. Leave carries a confirming hint.

<!-- COPY END 49b4e6b0 -->

<!-- COPY BEGIN ec6f4974 [NEEDS HUMAN REVIEW] -->

## 38 — Room tags

Tags for one room. Multi-select, with a new tag created inline from the field. The footer states
the privacy fact once, plainly, where the decision is being made.

**Accessibility.** Reorder available as move-up and move-down actions, not drag only.

<!-- COPY END ec6f4974 -->

<!-- COPY BEGIN 55519ebb [NEEDS HUMAN REVIEW] -->

## 39 — Manage tags

Manage tags. Rename, reorder the filter rail, delete — deleting a tag removes it from your rooms
and nothing else. Counts are local counts.

<!-- COPY END 55519ebb -->

<!-- COPY BEGIN 875f658a [NEEDS HUMAN REVIEW] -->

## 40 — Rooms light with pins

Light. The pin badge takes a white ring instead of black, so it still separates from the avatar.

**Accessibility.** As 34.

<!-- COPY END 875f658a -->

<!-- COPY BEGIN 0859b8e9 [NEEDS HUMAN REVIEW] -->

## 41 — Outpost feed

The Outposts tab now opens on the feed: everything from everyone whose Outpost you can read,
newest first. The rail is the way into a single wall, and it is honest about who is behind — a
dimmed avatar has nothing new because that peer hasn't synced.

**Accessibility.** Rail is a list with names; entering a wall announces whose it is.

<!-- COPY END 0859b8e9 -->

<!-- COPY BEGIN f1d267e5 [NEEDS HUMAN REVIEW] -->

## 42 — Someone's Outpost

One person's wall, reached from the rail. The line under the name is the reciprocal fact you
can't get anywhere else: what they can see of yours. Comments carry reactions too, and the
composer has an emoji key.

**Accessibility.** Both directions of access are read as two separate facts, never merged into one.

<!-- COPY END f1d267e5 -->

<!-- COPY BEGIN 5c4b552b [NEEDS HUMAN REVIEW] -->

## 43 — Reaction picker

Tap the smiley on the reaction row: your five most recently used emoji appear first, with a plus
that opens the system emoji picker. A visible trigger is reachable under VoiceOver and leaves
the long press to the system's own menu, which is what the menu below is. Same bar on comments.

**Accessibility.** Trigger is a button labelled Add reaction. Each emoji is labelled by name. Plus announces that
it opens the full picker.

<!-- COPY END 5c4b552b -->

<!-- COPY BEGIN 813250f3 [NEEDS HUMAN REVIEW] -->

## 44 — Message reactions

The same reactions in a room. A reaction is an ordinary entry in the log, so it syncs, backfills
and revokes like any message — and a reaction from a peer who hasn't synced yet simply isn't
there.

**Accessibility.** Summary spoken as "two people clapped", not as glyphs and digits.

<!-- COPY END 813250f3 -->

<!-- COPY BEGIN 9940b9d3 [NEEDS HUMAN REVIEW] -->

## 45 — You

The third tab finally has a page. Your own wall lives at the top of it, so the Outposts tab can
be about everyone else. Everything below it is a thing you own: identity, devices, what leaves
the phone, and what you paid for.

**Accessibility.** Grouped list with headers. Fingerprint spoken as words.

<!-- COPY END 9940b9d3 -->

<!-- COPY BEGIN 2d0e33be [NEEDS HUMAN REVIEW] -->

## 46 — Desktop feed

Both sidebar sections collapse from their headers — Outposts open here, Rooms folded to a count
so a long list can't push the feed out of reach. All Outposts is a destination above the
individual walls, and the right rail is the selected post's thread, where reacting and
commenting happen without leaving the feed.

**Accessibility.** Column order follows reading order; sidebar collapse is keyboard reachable.

<!-- COPY END 2d0e33be -->

<!-- COPY BEGIN 2d25d206 [NEEDS HUMAN REVIEW] -->

## 51 — Messages, split

The Messages tab in the default arrangement. One person per row, no sender chip — the name at
the top of the row is the only name it could be from. Tags run across DMs too.

**Accessibility.** Tab labels are Messages and Rooms. Nothing distinguishes the two lists by icon alone.

<!-- COPY END 2d25d206 -->

<!-- COPY BEGIN fd683f1e [NEEDS HUMAN REVIEW] -->

## 52 — Rooms, split

The Rooms tab beside it, unchanged from turn 3 apart from the dock. The stacked bubble is the
Rooms icon; the plain one is now Messages.

<!-- COPY END fd683f1e -->

<!-- COPY BEGIN c19f5425 [NEEDS HUMAN REVIEW] -->

## 53 — Blended inbox

One list, sorted by recency, pins still on top. A group shows two quiet marks: the avatar rests
on a second disc offset behind it, and the preview is prefixed by whoever spoke. Direct messages
have neither, so the difference is legible without reading a single label.

**Accessibility.** A group is announced as a group — the offset second disc is decorative, so the trait carries it.
Sender prefix is part of the preview sentence.

<!-- COPY END c19f5425 -->

<!-- COPY BEGIN 4ad9d716 [NEEDS HUMAN REVIEW] -->

## 54 — Inbox setting

The setting, on the You page. Two rows with a picture of each, defaulting to separate. Nothing
moves except the dock and the lists — no conversation changes, nothing re-syncs.

**Accessibility.** Two options as a radio group; each option's description is part of its label. The two pictures
are decorative.

<!-- COPY END 4ad9d716 -->

<!-- COPY BEGIN e787bfc2 [NEEDS HUMAN REVIEW] -->

## 55 — Rooms, empty

The rooms list before there is a room. Both ways in are given equal weight, because neither is
the obvious one: you either make a room and invite somebody, or somebody has already sent you a
code. The line underneath is the only place the sync row would have been, and with nothing to
sync it is simply absent.

**Accessibility.** Both actions are equal buttons in reading order. The empty state is a static message, not a live
region.

<!-- COPY END e787bfc2 -->

<!-- COPY BEGIN ba2a3108 [NEEDS HUMAN REVIEW] -->

## 56 — Feed, empty

The Outposts feed with nobody in it. Access is an allow-list in both directions, so an empty
feed means nobody has added you yet — which is stated as the mechanism rather than as a
shortfall. Your own wall is still on the rail and still writable; the rail is where the count of
who can see it lives.

**Accessibility.** Explains the mechanism, so it must be spoken in full rather than truncated to a heading.

<!-- COPY END ba2a3108 -->

<!-- COPY BEGIN d0197497 [NEEDS HUMAN REVIEW] -->

## 57 — Collecting earlier messages

A room you have just joined, backfilling. The row under the navigation bar names the peers it is
waiting on and what it is doing, because a count with no names cannot be told apart from a
stall. Messages already collected are readable underneath — the screen is never blocked — and if
a peer never comes back the row says that instead, in the same place.

**Accessibility.** Live region announcing progress at most once every few seconds, naming peers. Never a
percentage.

<!-- COPY END d0197497 -->

<!-- COPY BEGIN a869a3f6 [NEEDS HUMAN REVIEW] -->

## 58 — Send failure

A message that would not go. The failure sits above the composer, beside the words it refused to
send, rather than in a modal that has to be dismissed before you can read them. The bubble keeps
its text and takes an outline instead of the accent fill, so the state is a shape and not a
colour, and the reason is the real one: there is nowhere to leave it yet, not that it was
rejected.

**Accessibility.** The failed bubble announces "not sent" as part of its label. The inline failure is a live region
with the retry and delete actions after it.

<!-- COPY END a869a3f6 -->

<!-- COPY BEGIN 7c5e7456 [NEEDS HUMAN REVIEW] -->

## 59 — Access review, prompt

You have joined a room and it has people in it you have never decided about. Until you resolve
this, they have no access to your Outpost — so the prompt can afford to wait, and it does: a row
above the conversation rather than a sheet in front of it. Anyone you had already given access
to keeps it; the prompt counts only the people it has no answer for.

**Accessibility.** Non-blocking, so it is announced once and does not steal focus from the conversation.

<!-- COPY END 7c5e7456 -->

<!-- COPY BEGIN d3e49274 [NEEDS HUMAN REVIEW] -->

## 60 — Access review, sheet

The review itself. Per person is the default because access is per person everywhere else in the
app, and the two blanket buttons at the bottom are shortcuts through the same rows rather than a
separate mode — tapping one fills every row in and leaves it visible, so you can still change
one afterwards. Somebody who already had access is shown with where it came from and cannot be
revoked from here, because this sheet is about a decision you have not made yet.

**Accessibility.** Each row reads name, then current access, then the action. Blanket buttons announce that they
fill every row rather than replacing the list. At the largest sizes each row stacks its action
below its name.

<!-- COPY END d3e49274 -->

<!-- COPY BEGIN a602cd14 [NEEDS HUMAN REVIEW] -->

## 61 — Outposts off

Outposts turned off. The tab goes away entirely rather than staying as a shell explaining
itself, so somebody who does not want a wall stops being asked about one — and the access prompt
in a new room stops appearing with it. Turning it back on restores whatever access list you had;
the switch does not decide anything on your behalf.

**Accessibility.** The switch announces the consequence — tab hidden, nothing deleted — in its hint.

<!-- COPY END a602cd14 -->

<!-- COPY BEGIN a26a4784 [NEEDS HUMAN REVIEW] -->

## 62 — Outpost access, allow-list

The access list, revised for the default that now holds: no access, for everybody, until a
decision is made. It supersedes the earlier version of this screen, which showed a room-shaped
grant and implied that sharing a room was enough. The list is ordered by the people it has no
answer for, then by what you granted, so the thing needing attention is at the top rather than
sorted alphabetically into the middle.

**Accessibility.** Two sections with real headers, so "not decided" and "allowed" are navigable groups rather than
an ordering a sighted reader infers.

<!-- COPY END a26a4784 -->

<!-- COPY BEGIN fba12584 [NEEDS HUMAN REVIEW] -->

## 63 — Reciprocal access

Someone else's wall, carrying the fact you cannot work out from anywhere else: what they can see
of yours. The two directions are independent and the screen shows both at once, because the
common misreading of an allow-list is that it is a handshake. Changing your side is one tap from
here; changing theirs is not yours to do, and there is no control implying otherwise.

**Accessibility.** The direction you cannot change is announced as read-only with the reason, so no one hunts for a
missing control.

<!-- COPY END fba12584 -->

<!-- COPY BEGIN 82bdd260 [NEEDS HUMAN REVIEW] -->

## 64 — Notification content

Four rungs, each shown as the banner it produces rather than described in the abstract, because
what a person wants to know is what will appear on the lock screen. The paragraph at the bottom
is the part that changed since this was first drawn: the banner is built on your own device
after it decrypts the message locally, so nothing readable ever crosses the network — but the
finished banner goes into the operating system's notification store, and this app cannot reach
in and remove it afterwards. Choosing a lower rung is the only way to keep something out of that
store.

**Accessibility.** Radio group; each rung's sample banner is part of that option's label. The store caveat is
spoken with the group, not left as a trailing footnote.

<!-- COPY END 82bdd260 -->

<!-- COPY BEGIN 4bfc92af [NEEDS HUMAN REVIEW] -->

## 65 — Notification, one room

The same choice for a single room, in that room's settings. It follows the default until you say
otherwise, and the row states which default it is following rather than showing a blank — a per-
room override that reads as unset is the most common way people end up believing they configured
something. Muting is here too, as the case that has nothing to do with disclosure.

**Accessibility.** The follow-my-default row announces which default it is following, so the value is never blank.

<!-- COPY END 4bfc92af -->

<!-- COPY BEGIN 067c82bb [NEEDS HUMAN REVIEW] -->

## 66 — Welcome, first panel

Panel one of five. The tour's job is not to sell the idea but to set an expectation that the
rest of the app depends on — messages live in the sender's own iCloud and are collected from
there, which is why a room can be quiet for a day and then arrive all at once. Skip is present
from the first panel and stays present, because somebody who already knows this should not have
to pay five taps for it.

**Accessibility.** Each panel is a page in a paged container announcing "panel 1 of 5". Skip is reachable first,
not last. Dots are decorative.

<!-- COPY END 067c82bb -->

<!-- COPY BEGIN 86caa9cd [NEEDS HUMAN REVIEW] -->

## 67 — Welcome, last panel

Panel five, which is where the tour has to stop promising and start pointing. It keeps the
sentence about finding this again later because the affordance now exists — a question mark in
the navigation bar of every tab root, drawn in 8c . The panel also states the one limitation
people discover on their own and find alarming: there is no account to recover, so losing every
device is a real loss, and the recovery screens are the answer to that rather than this panel.

<!-- COPY END 86caa9cd -->

<!-- COPY BEGIN b9cdba89 [NEEDS HUMAN REVIEW] -->

## 68 — How this works

The affordance the tour promises, and where it goes. A question mark sits in the navigation bar
of each tab root and opens this: the tour's five panels as five plain sections, plus the
questions people actually arrive with, which are all variations on "where is my message". It
answers in the app's own terms and never suggests that support could look something up, because
there is nothing to look at.

**Accessibility.** Questions are a list of links; the short version is read before them.

<!-- COPY END b9cdba89 -->

<!-- COPY BEGIN 3d90e155 [NEEDS HUMAN REVIEW] -->

## 69 — Checking for a registration

The blocking screen while iCloud Keychain is still delivering an identity that already exists on
another device. It can hold indefinitely, so it cannot be a spinner with no words: it says what
it is waiting for, what makes it finish, and — after a minute — what to check, in the order
worth checking. The bottom option is the only escape and it is deliberately last, because
starting fresh here abandons an identity that is probably about to arrive.

**Accessibility.** Held indefinitely, so it announces once on appearing and again only when the numbered advice
appears. Never a looping spinner announcement.

<!-- COPY END 3d90e155 -->

<!-- COPY BEGIN e449e48f [NEEDS HUMAN REVIEW] -->

## 70 — Device synced

Shown once, the first time a second device enrols itself with no setup step at all. It exists to
answer "how does it know?" before that question turns into suspicion, and to make the one thing
that follows from it explicit: a device that can be signed into your Apple Account can become a
device that reads your rooms, so the list is worth a look. Nothing here is a confirmation,
because the enrolment already happened.

**Accessibility.** Announced on appearing, since nothing the person did opened it. Device list rows read name and
enrolment.

<!-- COPY END e449e48f -->

<!-- COPY BEGIN 86c6ecd7 [NEEDS HUMAN REVIEW] -->

## 71 — Integrity

The one screen in the app that reports something genuinely wrong. Three classes of event, each
stated as what the device did rather than as an alarm: an entry whose signature did not check
out, an entry a peer offered that we refused, and a feed belonging to somebody who is not who it
claims to be. Refused entries are the ordinary case and mostly mean an out-of-date peer; a
signature failure on an existing member is the one worth reading twice, so it is the one
carrying a date, a room and a name. There is nothing to tap because there is nothing anybody can
do to the entries — they were never accepted.

**Accessibility.** Three groups with headers and counts in the header. Each entry reads room, date, then what the
device did — no entry is presented as actionable.

<!-- COPY END 86c6ecd7 -->

<!-- COPY BEGIN 882c5fda [NEEDS HUMAN REVIEW] -->

## 72 — Redeem an invite

The joiner's side, which board 07 never drew. The field is a sheet with room for a long code and
it accepts a paste without any tidying up on the person's part. What it says before they commit
is the part that matters: joining hands your key to everyone in the room, and it hands you their
history from whatever point the inviter chose — a fact you cannot discover afterwards, so it is
stated here.

**Accessibility.** Paste field accepts any whitespace. Scan is a separate labelled button. The consequence block is
read before Continue.

<!-- COPY END 882c5fda -->

<!-- COPY BEGIN c677a88d [NEEDS HUMAN REVIEW] -->

## 73 — Verify the phrase

The joiner's half of the phrase comparison. Three words, read out loud on a call or in person,
and the two answers carry equal weight — refusing is a plain button, not a red one, because most
mismatches are somebody reading the wrong line rather than an attack. The screen says what a
mismatch would mean without dramatising it, and says plainly that skipping is allowed and what
it costs.

**Accessibility.** Words spoken as words. Match and no-match are equal-weight buttons; skip is a third, clearly
labelled with what it forgoes.

<!-- COPY END c677a88d -->

<!-- COPY BEGIN 1c1b43cc [NEEDS HUMAN REVIEW] -->

## 74 — New room

A sheet rather than an alert, because the name field is not the only thing on it. The admission
policy is set here, at the moment the room is made, by the only person who can set it — and it
is a real choice with a stated default rather than a setting to be found later. Nothing is
invited yet; the room exists first and the invite is a separate act.

**Accessibility.** Name field first focus; the policy radio group follows with each option's description in its
label.

{: .warning }
> **Overruled 2026-09-01.** The app puts the policy behind an understated *advanced setup* toggle
> rather than inline as drawn here. The board's reasoning is recorded and answered in
> [Design](../design.md#where-the-app-departs-from-a-board) — do not "fix" the app back to
> this board without reading it. Board 75 below is unaffected.

<!-- COPY END 1c1b43cc -->

<!-- COPY BEGIN cdd7cecf [NEEDS HUMAN REVIEW] -->

## 75 — Admission policy

The same control after the fact, in room settings, where it has to carry one more sentence than
it does at creation: a change to who may invite is itself a message, and it takes effect on each
device as that device collects it. That is the whole reason this is not described as a
permission — nobody is enforcing it centrally, and the screen says so instead of implying a
guarantee it cannot make.

**Accessibility.** Announces who set it and whether you may change it, so a read-only state is never mistaken for a
broken control.

<!-- COPY END cdd7cecf -->

<!-- COPY BEGIN ee7f53c8 [NEEDS HUMAN REVIEW] -->

## 76 — Delete for me

Hiding a message on this device. The label says what it does and the paragraph refuses the
reading people bring to it: this removes the message from your screen and from no one else's,
and the app cannot reach the copies other people already hold. It hides on every device of
yours, because a message you have hidden reappearing on your iPad is the failure people would
actually notice.

**Accessibility.** The quoted message is part of the sheet's label. Hide carries the "nobody else is affected" fact
as its hint.

<!-- COPY END ee7f53c8 -->

<!-- COPY BEGIN 7d848148 [NEEDS HUMAN REVIEW] -->

## 77 — Show hidden messages

The reversal, and the one screen in the set that is deliberately less informative than it could
be. It is a count, not a list: naming what was hidden would undo the hiding for anybody reading
over a shoulder, which is most of why people hide things. Restoring is all-or-nothing per room
for the same reason, and the messages return to their original places in the log rather than
arriving at the bottom as if they were new.

**Accessibility.** Deliberately a count. The count is spoken; the messages are not enumerated, and that omission is
stated so it does not read as a loading failure.

<!-- COPY END 7d848148 -->

<!-- COPY BEGIN 149d9548 [NEEDS HUMAN REVIEW] -->

## 78 — Block someone in a room

Blocking somebody who is already in a room with you. The mechanism exists — it is the same one
that decides who is handed a new key — so this is a screen rather than a system, and it does two
separable things that the screen keeps separate: you stop collecting what they send, and they
stop being handed your future keys. The middle paragraph is the honest limit: everyone else in
the room still receives them, and you will see the room move without seeing why. Leaving the
room is offered here because for most people that is the thing they actually meant.

**Accessibility.** Two effects announced as two facts. The limit — they stay in the room — is spoken before the
buttons.

<!-- COPY END 149d9548 -->

<!-- COPY BEGIN cc6e3bfd [NEEDS HUMAN REVIEW] -->

## 79 — Report a message

Reporting, which had no board and which the app cannot do the way people expect. There is
nowhere to send a report to, so the report is composed on the reporter's own device and sent as
ordinary mail, and this screen shows the whole attachment before it goes — the message, who sent
it, when it was collected, and the room's name — because a person about to disclose something
should be able to read what they are disclosing. Nothing is sent silently and nothing is sent
unless they choose to send it. Blocking is offered alongside, since it is the part that has an
immediate effect.

**Accessibility.** The attachment table is a list of labelled value pairs, read in full before the send action,
since it is the disclosure.

<!-- COPY END cc6e3bfd -->

<!-- COPY BEGIN 21797b8f [NEEDS HUMAN REVIEW] -->

## 80 — Devices

Board 12 with its pairing half removed. There is no six-character comparison and no setup step:
iCloud Keychain carries the identity to every device on the same Apple Account, so a new device
signs its own key and enrols itself, and this list is where that becomes visible. It is a record
rather than a control — the only action is to stop trusting a device you no longer have, which
takes effect for people as their devices collect it.

**Accessibility.** Rows read name, this-device, enrolment and last activity. Fingerprint spoken as words.

<!-- COPY END 21797b8f -->

<!-- COPY BEGIN 0607caca [NEEDS HUMAN REVIEW] -->

## 81 — Compare again

The standalone comparison, reachable from any member at any time — the case board 22 left out,
which drew only the check offered at the moment of joining. It states when you last checked and
what has happened since, because a comparison is only worth anything against a date. Marking
somebody verified is a note to yourself and the screen says so; nothing about the room changes.

**Accessibility.** Both fingerprints labelled by whose they are. The last-checked date is spoken with them.

<!-- COPY END 0607caca -->

<!-- COPY BEGIN 366e9393 [NEEDS HUMAN REVIEW] -->

## 82 — Fingerprint changed

The case nothing in the set covered: a member you had checked now has a different fingerprint.
It is stated as an event with a date rather than an accusation, because the ordinary cause is
somebody reinstalling after losing every device — and the app genuinely cannot tell that apart
from the alarming cause. So it gives the two readings plainly, in order of likelihood, and
offers the action that resolves it: check again, in person or on a call. The room keeps working
meanwhile; nothing is blocked on the strength of a suspicion.

**Accessibility.** Old and new are labelled was and is — the strikethrough is decoration and cannot carry it. Both
readings are spoken in order of likelihood.

<!-- COPY END 366e9393 -->

<!-- COPY BEGIN 97d8c3b2 [NEEDS HUMAN REVIEW] -->

## 83 — App icon

The icon picker, built without a board and included here so the set covers what ships. Seven
icons on the seven accents, plus a plain one for a home screen that should not announce what the
app is — which is the only reason this feature is worth having, and it is stated on the screen
rather than left as an inference.

**Accessibility.** Each tile is a button labelled by name, with selected state. Tiles are images, so the mark
inside them is decorative.

<!-- COPY END 97d8c3b2 -->

<!-- COPY BEGIN 560c28e5 [NEEDS HUMAN REVIEW] -->

## 85 — System navigation bar

Ruling 11, drawn: the tab roots go back to a system navigation bar with its large title, and the
sync line becomes its own row directly beneath it rather than something crammed into the bar.
That is what unblocked the reversal — the line was the reason given for building a custom
header, and as a separate row it can wrap at accessibility sizes, carry a second sentence when
it needs to, and disappear entirely when there is nothing to report, none of which it could do
inside a bar. The search field is the system's too, in the place the system puts it.

**Accessibility.** System bar brings its own behaviour. The sync row is a live region announcing once, and is
absent from the accessibility tree when there is nothing to report.

<!-- COPY END 560c28e5 -->

<!-- COPY BEGIN 53c82259 [NEEDS HUMAN REVIEW] -->

## 86 — Delivery marks

Ruling 4, which the app invented and the record accepted with three changes. The unlit mark is
an outline rather than a dim fill, so the pair differs in shape and not only in brightness. The
second mark reports that a device said it displayed the message, which is a smaller claim than a
person having read it, and the label says the smaller thing. And because reporting that at all
is a disclosure the reader makes about themselves, it is opt-in — which means a sender needs to
tell a mark that will never light from one still waiting, so that is a third state with a shape
of its own.

**Accessibility.** The specimen. Spoken as "Collected. Not yet shown." — never a count of lit marks, never the word
read. Not-reported speaks that it will not change. The marks are not tappable: they are part of
the bubble's own label, so they need no hit area of their own.

<!-- COPY END 53c82259 -->

<!-- COPY BEGIN a1e61a31 [NEEDS HUMAN REVIEW] -->

## 87 — Bubbles, buttons, fields

Rulings 7, 8 and 9 in one sheet, because all three are cases the set never drew and the app
therefore decided alone. The bubble radius is clamped to the bubble's own height, so a one-line
bubble is not a lozenge and a tall one keeps the full corner. A disabled button is a neutral
fill rather than a dimmed accent, which stops it reading as an available primary action — and
its label still has to clear the contrast floor against that fill, so dimming the fill is not
licence to dim the text with it. A text field has an explicit fill and a border, because fields
drawn lightly were being missed as tappable, and the border is an interface edge the audit can
measure at 3:1.

**Accessibility.** Reference sheet. Disabled buttons announce unavailable and why; fields announce their label,
value and focus separately.

<!-- COPY END a1e61a31 -->

<!-- COPY BEGIN 0cb1a713 [NEEDS HUMAN REVIEW] -->

## 88 — Reactions, tap to open

Ruling 5, split between the two. The trigger is a visible smiley on the reaction row, as the app
built it — discoverable, reachable under VoiceOver, and it leaves the long press to the system's
own menu instead of competing with it. Five recent emoji first, as drawn. The plus now opens the
system emoji picker rather than the fixed list the app shipped, because a hand-maintained list
ages every time the Unicode set does and a one-person project should not own that.

**Accessibility.** Trigger labelled Add reaction, reachable without a gesture. Existing reactions are one summary
element, not five. Emoji buttons draw at 38pt and the chips at 30pt, both extended to a 44pt
tappable region — the drawn size is the disc, not the target.

<!-- COPY END 0cb1a713 -->

<!-- COPY BEGIN 8535a58f [NEEDS HUMAN REVIEW] -->

## 89 — Tinted bars

Ruling 2. The wash on the navigation and tab bars is a taste rather than something everyone
should share, so it is a switch, and it sits beside the colour that drives it with a preview of
what it does. It ships off. The amendment the record added is the part that matters here: a
tinted bar changes what every label and separator on it is composited over, so the washed bars
enter the contrast audit as their own surfaces at all seven accents — sixteen tests become
thirty-two, or the wash is clamped to an opacity that cannot push a pair below the floor.

**Accessibility.** The two previews are labelled Plain and Tinted; the switch announces the consequence. Tinting
changes no label's contrast obligation. Swatches are the same component as board 05 — 40pt
drawn, 44pt tappable, each labelled by name.

<!-- COPY END 8535a58f -->

<!-- COPY BEGIN ef9a8044 [NEEDS HUMAN REVIEW] -->

## 90 — Audience rail

Ruling 6, which went to neither side. The app was right to delete "Visible to no one yet." from
under the composer — an empty audience is not a failure and should not be narrated on a first-
run screen. But somebody typing into their Outpost on day one still needs to know whether they
are writing into a void, so the answer moved to the audience rail and became a fact about who
will collect this rather than a warning about who cannot. Both states are drawn here, because
the rail is the same component either way.

**Accessibility.** Read before the text field in both states. The empty state is a fact about who will collect,
never phrased as a warning.

<!-- COPY END ef9a8044 -->

<!-- COPY BEGIN 33b5da43 [NEEDS HUMAN REVIEW] -->

## 91 — Light mode rules

The rules that take any board in this set into light without drawing it twice. Four surfaces and
one accent value: the ground sits below a raised content surface, exactly as ruling 1
established for dark, so the structure is identical in both appearances and only the values
change. The accent switches to its light-mode measurement — verdigris is #17877C rather than
#34A79B — because the dark value does not clear 4.5:1 on a white surface. Incoming bubbles keep
the accent tint; sent bubbles keep the solid fill and white text. Separators and field borders
are the two edge cases the audit measures at 3:1 rather than 4.5:1.

**Accessibility.** Reference sheet. Every swatch has its value as text beside it, so the specification does not
depend on seeing colour.

<!-- COPY END 33b5da43 -->

<!-- COPY BEGIN 90b3c9ef [NEEDS HUMAN REVIEW] -->

## 92 — Rooms, light

The rules from 10h on a real screen, which is the only way to check that they hold. Rows sit on
the white content surface above the grouped ground, the sync row keeps its place beneath the
navigation bar, and the unread dot stays a dot — present or absent, never a colour difference
doing the work. Nothing about the layout changed between appearances, which is the point of
defining light as values rather than as a second set of drawings.

**Accessibility.** As 02. Unread remains a dot that is present or absent and is announced either way.

<!-- COPY END 90b3c9ef -->
