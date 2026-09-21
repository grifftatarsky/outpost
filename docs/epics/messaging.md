---
title: Messaging
layout: default
parent: Roadmap
nav_order: 1
---

# Getting a message there

{: .no_toc }

Getting a message from one person to another, reliably, and saying honestly how far it got.

1. TOC
{:toc}

## Where this stands

Rooms, invites with a verification phrase, messages sealed under a room epoch key and exchanged
through the mailbox, surviving relaunch, with marks derived from what actually happened: all of it
proven between two Apple Accounts. A device also notices history it is missing and asks for it, and
a message that has not gone says so where it was sent.

Since 2026-09-20 a round hands each reader only what they are allowed to read, and an entry's
envelope names only the conversation it belongs to. Both are held by the suite and neither has run
between two accounts.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="messages-between-two-people-through-the-mailbox">
<summary><b>Messages between two people, through the mailbox</b> — Complete (tested)</summary>

**Story.** As a member, I want what I write to reach the people I wrote it to, so that the app is a
messenger and not a notebook.

**Acceptance criteria**

- **Done.** A message is sealed under the room's epoch key on the sending device and left in the sender's
  own iCloud, addressed to a rotating tag per recipient.
- **Done.** The recipient collects it, verifies the chain, folds it, and acknowledges so the sender can
  delete it.
- **Done.** It arrives with the recipient's app closed, in order, once.
- **Done.** Two sends in immediate succession both arrive, in order.
- **Done.** It survives a relaunch on both sides.

**Testing**

- Suite: the sync, fold, replica-race and stranded-packet suites. The in-memory mailbox stores wire
  fields and counts every server operation, so a test that says "writes nothing" counts everything.
- Two accounts, 2026-09-01: introduce and join, send each way, send with the app closed, two in
  succession. All passed; see [what has actually been observed](#what-has-actually-been-observed).
- Owed, hardware only: a send across a UTC midnight boundary; three sends with the network off,
  then restored.

<details markdown="1">
<summary>Record — the silent defects this closed</summary>

Each of these was a message silently not arriving, and none was visible from inside the app:

- **Addresses rotate daily and readers only asked for today's.** A message written before midnight
  and collected after it was addressed to an address nobody was listening on. Readers now look back
  a week.
- **The sent frontier advanced to the whole replica.** A message typed while a sync was in flight
  was marked sent without being in the packet, and never offered again.
- **The ring flag was cleared by any round that wrote anything.** A message arrived and nobody was
  told.
- **A keychain group that was declared but not effective** made every read throw, which killed the
  send and cleared the composer.

Three more were fixed to reach the two-account proof, none of which the suite could see: the room
menu offered no way to invite anybody, the code the app shares was in a format its own paste field
refused, and a room stopped being a room the moment a second person joined it.

</details>

</details>

<details markdown="1" id="delivery-marks-and-who-reports">
<summary><b>Delivery marks, and who reports</b> — Complete (tested)</summary>

**Story.** As a member, I want to know whether what I said arrived and was seen, so that I am not
guessing, and without the app guessing on anybody's behalf.

**Acceptance criteria**

- **Done.** An unlit mark is an outline; a filled one is a disc. Shape, not brightness.
- **Done.** The second mark says a recipient's *device* displayed the message, never that a person read
  it. Spoken as *"Collected. Not yet shown."*
- **Done.** Reporting is opt-in and off by default. A recipient who does not report is shown with a third
  shape, a dashed outline, whose label says it will not change.
- **Done.** A message with nobody to send it to says so rather than staying invisibly pending.
- **Done.** The marks are not controls; the detail is reached from the bubble's own actions.

**Testing**

- Suite: the delivery-mark and read-receipt suites; `deliveryMarks` rebuilds the sender's own
  messages field by field, because a `Message` field has been dropped on the way to the screen
  three times.
- Two accounts: "does not report" seen 2026-09-01 with receipts off on Beta; sent, delivered and
  read seen both ways 2026-09-05.

**Design.** Ruling 4.

<details markdown="1">
<summary>Record — the amendments, the state opt-in forces, and two defects</summary>

**Done 2026-08-18.** Three amendments to the first drawing, all built.

**Shape, not brightness.** The first version drew two discs and lit them, which carries the whole
meaning in how bright a 6pt dot is, the same failure as saying it with color.

**The label says the smaller thing.** The word "read" appears nowhere a member can see.

**Reporting is opt-in**, because it is a disclosure the reader makes about themselves; nothing else
in this app reports one person's behavior to another.

**The state that opt-in forces.** A sender needs to tell a mark that will never light from one still
waiting, so there is `notReported`. That needs the recipient to say they do not report, which is two
things: the **setting**, private, on `MemberPreferences` over the sibling feed, reaching no peer; and
the **policy**, an entry in every room, disclosing the policy and never an event. Silence means not
reporting: "has never said" and "said no" are the same fact, and the app must not read silence as
*we do not know yet*.

**"I send a message and it disappears", 2026-08-19: two defects, both fixed.** The transcript never
scrolled to your own message: `defaultScrollAnchor(.bottom)` places the first frame and nothing
after, so an appended message landed below the visible region. From the composer that is exactly a
dropped send. Pinned with `.defaultScrollAnchor(.bottom, for: .sizeChanges)` and an explicit scroll
on your own send. And a message with nobody to send it to drew nothing, forever: the frontier only
advances when a packet is written, and with no peers none is, so every solo message stayed
`pending`, which is invisible. The frontier is correct and was not changed; `pending` split, and
`noRecipients` is drawn as a plane that cannot take off.

</details>

</details>

<details markdown="1" id="a-round-bigger-than-a-packet">
<summary><b>A round bigger than a packet</b> — Complete (tested)</summary>

**Story.** As a member sending a burst, I want all of it to go, so that a round the server would
refuse does not lose everything in it.

**Acceptance criteria**

- **Done.** A round is batched under seven hundred kilobytes per packet.
- **Done.** The frontier advances only over entries in packets that landed.
- **Done.** A packet failing after another succeeded keeps what was written, rings nobody, and sends the
  rest next round. The first packet failing fails the round, because nothing was written.

**Testing**

- Suite: `PacketCapTests`, four cases.
- Real CloudKit, 2026-09-14: a 24-entry round arrived complete and in write order (`LiveRoundTests`).

<details markdown="1">
<summary>Record</summary>

A photo entry carries a six-kilobyte preview, and a hundred and seventy of them in one round made a
packet over the megabyte the app then believed was CloudKit's limit. The ceiling turned out to be the
app's own ([Decisions](../decisions.md#the-record-ceiling-is-the-apps-own-and-cloudkit-never-asked-for-it)),
and it stays, because a round that large is a bad round whatever the server allows. Built 2026-09-04. The vector-clock
frontier cannot represent a gap, so `unsentEntries()` is sorted per feed before batching; that was
the defect the tests found.

</details>

</details>

<details markdown="1" id="the-rendezvous-heals-a-dead-share">
<summary><b>The rendezvous heals a dead share</b> — Complete (tested)</summary>

**Story.** As a member whose peer's mailbox share stopped working, I want the two of us to find each
other again without either of us doing anything, so that a quiet peer is a quiet peer and not a
dead channel.

**Acceptance criteria**

- **Done.** An offer carries a keyed digest of its URL; a standing offer is rewritten when the digest no
  longer matches and left alone when it does.
- **Done.** The reader retracts an offer whose URL the server rejects as unknown.
- **Done.** The offer write reports written, standing, unplaced and failed; a failed save is a failure.
- **Done.** The fetch line names the reachable zones by owner.

**Testing**

- Suite: `ShareOfferTests`, including the digest.
- Two accounts, 2026-09-04: a share dead all day healed on the first round after the fix, and
  twenty-four packets arrived. 2026-09-05: rotated on purpose with the debug row; retracted within
  a minute, re-offered on relaunch, accepted, a message each way delivered and read.

**Detail.** [The rendezvous heals itself](../decisions.md#the-rendezvous-heals-itself) ·
[the rig procedure](../simulator-rig.md#a-quiet-peer-is-usually-a-dead-share).

</details>

<details markdown="1" id="a-round-acknowledges-every-packet-it-can">
<summary><b>A round acknowledges every packet it can</b> — Complete (tested)</summary>

**Story.** As a recipient of many packets at once, I want one that cannot be acknowledged not to
hold the rest, so that a sender's outbox drains and marks do not lag a round for nothing.

**Acceptance criteria**

- **Done.** Every settled packet is acknowledged; failures are collected and reported by name.
- **Done.** The transport treats only "unknown item" as absence; any other error is thrown as itself.

**Testing**

- Suite: `RoundAcknowledgementTests`.
- Real CloudKit, 2026-09-14: a 24-packet round settled and the outbox emptied (`LiveRoundTests`).

</details>

<details markdown="1" id="solos-a-conversation-with-one-person">
<summary><b>Solos: a conversation with one person</b> — Complete (tested)</summary>

**Story.** As a member, I want a conversation with one person to be its own thing rather than a
room I named after them, so that the common case is not the awkward case.

**Acceptance criteria**

- **Done.** Separate by default: Solos and Rooms tabs; a switch merges them into one Messages tab.
- **Done.** In the merged list a group carries a second disc; a solo carries neither disc nor sender.
- **Done.** The same delivery and read marks as a room.
- **Done.** Long press previews the last few messages over Pin, Mark as Read, Silence and Leave.
- **Done.** A solo is started from a person: the compose button on Solos (or *Solo* in the compose menu
  when merged) opens a picker of everybody this device knows; one tap founds it and invites them.
- **Done.** It is a solo on both devices from the moment it is made, not once the other person accepts,
  and each side titles it by the person it is with — by their shared name where names are shown,
  by their code otherwise; never by the viewer's own name.
- **Done.** An empty Solos tab offers *Send a Solo*.

**Testing**

- Suite: `SoloTests` — listed as a solo on both sides, titled by the other person under both name
  settings, the greeting names the person, an old profile reads as a room, the picker honors
  *Show others' names*. The rooms-list organization and preferences suites; the mute-store fix has
  its own.
- Device: beta started a solo with alpha on 2026-09-05; alpha accepted; both list it under Solos,
  each titled by the other's code, and a message went each way.

**Design.** Boards 51/52 (split), 53 (blended), 54 (the setting). The brief called them mutually
exclusive as tab arrangements; one is the default and the other is the switch. The row departs from
board 53: no sender in the preview, and the metrics are Messages' own — see the record.

<details markdown="1">
<summary>Record — what was built, and a control that did nothing</summary>

**Solos, 2026-09-05.** A two-person conversation is called a *solo* (Griff's word) and is founded as
one: `RoomKind.solo` rides the first profile entry, `Projection.kind(of:)` reads it from that entry
alone so a later profile cannot change it, and `RoomSummary.isDirect` is set from it rather than
guessed from a headcount. Each device titles a solo by the person it is with, per its own name
setting; the founder's stored name is only a fallback for the moment before the invitation is in the
roster. The first *Send a Solo* on the rig, an hour before this landed, made an ordinary room named
"Griff" on beta — exactly the awkward case the story describes — which is what prompted the kind.

**The split and the merge, reviewed 2026-09-06.** Six things a solo inherited from being a room
and should not have: the search field said *Search rooms* over the Solos tab (per scope now); the
merged list's empty state offered *Make a room* alone (both starts now, and the description names
both); *Edit list* on the Solos tab listed every room (the tab's own conversations, under the
tab's own name); the conversation's bar read *2 members* under the other person's name (nothing,
as Messages); the ⋯ menu offered *Who is in this room* and *Who gets in* for a solo (neither; the
phrase check and Notifications stay); the greeting introduced a solo as a room with a member list
and an admissions policy (*Started a solo with you*, and nothing else); and the leave
confirmation said *Everybody in Outie will see that you left* (the person, by name). And one line the
row left behind: the Inbox page's description of the merged list still said a group is marked *by
the name of whoever spoke*, which the row stopped doing on 2026-09-05. A seventh, the same evening:
the transcript named the other person over every run of theirs, as a room must; a solo's title
already says who, so the runs no longer do (`showsRunAuthors`, off for a solo). What that review
also noticed and left, with the reason, is in the inbox: a seen mark carries the reader's latest
receipt time rather than their first.

**The row, 2026-09-05.** Measured against Messages on the same simulator: a 45 pt avatar, an 8 pt
gutter with the 10 pt unread dot in it, text starting 84 pt in, a 17 pt semibold title, a 15 pt
preview held to two lines with the space reserved, a chevron. The pill carrying the last sender's
name is gone; Messages does not name the sender in the list, and the pill read as a tag. A room
nobody has spoken in says *No messages yet* rather than collapsing to one line. Compose is its own
toolbar button on the left, as in Messages: on Solos it opens the picker, on Rooms the new-room
sheet, and in the merged list a menu offering either.

A direct message is a room with two people in it, `RoomSummary.isDirect`, rather than a second kind
of thing with its own sealing path and roster. The stacked disc is drawn **opaque with a ring of the
ground between the two**: an avatar's fill is translucent, so two overlapping discs brighten where
they cross and read as a Venn diagram. A stack occupies exactly one avatar's footprint, the offset
taken out of the front disc, so mixed rows keep a common baseline.

**The setting is its own screen** (board 54) under Appearance: two options as a radio group, each
with a picture of the dock it produces, and its description inside the label. It left the rooms
list's toolbar menu deliberately: row size is a property of that list; where a conversation is filed
changes the dock.

**Two board discrepancies fixed on the way.** Board 52 names the Rooms icon as the stacked bubble;
the app had a two-person glyph. Board 53 requires a group to be *announced* as one; the second disc
is decorative, so without a trait a screen reader heard a room and a direct message identically.

**Long press, 2026-08-20.** The platform's gesture: a glass-lifted preview of the real bubbles over
Pin, Mark as Read, Silence and Leave. **Silence** rather than "hide alerts", because the app says what
it will stop doing; **Leave** rather than "delete", because one person cannot delete a conversation
for everybody. Silenced and pinned are badges at opposite corners of the avatar, drawn the same way:
an accent disc with the glyph knocked out. With avatars off, the marks are drawn flat in the accent
beside the name; they are facts about the row, not decoration on the avatar.

**This found a control that did nothing.** There were two mute stores, and every mute control wrote
the one the notification extension did not read. Muting drew a bell and silenced no notification.
The organization's flag is deleted; silence means what it says.

</details>

</details>

<details markdown="1" id="sending-feels-like-sending">
<summary><b>Sending feels like sending</b> — Complete (proved above the mailbox)</summary>

**Story.** As a member, I want the app to acknowledge what I did the moment I do it, so that it
feels like a messaging app rather than a form.

**Acceptance criteria**

- **Done.** A failed send keeps the words in the field, says why above the composer beside them, and
  offers retry and delete. The reason shown is the real one.
- **Done.** **A send that cannot go anywhere says so.** A full iCloud and a signed-out account are told
  apart from each other and from everything the app retries by itself, and each is named on the
  rooms list with its fix in the same sentence. The words are kept and go on the first round that
  works. Griff, 2026-09-12: the app is working exactly as designed, and the copy must not imply
  otherwise.
- **Done.** **↵ writes a second line and the arrow in the field sends.** Griff's ruling, and it is a
  criterion rather than an absence because this was built the other way once: `.submitLabel(.send)`
  on a vertical `TextField` renames the key, takes the newline away, and still does not submit.
  Measured, then reverted. `.onSubmit` is for the Mac.
- **Done.** A message animates into the transcript; dropped under Reduce Motion.
  `ConversationView+Transcript` carries `.transition(.opacity)` on the row and a `.bouncy` animation
  on `messages.count`, both `nil` under `accessibilityReduceMotion`. This read **Not done.** until 2026-09-14,
  when the code was read.
- **Done.** 2026-09-16. **A message is only pending when nobody has it**, and it says so where it was sent.
  `NotGone.notices` considers only this member's own messages that are `.pending` or `.sent` —
  anything collected by anybody has gone, and `.noRecipients` keeps its own mark. Ruled 2026-09-14;
  see [Decisions](../decisions.md#a-message-is-only-pending-when-nobody-has-it).
- **Done.** The mark is raised by one of two signals: more than one **newer** message of this member's in the
  room has been collected while this one has not, or the room's chosen time has passed. Newer
  messages are counted in one pass from the newest back, so it costs nothing a render notices.
- **Done.** The mark is an orange information circle that **replaces** the delivery marks on that message —
  on any message in a run, not only the last. Tapping it opens a sheet saying whether it has left
  this phone or is waiting in the member's iCloud, which signal raised it, when it was sent, and
  that it keeps trying. Orange is a palette token, `notGone`: `#B35000` light and `#FF9F0A` dark,
  held to 4.5:1 on both transcript grounds by `ContrastAuditTests`. The hit area is 44pt; the layout
  is the glyph's, so it sits where the delivery marks sit.
- **Done.** The time is per room, on the room's sheet under **Messages that have not gone**: *After 1 day*
  to *After 7 days*, or *Only when newer ones arrive first*, which leaves only the newer-messages
  signal. It is a `MemberPreferences` entry, so it follows the member to their other devices. A room
  nobody has set uses **three days** — Griff ruled the range, not the default; see
  [Decisions](../decisions.md#a-room-that-has-not-chosen-waits-three-days).
- **Done.** The explanation carries a quiet *Change when this is shown*, which closes the sheet and opens the
  room's.
- **Done.** The reason a send is refused reaches the conversation: the `cannotSend` sentence is shown above
  the composer, with an iCloud symbol, and leads the explanation sheet too.

**Testing**

- Suite: `NoRoomToSendTests` for what a member is told and that nothing is lost;
  `MailboxRefusalTests` for reading a `CKError` without an account, including the refusal nested in
  a partial failure. The rest of the failure path is exercised by the mailbox-failure suites.
- Suite: `NotGoneTests`, ten — waiting is ordinary until the room's time; one newer collected message
  is not proof and two are; somebody else's messages are not evidence; anything collected has gone;
  *nobody to send to* keeps its own mark; off leaves only the proof; the days clamp to one to seven;
  the choice survives encoding and a merge; and a real session marks a message three days on, in
  both the message list and the transcript, and stops when the room is set to off.
- Rig, 2026-09-16, alpha: the room sheet's new section reads *After 3 days*; the page lists the eight
  choices; choosing *After 5 days* moved the check and the row read *After 5 days* on return. The
  mark and its sheet were seen in the debug demo Solo, which carries one waiting message, because
  alpha's only room has nobody to send to.
- Rig, 2026-09-17, above the mailbox: Quad's app closed, Trig wrote *are you still there*, and Trig
  relaunched four days on (`--clock-ahead-days 4`). The message carried the orange mark, and tapping
  it opened *Not sent yet* — waiting in iCloud, more than three days, when it was sent, *See who this
  room is waiting on* and *Change when this is shown*.
- Rig, 2026-09-17, above the mailbox, with `--mailbox-refuses full` and then `signed-out`: the message
  stayed, and under it *Your iCloud is full, so there is nowhere to leave what you write. Free some
  space in Settings and it will go on its own.* — and the signed-out sentence the same way. Launched
  again without the flag, the three refused messages went on their own. **It found the rooms list's
  half had never been drawn**: *Nothing is going out* was built into the rooms list on 2026-09-13 and
  the phone never handed it the reason, so it only ever appeared in the conversation. Wired, and seen
  on the rig. The mapping from CloudKit's errors to these two is `CloudKitMailbox.refusal(for:)`, with
  its own suite; a really full or signed-out iCloud is still unseen, and needs a simulator signed out or a full account.

**Design.** Board 58 for the failure. The send animation is undrawn; transitions are not in the set.

</details>

<details markdown="1" id="per-room-read-reporting">
<summary><b>Per-room read reporting</b> — Complete (tested)</summary>

**Story.** As a member, I want to report reading in one room and not another, so that the opt-in is
not all or nothing.

**Acceptance criteria**

- **Done.** The setting can be set per room: follow my usual answer, report here, or never report here.
  It sits beside that room's notification level, on the sheet the conversation menu already opens.
- **Done.** The room's own `readPolicy` entry is written when the answer changes, so the people in it are
  told — and only when the effective answer actually changed, so switching between two settings that
  mean the same thing writes nothing.
- **Done.** A room that has said nothing follows the member's usual answer, and **changing the usual answer
  does not overrule a room that has its own**. A per-room answer is a decision about that room; the
  global switch is the default behind it.
- **Done.** Turning reporting on everywhere skips the rooms that have their own answer, rather than
  announcing a policy those rooms will not honor.

**Testing.** `PerRoomReportingTests`: a room following the usual answer, one room reporting while
another does not, a room's answer surviving a change to the usual one, and clearing a room's answer
to put it back to following.

The board requires opt-in and does not require per-room, so this is a narrowing rather than a miss,
but the read-by detail view assumes it.

</details>

<details markdown="1" id="the-read-by-detail-view">
<summary><b>The read-by detail view</b> — Complete (tested)</summary>

**Story.** As a sender, I want to see who has collected and who has shown a message, so that the
two marks have a place to be explained.

**Acceptance criteria**

- **Done.** Reached from the message's own actions, never from the marks, which are not controls: it is a
  section on the detail screen the bubble's menu already opens.
- **Done.** Lists each recipient's state in the words the marks use, and in only three states, because per
  person that is the whole of what the log knows: **shown** with a time, **nothing yet**, and **does
  not report**. There is no per-person *delivered* — collection is acknowledged per packet, not per
  reader, and claiming otherwise would be the app inferring delivery.
- **Done.** Shown first, then waiting, then the people who will never report — so the answer a member is
  looking for is at the top and the ones that will never change are at the bottom.
- **Done.** A room lists everybody else; a solo lists the one person. Griff, 2026-09-12.
- **Done.** The section is only drawn on this member's own messages.
- **Done.** Where nobody in the room reports, the footer says so rather than leaving three dashes to read as
  a wait.

**Testing.** `WhoHasReadItTests`: the default where nobody reports, a reader who does and the time
that comes back, a reader whose cursor has not reached the message, a solo, the sender never being
in their own list, and the ordering.

</details>

<details markdown="1" id="repairing-a-history-with-holes-in-it">
<summary><b>Repairing a history with holes in it</b> — Complete (tested)</summary>

**Story.** As a member, I want my device to notice that a message never arrived and ask for it, so
that a gap in a conversation is something the app fixes rather than something I discover months
later.

**Acceptance criteria**

- **Done.** A device can compute, per room, which entries it is missing from each member's feeds
  (`Replica.gaps(from:)`): every position below a feed's highest held or claimed number that
  nothing occupies, on every device each member has.
- **Done.** A member can ask for a repair against one person or everyone in the room: *Check for missing
  history* in the conversation's menu, a submenu in a room and one button in a solo.
- **Done.** Progress shows at the top of the conversation while it runs — *Asking Alice and Bob for
  anything this device is missing…*, then who answered and who is still waited on — and on
  completion it names who was checked and counts what is still missing, split into what nobody
  asked holds and what was sent and did not arrive.
- **Done.** A soft-deleted message is not reported missing. A withdrawal and a hiding are each a further
  entry, never an absence, so a hole is unambiguously a gap (`softDeletesLeaveNoHole`).
- **Done.** A request is the size of what is missing, not of the history: the holes as spans, one clock of
  heads, and the room. Finding the holes is one pass over the log in memory, uncached; that is
  what a check costs today, and a hole once filled is not looked for again because it is no longer
  a hole.
- **Done.** The **Resend everything** debug action is gone, with its session method and its test.
- **Done.** A hole nobody asked about is chased anyway: two minutes after it stops looking like a packet
  in flight, quietly, at most once an hour per room, at most one outstanding request at a time.
- **Done.** A refusal no later credential can lift — an entry signed by a known device outside the window
  it was allowed to sign in — is recognized rather than retried for ever: it settles its packet, is
  recorded, is left out of later requests, and is counted in its own words.
- **Done.** Naming the holes is incremental, a per-feed contiguous mark kept where entries enter, rather
  than a walk of the whole log on every read.
- **Done.** A reader let into an Outpost asks its owner for it, by whose wall rather than by which room.

**Testing**

- Suite, `HistoryRepairTests`: a vanished packet is named as one entry of the right feed and the
  writer has no hole; a withdrawn and a hidden message are not holes; a repair recovers the entry,
  reports who was checked, does not move the answerer's frontier, and can be dismissed; a tail no
  clock mentioned cannot be named and is still recovered through the heads; a peer that lacks it
  says so and the report counts it; a member who joins late is handed the room and learns who else
  is there; a repair outlives a relaunch. Requests and answers ride the sealed body and a body
  without them still opens.
- Rig, 2026-09-06: alpha checked its solo with beta. *Asking Outie…* on alpha at 20:12:08, the
  request packet written two seconds later, beta's log answering at 20:12:12, and alpha reading
  *Checked with Outie. Nothing is missing.* on its next tick. The question and the answer cross
  CloudKit; there was nothing to fill.
- Real CloudKit, 2026-09-14: a packet deleted off the server was named as one missing entry, asked
  for, and the words came back (`LiveRoundTests`).

**Design.** Board 57 (Collecting) covers the progress state: a live region naming peers, never a
percentage. The completion is one sentence in the same place, dismissed by the member; there is no
separate list of missing messages, because a missing entry has no words to list until it arrives.

<details markdown="1">
<summary>Record — what a request carries, why it rides the packet, and two defects it uncovered</summary>

**The log makes this exact.** Entries are numbered from one per feed without gaps, so a device
holding 1–5 and 7 knows it lacks 6, and every entry's clock says what its author had seen when they
wrote it, so a clock naming a feed at 9 while this device holds it to 7 is proof that 8 and 9 exist.
`Replica.claimed` merges every integrated clock for that reason. What neither can name is a tail no
later entry has mentioned — the last packet of a quiet feed — so the request also carries the
asker's *heads*, and the peer sends everything it holds beyond them.

**A repair rides the packet, never the log.** A log entry is forever and reaches everybody; a
request is for one peer and over once answered. So `RepairRequest` and `RepairAnswer` travel in the
sealed packet body beside the entries, decoded field by field so a build that predates them still
opens the packet. The entries that answer a request are ordinary entries in the same packet; the
answer says the one thing they cannot: what the peer *does not* hold, and its own heads, so the
asker can tell *sent and not arrived* from *nobody has it*.

**Never into the frontier, and never into the round's count.** An answer re-sends entries to one
peer, and the sent frontier is one mark per feed for every peer; advancing it over an answer would
mark entries sent that most peers never got — the message-loss bug one path over. Repair packets go
out after the round's frontier and delivery marks are settled, are not recorded as outstanding, and
are not added to the round's report, whose `entriesSent` is what the frontier moved over. An answer
also leaves out whatever the same round's ordinary send just wrote to everyone, and a request takes
its heads at the moment it goes out rather than when it was started, since the round has just
collected.

**Two defects the three-member test found**, neither visible with two accounts:

1. *The third member of a room was handed a room with one other person in it.* The sent frontier is
   global, so what the inviter had forwarded to the second member before the third existed — the
   founding, the second member's admission, and with it the keys the second member's entries verify
   against — was never offered to the third. A joiner now asks the inviter for the room the moment
   they accept, quietly: the request names the room, the inviter sends everything in it from every
   feed past the joiner's heads, and the record is dropped once answered rather than drawn.
2. *A joiner two epochs in could not read the founding.* A grant carried one link, on the argument
   that the rest are in the log — and they are, inside `epochChange` entries each sealed under the
   epoch *before* the one it announces, so the entry carrying the next link down was always sealed
   under a key the joiner did not have yet. The second member could read everything; the third could
   read nothing before their own arrival. A grant now carries every link the granter holds, which is
   opaque without the newer secret and costs a few hundred bytes. And a round that integrates
   entries into a room whose chain has not reached the beginning walks the keys back again, since
   the links can now arrive after the key.

**What is honest and what is not.** A peer that has not answered is *waiting*, however long ago it
was asked; the app does not guess when a phone will be turned on. *Still missing* is counted at the
moment it is read, from the log and the answers, never carried. A hole in a revoked device's feed
after its revocation would be asked for and refused forever, and is not handled.

</details>

<details markdown="1">
<summary><b>A packet carries only what its reader may read</b> · Complete (tested)</summary>

**The story.** A device should hand over only what its reader is allowed to read. Not seal it and
trust the app not to draw it — not send it.

**What it was.** A round collected every entry this device had not yet sent, across every room and
solo, sealed them into one body, and wrapped that body's key for every peer. The addressing was per
recipient and correct; the contents were global. History repair leaked the same history a second way:
`Replica.fill` served a named author's log whole, ignoring the room the request named, and the answer
never consulted the asker's history floor.

**Measured before any change**, 2026-09-20: a three-member fixture put a second room's entries on a
device that was never in it, and a member invited from today held nine sealed entries from before
they were let in.

**Acceptance.**
- No entry reaches a peer for a conversation they are not in.
- Nothing at or below a joiner's history floor reaches them.
- Somebody removed or gone gets nothing sealed after the key turned on them.
- A member never ends up asking, forever, for history nobody will hand over.

**What holds it.** `RepairScopeTests`, three cases, each red before the fix.

**What is owed.** Two Apple Accounts on the rig. Nothing crossing the network is proven by the suite.

</details>

<details markdown="1">
<summary><b>The envelope names only its own conversation</b> · Complete (tested)</summary>

**The story.** An entry's payload is sealed. The envelope around it is not, because that is how an
entry moves with no server in the middle. So the envelope must say as little as it can.

**What it was.** `AppSession.append` stamped `replica.frontier` — every log the device held, across
every room and Outpost, as person and device — in the clear and inside the signature. One message
from a room you share told you how many other conversations its writer keeps, who is in them, and how
far each had got. Three other things went to every peer: the public keys of everyone this device had
met, their device certificates, and the list of whose Outposts this member follows. Repair heads were
taken across every conversation.

**Acceptance.**
- A clock names only the conversation its entry was written in.
- A packet names only people its reader already shares something with.
- A wish to be told about an Outpost names only the person whose Outpost it is.
- Repair heads stop at the edge of the conversation asked about.
- Nothing on disk or on the wire changes shape.

**What holds it.** `EnvelopeLeakTests`, five cases, each red with its own fix reverted.

**What is still legible.** A position number is counted per device across every conversation. Closing
that needs a separate hash chain per conversation, which would let a device drop or reorder its own
history without anyone being able to tell. In [the inbox](../inbox.md), undecided.

**What is owed.** Two Apple Accounts on the rig.

</details>

</details>

## What has actually been observed

**Observed** means seen on both devices, not inferred from a log line or a passing test. Two Apple
Accounts, two simulators, against the live container.

<details markdown="1">
<summary>2026-09-21 — a log per conversation, across two accounts</summary>

Alpha on account A as Trig, beta on account B as Quad, both accounts cleared first. Every step on
the build that splits the log per conversation and adds attestations.

| Step | Result |
|---|---|
| Onboard both | **Passed.** Both reached home on their own account. |
| Make a room and invite | **Passed.** Checks made on alpha; the invitation left in the rig directory. |
| Join | **Passed.** The same ten characters, `G8SJ7GCSAD`, on both. |
| Let in | **Passed, after about three minutes.** The rendezvous found beta's offer on the fourth look; beta then received the room's key and the room appeared. |
| Quad speaks | **Passed.** *hello from Quad on account B* reached alpha, and beta's mark moved to *Collected*. |
| Trig answers | **Passed.** *hello back from Trig on account A* reached beta. |
| Attestations | **Passed.** Each device heard about both logs in the room; no contradiction on either. |

Not seen here, only in the suite: a contradiction, a forward-only joiner, and coming back to a
deleted room.

</details>

<details markdown="1">
<summary>2026-09-01 — the first two-account run</summary>

| Step | Result |
|---|---|
| Introduce and join: invite, phrase, admission | **Passed.** Phrase `3S2W45` shown identically on both devices; joiner admitted; room reports two members on both sides. |
| Send from A | **Passed.** Arrived on B, attributed to Alpha. |
| Send from B | **Passed.** Arrived on A, attributed to Beta. |
| Send with the recipient's app closed | **Passed.** Beta's app was terminated for the whole exchange and both messages were there on next open. |
| Two sends in immediate succession | **Passed.** Both arrived, in order. This is the mid-sync race that used to mark the second one sent without putting it in the packet. |
| Send across a UTC midnight boundary | **Not run.** Needs the device clock moved, which a simulator takes from the host. |
| Three sends with the network off, then restored | **Not run.** A simulator uses the host's network. |

**Marks:** a sent message shows the sent mark. Beta has read receipts off, and Alpha's messages show
the "does not report" mark rather than sitting in an ambiguous state. Consecutive messages from one
person group correctly.

**Not observed that day:** whether ringing a peer's bell produces a notification on the other device.
The sender was seen writing the bell and the recipient subscribing to it. Griff saw a banner arrive on
a phone on 2026-09-09. See [Telling someone it arrived](notifications.md).

</details>

<details markdown="1">
<summary>2026-09-05 — after the rendezvous learned to heal</summary>

| Step | Result |
|---|---|
| One member's mailbox share rotated under the other (debug: *Rotate mailbox share*), with that member's app stopped | **Passed.** The other failed to accept the old URL with "Unknown Item", retracted the offer and read one zone, within a minute. |
| The rotated member relaunched | **Passed.** A fresh offer on its first round; the other accepted it on its next and read two zones again. About ninety seconds end to end. |
| A message each way afterwards | **Passed.** Both arrived and both showed delivered and read. |
| Twenty-four packets in one round, one of them unacknowledgeable | **Fixed.** The loop stops at nothing now and names what it could not acknowledge. A 24-packet round was proved over real CloudKit on 2026-09-14. |

</details>

## Test plan

<details markdown="1">
<summary>Two devices, two Apple Accounts</summary>

One account cannot participate in its own share, so a single account can prove the transport and
never the sharing.

**Setup.** Fresh install on both; the log line `storage: … appGroup=true` at launch says the app
group and keychain group are effective. Create a room on A, invite B, verify the phrase out of band,
redeem on B. Sync both until idle.

| # | Do | Expect |
|---|---|---|
| 1 | Send from A | Arrives on B. Marks under A's message go none → first → both as B collects and reads. |
| 2 | Send from B | Arrives on A. Same progression. |
| 3 | Send from A with B's app closed | Arrives when B opens it, in order. |
| 4 | Send from A, then immediately again | Both arrive. The mid-sync race. |
| 5 | Send from A across a UTC midnight boundary, collect on B after | Arrives. The rotation that used to strand messages. |
| 6 | Turn off Wi-Fi on B, send three from A, turn it back on | All three arrive, in order, once. |

**Marks.** A message still on the sending device shows no marks. Opening a room does not light the
second mark on its backlog; scrolling a message into view does. Your own reading never lights your
own second mark. With receipts off on B, A's messages stay at delivered forever.

**Repair.** Send three from A with B closed; delete the middle packet from A's outbox in the
CloudKit dashboard; open B. B's conversation shows the first and the third. *Check for missing
history* on B: the line reads *Asking A…*, then *Checked with A. 1 missing entry arrived; nothing is
missing now.*, and the middle message is in its place. Withdraw one on A and check again on B:
nothing is missing. Not run by hand on two accounts; the same repair was proved over real CloudKit
by `LiveRoundTests` on 2026-09-14.

</details>

<details markdown="1" id="a-draft-that-survives">
<summary><b>A draft that survives</b> — Complete (tested)</summary>

**Story.** As a member, I want what I was writing in a conversation to still be there when I come
back, even after the app was closed, so that leaving a sentence half-written does not lose it.

**Acceptance criteria**

- **Done.** Each conversation keeps one draft. It comes back into the composer when the conversation
  opens again, after the app has been closed or the device restarted.
- **Done.** The rooms list shows it in place of the last message: **Draft**, in the accent, then the
  words.
- **Done.** Sending clears it, and so does emptying the field.
- **Done.** It is written down 0.6 s after typing stops, when the conversation closes, and when the
  app leaves the foreground.
- **Done.** It is sealed on disk. The state file holds ChaChaPoly ciphertext bound to the room, under
  a key kept in this device's keychain and never synced (`DraftSeal`). A copy of the state file without
  that keychain cannot open it. `DraftTests` checks that the words never reach the file readable.
- **Done.** A reply from a banner that could not be sent joins the conversation's draft on a new line,
  and the not-sent notification says so rather than repeating the words.
- **Done.** Deleting a conversation deletes its draft.

- **Done.** A new post and a comment on any post keep a draft the same way, by one shared modifier
  (`keepsDraft`), and **Delete drafts** in Outpost settings deletes them after asking.

**Not in this ticket.** Photos staged on a new post are not kept, only the words. Drafts stay on the
device they were written on; they do not follow the member to their other devices.

**What was observed, 2026-09-19, on gamma.** Trig typed into Checks and went back: the row said
*Draft half a thought 46250*. The app was quit and opened again: the row still said it, and the
composer held the words. Sending cleared the row. `RigChecks.testDraftSurvives`. A new post, cancelled
and reopened, held its words; Outpost settings showed *Delete drafts 1*, deleted it after the
confirmation, and the next new post was empty. `RigChecks.testOutpostDraftsAndIcons`.

</details>

**What would falsify the epic.** A message that arrives twice. A message that never arrives and is
not reported missing. A mark that claims delivery or reading that did not happen. Any of those is
worse than a crash, because the app looks fine while it is wrong.
