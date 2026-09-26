---
# COPY BEGIN 3dd8f935 [NEEDS HUMAN REVIEW]
title: Rooms and membership
layout: default
parent: Roadmap
nav_order: 3
---

# Who is in a room

{: .no_toc }

Who is in a room, who can see an Outpost, and how somebody leaves or is put out.

1. TOC
{:toc}

<!-- COPY END 3dd8f935 -->

<!-- COPY BEGIN f5450d90 [NEEDS HUMAN REVIEW] -->

## Where this stands

Creating a room, inviting with a code and a verification phrase, admission by existing members, a
policy set by whoever made the room, a shared roster, putting somebody out and leaving: built and
proven on two Apple Accounts. The asymmetry this page used to name, that a room could be joined and
not left in the other direction, is closed.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

<!-- COPY END f5450d90 -->

<!-- COPY BEGIN 7fa05e34 [NEEDS HUMAN REVIEW] -->

## A room with three people in it

**2026-09-09, and the first time it has been possible.** Two Apple Accounts is a hard stop — a third
needs a phone number Griff does not have — so the third member runs on a simulator with **no Apple
Account at all**, and the transport moves instead: `--mailbox <path>`, a Debug-only flag that puts a
directory on the Mac where CloudKit was. See [the rig](../simulator-rig.md#members-without-an-apple-account)
for what that is and, more importantly, what it cannot prove.

Griff (an account), Outie (a second account) and **Trig** (no account, an erased iPhone 17) are in a
room called **Triangle**. Both joins ran the full round trip over the directory — invitation, the six
characters read off both screens (**7M3HZF** for Trig, **V748WW** for Outie), confirmation, the
inviter folding it, the epoch grant collected. All three devices say *Triangle — 3 members*, and all
three transcripts read the same six lines:

> Griff started Triangle · Griff invited Trig · Trig confirmed the invitation ·
> Griff invited Outie · Outie confirmed the invitation

**Proved above the mailbox. Unproven below it.** Zone routing, share acceptance, the change feed and
push are the seam this replaces, and they stay for UAT, where a third real account exists.

<!-- COPY END 7fa05e34 -->

<!-- COPY BEGIN ba17a578 [NEEDS HUMAN REVIEW] -->

## Tickets

<details markdown="1" id="verification-design-pass">
<summary><b>A design pass over verification</b> — Complete (tested)</summary>

**Queued on purpose and run the day the functionality was proved.** A design pass against half-built
screens reviews the scaffolding, and the notes it produces are about states that are about to change.
Griff's call, 2026-09-08; the pass ran on 2026-09-09.

**Story.** As somebody meeting this feature for the first time, I want the screens that decide who I
am talking to to feel like one idea rather than five, so that the most important thing the app does
is also the clearest.

**What it looked at.** The surfaces the change creates or moves, built one at a time in five stages
— which is exactly the way to end up with five dialects of the same conversation:

- **The phrase, in all four places it now appears**: the inviter's sheet, the joiner's sheet, the
  room's *Who you are talking to*, and the solo's check. One typeface, one grouping, one way of
  saying "read these six characters out loud" — today the invite sheet and the join sheet already
  word it differently.
- **The waiting states**, which are opposite on the two sides and must not look alike: *invited, not
  yet in* on the inviter's, *waiting to be let in* on the joiner's, and the running count under
  `atLeast(n)`.
- **The `Invited` tag and its filter** beside the member's own tags. An app-managed tag sitting in a
  list of hand-made ones is the sort of thing that reads as a bug until it is designed to read as a
  fact.
- **The refusal screen.** The one screen in the app whose job is to be alarming without being
  frightening, and the only one carrying three things at once: what happened, how unlikely the
  frightening reading is, and why the refusal itself was the protection.
- **The solo's five states** — not checked, held, outstanding, confirmed, refused — and whether the
  quiet ones are quiet enough to live at the top of a conversation permanently.
- **Where the expiry and the purge live**, now that they are load-bearing rather than housekeeping.

<!-- COPY END ba17a578 -->

<!-- COPY BEGIN 2d977b66 [NEEDS HUMAN REVIEW] -->

**Acceptance criteria**

- **Done.** Every screen audited against `SettingsChrome`, the native-first rule and the honesty rules, by
  seven readers with one lens each and a second reader per lens checking every finding against the
  lines it quotes. 67 findings, deduplicated to 31, **all of them fixed on 2026-09-09** — twelve
  landed with the pass and Griff asked for the rest the same day.
- **Done.** One vocabulary, listed — the table at the top of the audit. *Code* now means the pasted identity
  blob and nothing else; the phrase is *the characters* on every screen and in every VoiceOver label
  (it was six characters then, and ten since 2026-09-15). Two words are still doubled and say so (findings 19 and 20).
- **Done.** A pass on the rig at `accessibility-extra-extra-extra-large` with Reduce Motion on, both
  accounts, both devices. It found the truncated notice headline, the overrunning six characters and
  the doubled waiting line, all three fixed.
- **Done.** The one finding that was real and not this feature's was fixed rather than parked: the package's
  `LocalizedStringResource` literals resolved against the main bundle, so nine strings would have
  shipped untranslated. `Scripts/lint/localized-resource-bundle.py` now fails the build on a bare
  one.

**Not this ticket.** Behavior. If the pass finds something behaving wrongly rather than looking
wrong, it becomes its own ticket rather than being fixed under this one.

</details>

<!-- COPY END 2d977b66 -->

<!-- COPY BEGIN d61dd61c [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="an-invitation-is-an-offer">
<summary><b>An invitation is an offer, not an admission</b> — Complete (tested)</summary>

Approved by Griff on 2026-09-08, built in stages, and **driven on two Apple Accounts on
2026-09-09** — which is the part that counted, because the defect this answers was invisible to a
green suite. The rig run was part of the ticket rather than a formality, and it earned its keep:
three of the four runs passed first time and the fourth found a defect that stopped the solo check
being reachable at all. See *What two accounts said* below.

| Stage | What | State |
|---|---|---|
| 0 | Pin what a join does today, before anything moves | Done — `InvitationInvariantTests`, all four still green after the change |
| 1 | The wire: `PayloadType.joinConfirmed` and its body | Done — `JoinConfirmationWireTests` |
| 2 | The roster gate and the app path that feeds it | Done — `InvitationIsAnOfferTests`, `JoinIsARoundTripTests` |
| 3 | The screens, both sides, including the refusal warning | Done — proved on two accounts 2026-09-09 |
| 4 | The automatic `Invited` tag and its quick filter | Done — app-managed tags, Griff's call 2026-09-08; the rail's *Invited* pill seen on both devices |
| 5 | Solos — a separate ticket below | Done — proved on two accounts 2026-09-09, after two fixes the run itself found |

**What two accounts said, 2026-09-09.** Griff on an iPhone 17 Pro, Outie on an iPhone 17 Pro Max,
two Apple Accounts, CloudKit between them.

<!-- COPY END d61dd61c -->

<!-- COPY BEGIN 704093d3 [NEEDS HUMAN REVIEW] -->

1. **Refusing refuses.** *Rig One*, an indefinite invitation, the same phrase **K9F4V9** on both
   screens. Outie tapped **They do not match**: the refusal screen is terminal, no room appeared,
   and Griff's copy still read *1 member*. That is the defect this ticket exists for, closed.
2. **Accepting works, and the waiting state appears and clears.** The same invitation, **They
   match**, and Outie's list carried *Waiting to be let in* with the phrase on it until the round
   that admitted them. Both transcripts then read *started* / *invited* / *confirmed the
   invitation*.
3. **Taking an invitation back holds.** *Rig Two*, invited for a day, link already on Outie's
   device, then taken back. Outie's link still read and still matched, Outie confirmed, and has been
   *Waiting to be let in* since — exactly what the alert promises. Griff stayed at *1 member*.
4. **The solo check, both ways.** Outie's *Check who I am talking to first* held the new solo shut
   and raised the question; Griff answered **They match** and it opened on both. Griff then asked
   again with **Hold until it is answered**, Outie answered **They do not match**, and both
   composers closed. Outie tapped **Check again**, Griff confirmed, and both opened.

Two defects the run found, both fixed the same morning:

- **A solo's invitation was created and then dropped**, so the other person was never asked and no
  screen in the app could ask them — the solo check was unreachable on two accounts. Starting a solo
  now shows the invitation on the same sheet a room's *Invite someone* uses.
- **A refusal was permanent.** `SoloCheck.resolve` names one way out — ask again after the refusal
  and have that one confirmed — and no screen ever offered that confirmation, so both people could
  only keep asking. `SoloCheck.answerableAsk` carries the standing question and the refusal card
  offers it.

**Story.** As somebody being invited, I want refusing the verification phrase to actually refuse,
so that the one control against a person in the middle is not decoration.

**What was wrong.** Measured on two accounts, 2026-09-08. B tapped **They do not match** and is
in the room — their copy says *"A added you to this room"*, lists two members and offers to open it.
A's copy says two members. The button is not at fault: reading an invite only inspects it and
refusing only closes the sheet. What admits B is A, because creating an invitation writes B into the
roster, and where an invitation is enough that roster reaches B through ordinary sync.

<!-- COPY END 704093d3 -->

<!-- COPY BEGIN d725a8dc [NEEDS HUMAN REVIEW] -->

**Acceptance criteria**

- **Done.** Creating an invitation does not put the joiner in the roster. A's room counts them under
  *Invited, not yet in* — a second `Section` in `RoomMembersView`, built from `pendingInvitations`
  rather than `RoomRoster.invited` so a lapsed offer is not listed as outstanding.

  **Two sub-states, not the three the mock had.** *Invited. Nothing back yet* and *Confirmed the
  code — waiting to be let in.* There is no *received*: nothing travels from a joiner before their
  confirmation, so it is a claim no device made. See the corrected warning in
  [Who you are talking to](../verification.md).
- **Done.** B is shown nothing about the room — not its name, not its members, not one message — until they
  have confirmed the phrase. True by the caller before this and pinned by a test now
  (`RedeemInviteFlowTests`); it stays a property of the caller rather than of the type, which is
  worth knowing.
- **Done.** **They do not match** discards the invitation and **sends nothing**. Refusing calls nothing at
  all — `JoinIsARoundTripTests` settles six whole rounds to prove the room still has one member in it
  on both devices — and the warning is on the screen where they refused, carrying what happened, how
  unlikely the frightening reading is, and why the refusal itself was the protection.

  **"Permanently" was too strong and is now accurate.** `RedeemInviteFlow.refuse()` is a one-way
  door for the life of the sheet: no transition leaves `.refused`, and the pasted code is dropped.
  Nothing stops somebody pasting the same invitation into a fresh sheet, which is a deliberate act
  and is left available on purpose.
- **Done.** A chooses the expiry when making the invitation, can see what is outstanding, and can purge one
  by hand before it runs out. Folds in *Invitations that are never accepted*.

  The choice was already in the model — `attest` and `invite` have taken an `InvitationLifetime`
  since expiry existed and nothing ever passed one — so that half was a picker. The purge was not:
  `PayloadType.invitationRescinded` = 22 is new, and the room folds it. **It reaches nobody's
  device.** Whoever holds the link still holds it and can still confirm; what changes is that the
  room declines to admit on that invitation, which is the only shape available when the other party
  may be offline or may be the party this exists to protect against.
- **Done.** Confirming runs the room's access rule exactly as it does now — `open` admits, everything else
  waits. The gate is in `RoomRoster.isAdmitted`, ahead of all six rules and touching none of them,
  and `RoomAccessTests` still passes unchanged. Both waiting states are drawn: the inviter's in the
  member list, and the joiner's as a *Waiting to be let in* row at the top of their own list, which
  is a room-shaped state for a room the device does not hold.
- **Done.** `member(x)` where x has left still fails closed, as it does today — `RoomAccessTests`, unchanged.
- **Done.** The phrase stays reachable from the room afterwards, on both sides: *Who you are talking to*,
  in the room's menu, with the date beside each person. *Waiting to join* is now drawn only when
  somebody actually is.

  **The date is when the room recorded the confirmation**, and the screen says so in those words. It
  is not when the other person tapped — no device here saw that — and `RoomRoster.confirmations`
  keeps the earliest entry time so two devices folding in different orders cannot show different
  dates. The joiner's side is answerable only because `PersistedState.acceptedInvitations` is
  append-only: it is their sole copy of the attestation the phrase is derived from.

<!-- COPY END d725a8dc -->

<!-- COPY BEGIN c99dfb49 [NEEDS HUMAN REVIEW] -->

**Wire, as built.** **Two** cases, and neither is a refusal — a refusal still does not travel.
`PayloadType.joinConfirmed` = 21 in stage 2, and `PayloadType.invitationRescinded` = 22 in stage 3,
both in `allKnown` and `plumbing`. The second is the purge this ticket folds in, which was the one
part of *A controls how long an invitation lives* with no model behind it at all.

The claim this paragraph used to make — that an older build would "treat both as plumbing so they
degrade quietly" — was wrong, and the mistake is worth keeping. `isConversation` is a **denylist**,
so a build that has never heard of raw 21 draws it as a message. The two levers are where the entry
is addressed and its `fallbackText`: the joiner's copy goes to their own wall, where an older build
finds no room profile and draws nothing; the relayed copy goes into the room, where an older build
draws one line of fallback text.

**And the round trip.** A joiner holds no key for the room, so the confirmation travels in the sync
packet beside the epoch grants and the inviter relays it in. Two extra sync rounds, and four things
fell out of it that each broke everything on their own — including why it is a packet field rather
than an entry on the joiner's own feed. See
[Decisions](../decisions.md#an-invitation-is-an-offer-not-an-admission).

**Testing, as done.** `InvitationInvariantTests` pinned the old behavior first — one epoch turn per
join, the inviter keeping the joiner's keys, `mayWrite` not becoming the gate, tightening evicting
nobody — and all four survived, which is the signal the change was right rather than merely green.
`InvitationIsAnOfferTests` covers the roster; `JoinConfirmationWireTests` covers the payload,
including two forgery tests written after mutation-proving showed three earlier ones were being
caught by naming guards rather than by the signature check; `JoinIsARoundTripTests` covers the app.

**The rig ran it, four ways, on 2026-09-09** — refuse, accept, take back, and the solo check both
ways — which is what turned this from green to proved. The whole defect was invisible to a green
suite, so nothing but the rig counted. See *What two accounts said* above.

</details>

<!-- COPY END c99dfb49 -->

<!-- COPY BEGIN 2cd2ff31 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="solo-verification">
<summary><b>Solo verification</b> — Complete (tested)</summary>

Approved by Griff on 2026-09-08 in [Who you are talking to](../verification.md), and driven both ways
on the rig on 2026-09-09: held, confirmed, refused, and reopened.

**Story.** As somebody with one conversation per person, I want to be able to check who I am talking
to whenever I like — and to decide in advance whether a stranger's solo opens at all — without the
room's admission machinery, which does not fit two people.

**Acceptance criteria**

- **Done.** One question in the privacy check-up and under Privacy & Safety, drawn as a switch:
  **Check who I am talking to first**, off by default, which is what Messages does. It is and **named by both presets** rather than defaulted, because a preset jumps
  the page that would ask — *As little as possible* turns it on, which is the one place the two
  presets differ in kind.

  {: .warning }
  > **Two claims in this criterion were not buildable as written, and the second is a correction to
  > the design rather than to the build.**
  >
  > *"An incoming solo is held rather than opened"* — what the build holds is the **composer**, and
  > it holds it wherever a write would come from, not only where the text field is. The conversation
  > itself is not hidden: its messages, its banner and its unread mark are unchanged. A state that
  > closed the whole thing would be a fourth `RoomStanding`, folded from the log, and this is not a
  > fact about the log — it is one member's setting.
  >
  > *"The sender is told it is held"* — **it cannot be, and the app does not pretend to.** The ask
  > this member's setting raises is byte-identical on the wire to a curious one, so the other device
  > can honestly say *they have asked to check who you are before carrying on* and nothing more.
  > Saying *held* from that would be reporting an inference as a measurement. Telling them properly
  > would mean announcing a switch on a phone they cannot see. Corrected 2026-09-08 while building.
- **Done.** Either side, from the solo's own menu: **Check who I am talking to**. Both devices show the same
  phrase — the one they already have, from how they met, so nothing new is derived — and either may
  confirm or refuse. The answer is on the quiet line for whoever did not ask, because they are still
  talking and the notice that carries the buttons is not drawn for them.
- **Amended.** The asker chooses what happens to **their own** conversation meanwhile: *Keep talking*, with a
  quiet line saying a check is outstanding, or *Hold until it is answered*, which closes their
  composer. **The transcript is not covered** — only a refusal does that, and *Hold* is this member
  deciding to add nothing rather than a reason to take their own history off their own screen.
- **Done.** **The hold is the asker's own and never the other person's.** Pinned three ways, the strongest
  being a property rather than a boolean: the other person's side must come out *identical* whether
  the asker held or not, so every route to a mutual hold fails it and not only the one somebody
  happens to be looking at.
- **Done.** A refusal blocks the solo both ways and says plainly what it means. Nothing already received is
  deleted — and deliberately not through the block the app already has, which hides everything that
  person ever sent and would erase the evidence.

  **A refusal is never lost**, which took two fixes: a confirmation of a *concurrent* ask reported
  *Confirmed* to somebody who had just been told the characters did not match, and an answer that
  outran its question was dropped when a second answer named the same one.
- **Amended.** Five states, each drawn somewhere a member can find: not checked, held, outstanding, confirmed,
  refused. **Held is two states in the design and two in the build** — a standing setting and a
  choice about one question — kept apart because one is a rule and the other is a decision.

  The date lives on *Who you are talking to*, which shows when the **room** recorded the join
  confirmation. A check made mid-conversation is in the transcript with its own line and is not yet
  on that screen.

<!-- COPY END 2cd2ff31 -->

<!-- COPY BEGIN 0ec3b63e [NEEDS HUMAN REVIEW] -->

**Not this ticket.** Rooms. A solo is exempt from *An invitation is an offer* and from `RoomAccess`
entirely; the two tickets share the phrase and nothing else.

**Testing.** The states and their transitions in the kit; the asker-only hold, which is the one a
reviewer will assume works the other way; and the rig for a phrase matching across two accounts,
which is the only thing that can prove the two devices derive the same one.

</details>

<!-- COPY END 0ec3b63e -->

<!-- COPY BEGIN 11491cbb [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="join-prompt-padding">
<summary><b>Padding on the join prompt's member list</b> — Complete (tested)</summary>

**Story.** As somebody reading who is already in a room I have been invited to, I want the list to
look like the rest of the app.

**What was wrong.** The rows sat in a `VStack(spacing: 0)` and `PersonRow` carries no vertical
padding of its own, so 32-point avatars touched. Seen on the rig 2026-09-08.

**Acceptance criteria**

- **Done.** Rows are spaced the way every other person list in the app spaces them, and the avatars do not
  touch. Ten points between the rows and ten around the stack.

</details>

<!-- COPY END 11491cbb -->


<!-- COPY BEGIN c72d9029 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="setting-up-a-room">
<summary><b>Setting up a room</b> — Complete (tested)</summary>

**Story.** As somebody starting a conversation, I want to name the room, choose how people get into
it, and bring people I already know, so that the room is the shape I meant before anybody is in it.

**Acceptance criteria**

- **Done.** A room's admission policy is chosen when the room is made and defaults without the member
  having to decide. The advanced toggle is off by default; the policy is one tap away and explained
  on demand.
- **Done.** `atLeast` never demands more approvals than there are members, and says so before it is
  chosen: an effective threshold of `min(chosen, memberCount)`.
- **Done.** People can be selected in bulk, and every one still goes through accept-then-confirm. Selecting
  starts an invitation; nobody is put in a room by being selected.
- **Done.** *Superseded 2026-09-08:* an open room asked the inviter to check the phrase without gating. Since
  an invitation became an offer, the person invited confirms the characters before they are in any
  room, whatever its policy; see [An invitation is an offer](#an-invitation-is-an-offer).
- **Done.** The invited person sees who and what they are joining before any history, at the first honest
  moment.
- **Done.** Every preference on the sheet is device-local.

**Testing**

- Suite: the policy threshold and the greeting suites.
- Two accounts: driven 2026-09-01; the invitee's sheet 2026-09-02. Turning the room's key on an
  open invitation was fixed in the same pass.

**Design.** Boards 74 (New room) and 75 (Admission policy), with the advanced-toggle departure recorded
in [Design](../design.md#board-74--the-admission-policy-sits-behind-an-advanced-toggle).

<!-- COPY END c72d9029 -->

<!-- COPY BEGIN 03afc313 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — the sheet, the confirmation an open room used to skip, and "before they join"</summary>

**This came before removing anybody**, and not by preference: removal is decided by the admission
policy, and there was one kind of room whose policy had an empty approver set, so there was nobody a
policy could authorize to remove anyone.

**The sheet**, in Liquid Glass with the system's components: name, first focus; the default options
plainly displayed; a toggle for advanced setup, off by default; a toggle for bringing people in that
remembers its last setting. Advanced setup reveals the policy as a radio group, each option with an
ⓘ that explains on demand, because five policies each with a sentence is a wall. `atLeast` is a
radio plus a stepper, defaulting to 2 and reaching 5 at creation.

**Bringing people in**: everybody this member shares a room with or whose Outpost they can see, a
search field over a list with an index bar, each row an icon, a name or the raw identifier, and a
select control. **Add** creates the room and starts a join for each person selected.

*The next two paragraphs describe the design of 2026-09-01, before an invitation became an offer on
2026-09-08, and are kept as the record.*

**The confirmation an open room used to skip.** `RoomAccess.open` has an empty approver set on
purpose, so every other policy got a confirmation step out of that machinery and the open room got
none. That is right about authorization and wrong about verification, and they are different
questions. So an open room now asks the inviter to check the phrase. It is not a gate and is not
drawn as one: they are in already, the screen says so. Refusing stops that member being rewrapped
the room key from the next epoch on, which is the only remedy that exists, and the screen says that
rather than implying somebody was removed.

**"Before they join" is not buildable, and the sheet is shown at the first honest moment instead.**
A `MembershipAttestation` carries the room's identifier, the two parties' keys, an expiry and a
verification phrase, nothing else. The name, the roster and the policy are entries sealed under the
room's epoch, unreadable until a member rewraps a key, which happens only once the joiner is
admitted; under an open room the invitation *is* the admission. Carrying the roster in the invitation
would hand a room's membership to whoever holds the code, which the product refuses to do. So the
sheet says **"Alpha added you to this room"** and offers **Open**, not Accept and Decline: under an
open room that choice has already been made, and drawing it would be offering a decision that is not
there. `RoomGreeting`, `JoinPromptView`, shown once per device, with the room's settings in full.

</details>

</details>

<!-- COPY END 03afc313 -->

<!-- COPY BEGIN 8288c378 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="removing-somebody">
<summary><b>Removing somebody</b> — Complete (tested)</summary>

**Story.** As a member, I want to put somebody out of a room, so that a room is something I can
correct rather than only add to.

**Acceptance criteria**

- **Done.** Any member of a room may remove any other, including whoever made it, and the removal is an
  entry every device folds.
- **Done.** Removal turns the room's epoch and the removed member is not granted the new key. They keep
  what they already hold, and the app does not claim otherwise.
- **Done.** The removed member's copy says *"You were removed from this room"* in those words, keeps the
  history readable, and blocks the composer. No push, no banner, no message to them from the room.
- **Done.** Two members removing each other resolve the same way on every device: the first remover wins.
- **Done.** Re-admission starts a membership; it never restores one.
- **Done.** Entries from a removed member are refused on the receiving side and not drawn; a removed device
  cannot produce entries for the room.

**Testing**

- Suite: twenty tests over the fold and the session.
- Two accounts, 2026-09-02: all three removal steps passed. Alpha sent after removing Beta; the
  entry reached Beta and drew as *Not readable on this device*; Beta's log shows `installed epoch
  1` ten times and `installed epoch 2` never. Survived relaunch on both sides.
- Owed: the three-participant cases from the audit, listed as their own ticket below.

**Design.** Board 26, redrawn: three facts on the screen, spoken before either button. Everyone who
stays gets a new key and the removed person does not; nothing they already collected comes back;
removal is visible to the room. The destructive fill is the darkened red at 4.86:1.

<!-- COPY END 8288c378 -->

<!-- COPY BEGIN 849d924a [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — what was decided on 2026-09-01, and the audit</summary>

Membership is monotonic on purpose, so removal has to be an explicit act with its own entry:
`removal` is entry type 14.

The reference point was iMessage, checked rather than remembered. Apple documents only the
requirement of four or more people on Apple devices. What is widely reported is that the removed
person sees **"You have left this conversation"**, the same string shown to somebody who left of
their own accord. That is a false statement to a member and this app will not make it.

Decided: anyone may remove anyone, including the founder, because in the default room a founder is
not a role that means anything. The removed person is told in their own copy and nowhere else. Their
copy becomes a historical log. Somebody who left sees the same thing. Messages sent after the removal
are marked undelivered because of it, on the sender's own screen. Anyone may re-add. Whether a newly
admitted member gets all of the history or only what follows them is a room setting that does not
exist yet; the re-add rule and the delete warning defer to it. Not inherited: iMessage's splintering,
which follows from identifying a group by its participant set; a room here has a stable identity, so
the fork cannot arise.

**The audit.** An audit of the removal path predicted nine cross-device failures; five survived
refutation, and none of them is what the two-member run exercised. Two were then closed: nothing on
the receiving side refused an entry from a removed member (`Projection.outOfRoom` decides it from the
log alone now), and `mayWrite` had no call site (`AppSession.append` refuses). One was narrowed: a
member handing the removed device the new key from a stale roster needs a verification failure to
open the window at all, and `grantsOwed` holds that room's keys for a round when one happens. The
rest is the ticket below.

</details>

</details>

<!-- COPY END 849d924a -->

<!-- COPY BEGIN 9026ca40 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="leaving-properly">
<summary><b>Leaving properly</b> — Complete (tested)</summary>

**Story.** As a member, I want leaving a room to be real, so that I do not silently keep receiving
what I meant to stop.

**Acceptance criteria**

- **Done.** Leaving is an entry, `departure` (15), written by the person it is about and by nobody else.
  They leave the roster, may no longer write, what they said stays, what they write afterwards is
  not drawn, and coming back is a fresh join.
- **Done.** It is not a removal and nothing merges the two: two types, two roster maps, two notices, two
  errors.
- **Done.** The leaver does not turn the key. Somebody who stays does, the founder if still here and
  otherwise the lowest identity remaining, named identically on every device.
- **Done.** The confirmation states what will happen; the room says what the leaver keeps: *"You left this
  room. Everything already here is still yours to read."*

**Testing**

- Suite: the departure suites.
- Two accounts, 2026-09-02: Beta left from the rooms list; both copies drew *"Beta left this room"*;
  Alpha dropped to one member and turned the key to epoch 2; Beta stayed on epoch 1.

**Design.** Boards 23–25, of which one step is built. **Decisions.**
[Leaving and being removed are two acts](../decisions.md#leaving-and-being-removed-are-two-acts-and-never-one-with-a-flag)
· [Somebody who stays turns the key](../decisions.md#somebody-who-stays-turns-the-key-after-somebody-leaves).

<!-- COPY END 9026ca40 -->

<!-- COPY BEGIN d0996048 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record</summary>

Leaving used to be a swipe that cleared a pin: membership stayed in the log, the room came back on
the next sync, and everybody else went on addressing packets to somebody who believed they had gone.
The author *is* the subject, which is what makes the entry's signature the whole of the proof. The
leaver must not turn the key because `advanceEpoch` keeps the secret it generates, so they would walk
out holding the key to everything said afterwards. iMessage tells a removed person "You have left
this conversation"; the mirror of that lie is naming a remover for somebody who walked out, and this
app makes neither claim.

</details>

</details>

<!-- COPY END d0996048 -->

<!-- COPY BEGIN a1f77874 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="blocking-a-person">
<summary><b>Blocking a person</b> — Complete (tested)</summary>

**Story.** As a member, I want to stop somebody reaching me, so that a room I cannot leave is still
mine to read.

**Acceptance criteria**

- **Done.** A local, silent block from any message's menu or a member's row: their messages stop being
  drawn at once, in every room, with no network call, and they are not told.
- **Done.** Blocked flags are stamped and follow the member across their own devices; reversible from
  You › Privacy & Safety › Blocked people.
- **Done.** The deny list shipped in the binary is the same mechanism with a switch.
- **Done.** A blocked person stops being handed this member's future room keys. Built 2026-09-14 — a block
  is noticed the way it is noticed everywhere else, by messages that stop arriving, and the app
  never says why. See
  [Decisions](../decisions.md#blocking-stops-the-key-handover-and-stopping-it-is-the-whole-point).
- **Done.** **Their packets stop being collected and acknowledged.** `peers()` filters them, so nothing of
  theirs is fetched and nothing is acknowledged; their app stops being told *collected* and then
  *shown*. This is the whole mechanism — silence is not answering, not merely not drawing.
- **Done.** They are dropped from the Outpost audience, which is the one place a block ends access
  outright: a wall has a single owner and nobody else to hand its key over.
- **Done.** The filter lives at the `CarpenterApp` call sites — `notShutOut(_:)` — and never inside
  `RoomRoster`. The roster is derived from entries every member replays; a local choice inside it
  would make the fold device-specific and two devices would disagree about who is in a room.
- **Done.** Nothing said while somebody was blocked is lost. The sender never had an acknowledgment, so
  the packet is still on offer and comes back on the round after they are unblocked.
- **Changed.** **Blocking does not turn the room's epoch.** Proposed, then dropped on building it: in a group
  every other member re-grants the key, so the turn buys nothing and costs everyone a re-key; in a
  direct conversation not answering has already done it. Recorded rather than left silent, because
  the cost is real — inside a shared room a block is this device refusing to deal with somebody,
  not a wall around what they can read.
- **Done.** Leaving the room offered on the same screen, because for most people that is what they meant.
  2026-09-17: blocking somebody from inside a room you are still in — a message's menu, the member
  list, a solo's check — asks with an action sheet of *Block*, *Block and Leave* and *Cancel*, because
  Apple's Action sheets page is for "choices related to an intentional action". Where there is no
  room to leave — somebody's Outpost, a room you have already left — it stays the alert with *Block*
  and *Cancel*. The room to leave comes from `leavingThisRoom` in the environment, set once where a
  conversation is drawn. Seen on the rig 2026-09-17: holding Quad's message and choosing *Block Quad*
  opened the sheet from the message with *Block* and *Block and Leave*, both red.

<!-- COPY END a1f77874 -->

<!-- COPY BEGIN 7f5d5998 [NEEDS HUMAN REVIEW] -->

**Testing**

- Suite: `BlockingTests`, including that current messages stop being drawn and the mailbox saw no
  packet for it.
- Two accounts: the block menu and the Blocked people screen seen 2026-09-04. A blocked sender's
  message has not been sent at the rig since the block.

**Design.** Board 78: a screen, not a system. **Detail.** [Trust and safety](../trust-and-safety.md).

</details>

<!-- COPY END 7f5d5998 -->

<!-- COPY BEGIN 9d5bcd2f [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="reporting-a-message">
<summary><b>Reporting a message</b> — Complete (operational proof owed)</summary>

**Story.** As a member, I want to report something somebody sent me, so that there is a way to
escalate that does not require me to build one.

**Acceptance criteria**

- **Done.** Composed on the reporter's own device and sent as ordinary mail to the abuse address in the
  build; there is no server to report to and none will be added.
- **Done.** The whole attachment is shown before it goes: the description, the sender's fingerprint, which
  message and when, as labeled value pairs. It never carries the message body or any media, and the
  app cannot attach them.
- **Done.** Nothing is sent silently or unless the member chooses to; the screen does not imply a
  moderation system.
- **Done.** Blocking is offered alongside.

**Testing**

- Suite: the report-composition tests; media is excluded by construction.
- Two accounts: the report sheet seen from a photo's held menu 2026-09-04. The mail send needs a
  mail account the simulators do not have. The abuse address exists and receives mail (Griff,
  2026-09-17).

**Design.** Board 79. **Detail.** [Trust and safety](../trust-and-safety.md), including the
mandatory-reporting obligations and the review reply.

</details>

<!-- COPY END 9d5bcd2f -->

<!-- COPY BEGIN e3b47d62 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="per-person-outpost-access">
<summary><b>Per-person Outpost access</b> — Complete (tested)</summary>

**Story.** As a member, I want to choose who can see my Outpost, person by person, so that my wall
is not defined by which rooms I happen to be in.

**Acceptance criteria**

- **Done.** The model, `OutpostAccess`: an allow-list defaulting to nobody, grants from a date, revocation
  as a stamped false, per-person cross-device merge, and an inherited origin for today's readers.
- **Done.** Posts sealed to the granted people rather than filtered at render time. There was no
  room-shaped grant to remove: a wall's roster is empty and always will be, so the old rule was
  already granting nobody anything.
- **Done.** The migration: there is none to write, and that is the finding rather than a gap. Nobody could
  read any wall before this, so there is no room-shaped reader to mint an inherited grant for. The
  `inherited` origin stays in the model for a migration that a future rule might need.
- **Done.** Granting access to everything is a separate, deliberate confirmation.
- **Done.** A new room raises a non-blocking prompt in the conversation, a row and not a sheet; the review
  it opens offers per-person choice with blanket allow and deny as shortcuts through the same rows.
  A refusal is an answer and the room stops asking; *Later* is an answer about the people it was
  asked about, and somebody who joins afterwards brings it back.
- **Done.** The reciprocal line on somebody else's wall: what you can read of theirs and what they can
  read of yours, together, with the direction that is not yours to change saying whose it is.
- **Done.** Access is a set of periods rather than one date, said as date ranges wherever it is drawn, with
  one sheet offering the changes that are actually reachable and naming the one that is not
  reversible. See the decision, *Access to a wall is a set of periods*.
- **Done.** The Mac's audience rail, deferred rather than built, and here is the reason. Board 90 is a rail
  beside an Outpost composer on the Mac; the Mac has no wall to put one beside, and *The desktop
  wall* is not started. Building the rail first would be a component with nowhere to live, and the
  fact it carries — who will collect this — is already said on iPhone under the composer, by the
  same words board 90 asked for. It moves with the desktop wall, in
  [Desktop](desktop.md#the-desktop-wall).

<!-- COPY END e3b47d62 -->

<!-- COPY BEGIN f8bed739 [NEEDS HUMAN REVIEW] -->

**Testing**

- Suite: nine tests on the model, fourteen on the periods and the changes they allow
  (`AccessWindowTests`), eleven on the review (`OutpostReviewTests`), eleven on the two directions
  (`ReciprocalAccessTests`), and nine more on the enforcement (`OutpostAudienceTests`,
  `OutpostBackfillTests`): sharing a room grants nothing; everything opens the history; from now
  does not, and a later epoch change does not take back what a from-now reader already had;
  revocation is forward-only; a photo reaches the audience with its bytes; the list survives a
  relaunch; a reader let in later is handed the wall they were given the key to.
- **Two accounts, 2026-09-07.** Alpha's *Who sees it* listed beta as undecided, let them in from
  now, and showed them under *Can see it* as "From Sep 7, 2026". Alpha then posted; beta's Outposts
  tab drew that post and **not** the photo posted the day before, which is the whole of what "from
  now" claims. Beta's log reads `adopt: installed epoch 1 for a room (link absent…)` — the grant
  arriving with no way back — and the request for the wall it had just been let into.
- **Two accounts, 2026-09-07, second run** — the half the first run could not reach. Alpha removed
  beta, whose row moved to *You have not decided / Cannot see it* with no key-turn notice, so the
  wall's epoch had turned in the same breath. Alpha then posted a two-picture gallery while nobody
  could see the wall, uploading `recipients=0` twice, and let beta back in to *everything*. The next
  round logged `outpost: re-offered 3 wall picture(s) to 1 new reader(s); 0 no longer here`, and
  beta answered with `adopt: installed epoch 2 for a room (link present, now holding 3 epoch(s))`
  and three `media: fetched` lines. Beta's screen drew the whole wall: both pictures of the gallery,
  both text posts, and the photo from the day before. No access change appeared as a post on either
  device, and the *"the room may not appear at all"* diagnostic did not fire once. Alpha's packets
  went out `addressed to 1 recipient(s)` throughout, which is the narrowed peer set on a real
  transport. Still unseen on hardware: a key turn that *fails* and is retried by the next round, and
  an entry refused for good — both covered by the suite and by nothing else.
- **Two accounts, 2026-09-07, the review.** Beta's Emoji conversation drew the row: *1 person here
  can't see your Outpost*, the default said plainly, *Later* and *Review*, with the transcript
  legible underneath. The sheet listed the one member as *No access / Choose*, offered the three
  answers, and the row became *Posts from today, chosen here / Change* with both blanket buttons
  grayed because nothing was left waiting. Closing it took the row away, and the *Griff* room —
  same person, different room — never raised one, because an answer is about a person rather than
  about where it was given. Beta's wall then read *Visible to 1 person*, and alpha's Outposts tab
  drew Outie's post made after the grant. The whole path, from a row above a conversation to a
  post readable on another Apple Account.
- **Two accounts, 2026-09-07, the reciprocal card.** Alpha opened beta's wall and the card read
  *You can read: their posts from Sep 7, 2026 · Their decision* over *They can read: everything of
  yours · Change* — genuinely lopsided, each half folded from a different member's log, and the
  half that is not alpha's to change saying so instead of leaving a gap. *Change* offered the same
  three answers, narrowing the grant rewrote the lower line to a date, and widening it back
  restored *Everything of yours*.

<!-- COPY END f8bed739 -->

<!-- COPY BEGIN 8e14c22d [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — what a date could honestly mean, and why the floor is an epoch</summary>

**Two offers, not a date.** An epoch covers everything said while it stood, so "from last Tuesday"
would really mean "from whenever this wall's key last changed" — which is not the promise those
words make. So the screen offers *everything* and *from now*, and from now turns the wall's epoch
before writing the entry, so the reader is handed an epoch with nothing in it yet.

**The floor is remembered, not recomputed.** A grant hands over one secret and the links that walk
back from it, so where the walk stops is where their history stops. Recomputing that stop from the
grant's date would mean the next epoch change hands them the new key with no links — taking back
everything they could already read. The entry records the epoch they came in at, and every later
grant carries the links above it.

**The receipt knows the floor too.** Grants are handed out once per room, epoch and recipient, or an
open room rewrites a packet every sync. Widening somebody from *from now* to *everything* is a
second, wider grant of the same epoch to the same person — recognized as already issued, and never
written, until the floor went into the key.

**A refusal is an answer, and it costs no key.** The review's third answer, and *Allow nobody*,
write the same `outpostAccess` entry a revocation does — with `isAllowed` false — and that is what
stops the room asking again. What they do not do is turn the wall's epoch: a key only turns for
somebody who holds one, and saying no to a person who was never let in takes nothing away. Turning
it anyway would rewrap the wall to every reader and wake every one of their devices, once per
person, for a decision that changed nothing.

**Where an answer was given is part of the answer.** `chosenIn` records which room's review a
decision was made in, so a later review can say "Everything, from The Gazette" rather than only
"already set" — which is the question the row was there to answer. Nil for the audience list, which
is not about any one room, and the copy then says nothing rather than inventing a place.

**A bounded walk is not a fault.** The rig's first run logged *"could not walk this room's key back
to the beginning — the room may not appear at all"* on the round that proved the grant working.
The walk stopping is the feature; a grant carrying no links says so, and the diagnostic says the
same rather than sending the next person after a bug that is not there.

</details>

<!-- COPY END 8e14c22d -->

<!-- COPY BEGIN d6d236cb [NEEDS HUMAN REVIEW] -->

**Design.** Boards 11, 11b/c, 21, 42, 59, 60, 62, 63, 90, 15.

<!-- COPY END d6d236cb -->

<!-- COPY BEGIN 3ff1a6dd [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary>Record — why the enforcement was deliberately not built with the model</summary>

The model landed 2026-08-19. An allow-list that only filters the projection is theater: on this
app's model, what a reader can actually read is what they hold keys for, so per-person access means
sealing posts to the granted people. Wiring the list to the read path without that would ship a
permissions screen that does not permission anything, and flipping the read path before the
migration exists would hide every existing Outpost from everyone. Remaining, in order: the payload
type that carries a grant; sealing an Outpost entry to the current audience; the migration; then the
screens.

**From the boards.** 62, the allow-list, is ordered by the people it has no answer for, then by what
you granted, in two sections with real headers. 59, the review prompt, can afford to wait and does: a
row above the conversation, counting only the people it has no answer for. 60, the review sheet: per
person by default, the two blanket buttons shortcuts through the same rows; somebody who already had
access cannot be revoked from here. 63, reciprocal access, shows both directions at once because the
common misreading of an allow-list is that it is a handshake. 90, the audience rail, is where the
deleted "Visible to no one yet" line went: who *will* collect this, as a fact, never as a warning.

</details>

</details>

<!-- COPY END 3ff1a6dd -->

<!-- COPY BEGIN 436bba42 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="a-confirmation-answers-one-invitation">
<summary><b>A confirmation answers one invitation</b> — Complete (tested)</summary>

**Story.** As a member of a room, I want somebody asked back after being removed to read the
characters again, so that "an invitation is an offer" means the same thing the second time as the
first.

**Acceptance criteria**

- **Done.** `RoomRoster.confirmations` is keyed by `MembershipAttestation.signature`, so the first gate asks
  about the offer the room holds now. Closes all four ways in: removed then re-invited, left then
  asked back, a second offer superseding a confirmed but unapproved first, and withdrawn then
  replaced.
- **Done.** A removal or a departure records the offer it ends as **spent**, so re-appending that
  attestation's own bytes — which any member can do, because the fold checks nothing about a
  `.joinRequest` beyond the room it names — puts nothing back on the table.
- **Done.** `confirmedAt`, `hasConfirmed` and `confirmed` keep their public shapes and resolve through
  `requests[person]?.signature`; `isOpen(_:)` is the one question the fold, `verify`, the relay and
  the two invitation lists all ask, so no two of them can drift.
- **Done.** The honest re-join works, which it did not: `outstandingInvitations()` asks membership rather
  than possession. **It has to be membership** — removal advances the room's epoch, so the fresh
  offer is sealed under a key the removed member does not hold and their device cannot see it.
- **Done.** No wire change and no `PersistedState` change. `JoinConfirmedBody` already names the signature,
  and the roster is derived — `Projection.roster(of:)` rebuilds it on every call.
- **Done.** The room's own half of the gate, closed 2026-09-14. `RoomRoster` keys on the invitation
  (`admissionsByInvitation`, `refusalsByInvitation`) and `AdmissionBody` names the invitation it
  answers, so an approval or a refusal given for one offer no longer counts for the next. The
  person-keyed views remain as derived reads.

**Testing.** Two mutations proven: keying `confirmations` by the person again re-opens the fresh
invitation and the approval cases, and making the spend a plain forget re-opens the replay — each
failing only its own tests. `RemovalTests` and `LeavingTests` carry the fold; `JoinIsARoundTripTests`
carries the round trip, which is the one that fails on either half alone and which no roster test can
see. Three existing tests were inverted rather than deleted, so the diff shows the rule moving.

**Unproven on two accounts:** remove → re-invite → confirm, with the room's key turning for the
re-admission. `docs/testing.md` has no step for it.

</details>

<!-- COPY END 436bba42 -->

<!-- COPY BEGIN 3389a930 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="invitations-that-are-never-accepted">
<summary><b>Invitations that are never accepted</b> — Complete (operational proof owed)</summary>

**Story.** As an inviter, I want an invitation to expire and to be visible while it waits, so that a
room does not accumulate invitations to people who moved on.

**Acceptance criteria**

- **Done.** A lifetime chosen when sending: a day, a week, thirty days, or indefinite. **"A month" is thirty
  days on purpose** — the expiry is inside `signingPayload`, so every device checks the same instant,
  and a calendar month depends on a time zone and a start date. `InvitationLifetime` says so at
  length and the screen says thirty days rather than implying a calendar it is not using.
- **Done.** **A date you pick**, as a fifth row that reveals a date control beneath it — the shape
  `RoomAccessView` already uses for the number of approvers it wants. Good until the **end** of that
  day, because "good until the 14th" is how the words read and midnight would make the 14th the first
  day it did not work. Bounded to a year: further out is `indefinite` wearing a date, and that option
  is a sentence above saying what it costs.

  **The calendar is resolved once, before anything is signed.** The warning `InvitationLifetime`
  carries is about a *lifetime* meaning a different number of seconds on different devices; a picked
  day is turned into an instant on the device that picked it, so what travels is unambiguous and
  every device still checks the same moment. The member's own Wednesday is the Wednesday they meant.
- **Done.** **When it lapses it closes itself** — and where that is true is the part worth writing down. The
  device holding the link will not redeem or confirm it, and the inviter's device will not relay a
  confirmation it collected after the date. **The fold asks no expiry and must not**: a lapse has no
  entry, so it has no position, so it cannot be given the never-evict guard a withdrawal has, and a
  gate there would compare one party's clock against a lifetime that party chose. See
  [An invitation's lifetime bounds the offer up to the confirmation](../decisions.md#an-invitations-lifetime-bounds-the-offer-up-to-the-confirmation-and-the-room-is-not-where-it-is-asked).
- **Done.** Pending invitations shown in the room, each with when it expires; an invitation is a fact about
  the room. `RoomRoster.pendingInvitations(at:)` and `lapsedInvitations(at:)`, drawn in the member
  list, on the join sheet, on the joiner's own waiting row, and as an *Invited* chip on the rail. The
  transcript draws the invitation, the confirmation and the withdrawal as notices. **A lapse is the
  one thing it cannot announce** — there is no entry to draw — so the lists are where it is visible.
- **Done.** Taking an invitation back follows the rule the room has for removal **as that rule stands
  today**: any member in good standing, enforced in the fold, because an entry arriving from another
  device has no call site to trust. The transcript names who took it back, and the row and the sheet
  say whose offer it was.

  **The criterion was reworded, and the reason is a stale pointer.** "Exactly the rules the room has
  for removal" was written when removal was decided by the admission policy (see *Removing somebody*
  above); that was replaced on 2026-09-01 by *anyone may remove anyone*. The reason clause — an
  invitation is the first half of membership — is what survived, and it is what was built. It also
  frees an invitation nobody could reach: an offer made by a member who has since left, which
  nothing clears and which that member may no longer write to the room to withdraw.

<!-- COPY END 3389a930 -->

<!-- COPY BEGIN 14f4535f [NEEDS HUMAN REVIEW] -->

**Five defects found on the way, none of them in the plan.** Worth listing, because every one was a
screen or a control saying something the code did not do:

- **A withdrawn invitation kept its *Admit* button, and tapping it wrote a false line into the room's
  permanent history.** `pending(for:)` and `RoomRoster.verify` both ignored withdrawals, so `decide`
  appended an `.admission`, the transcript drew *"Alice let Bob in"*, and only then did the fold
  decline to establish anybody.
- **The transcript credited a withdrawal to whoever made the offer**, not whoever took it back —
  invisible only because the fold forced them to be the same person, and a false attribution the
  moment that changed.
- **Every membership refusal reached the screen as a case number.** `SessionProblem` had no
  `MembershipError` arm at all, so *"The operation couldn't be completed. (CarpenterKit.MembershipError
  error 0.)"* was what a member read when a join, a withdrawal or a removal was refused.
- **The join sheet never drew the expiry it was handed.** `PendingJoin.expiresAt` was carried through
  the whole composition root to the one screen where somebody decides on an invitation, and only the
  member list ever said it.
- **A joiner watched their own waiting row disappear** when the date passed, on the one screen that
  is their entire view of the room they are waiting for.

**Testing.** `InvitationLifetimeTests` and `PendingInvitationTests` (the lifetime, the two lists),
`RescindingAnInvitationTests` and `SessionRescindTests` (taking one back), `AnOfferThatRanOutTests`
(what the expiry does and where). Six mutations proven: the relay gate, `decide`'s widening, the split
between the two lists, the widened fold, the transcript's attribution, and the joiner's row.

**(c) ran on the rig, 2026-09-09, proved above the mailbox.** Griff invited Quad into *Triangle*
choosing **a date you pick** — the sheet said *"This invite expires Sep 16, 2026 at 11:59 PM"*, so the
end-of-day resolution is signed into the attestation. On Outie's device the row read **"ABD2B6 —
Invited by Griff. Nothing back yet — runs out next week."** (a fingerprint rather than a name, because
Outie has never met Quad), the menu offered *Take back the invitation* on somebody else's offer, and
the sheet's fourth fact named Griff. Outie took it back, and Griff's own transcript now reads **"Outie
took back the invitation to Quad"** — his device names Quad because he has met them, Outie's names
ABD2B6 because she has not. Both rules holding on one entry.

<!-- COPY END 14f4535f -->

<!-- COPY BEGIN 3624b687 [NEEDS HUMAN REVIEW] -->

**Still unproven, and CLAUDE.md's rule stands:** (a) the joiner confirms, the inviter stays offline
past the date, the inviter opens the app, and the join is refused with both screens saying so; (b) the
joiner confirms, the inviter relays in time, and an approver admits after the date. Both want an
inviter's clock moved past the date; `--clock-ahead-days` can now do that on the rig, and has not been
tried for this.

</details>

<!-- COPY END 3624b687 -->

<!-- COPY BEGIN 9a5eddd0 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="the-multi-step-leave">
<summary><b>The multi-step leave</b> — Complete (tested)</summary>

**Story.** As a member leaving a room, I want to be asked about that room's Outpost access, so that
I do not keep giving somebody access I meant to end.

**Acceptance criteria**

- **Done.** Leaving is a **confirmation dialog**, not an alert: *Leave and Review Outpost Access*, *Leave*,
  *Cancel*. Apple names this case — "Use an action sheet — not an alert — to offer choices related
  to an intentional action… an alert… doesn't provide additional choices related to the action"
  ([Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)).
  An iOS alert cannot hold the toggle this was first drawn with: it holds a title, optional text and
  up to three buttons, plus a text field
  ([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)).
- **Done.** Destructive styling on the leaving choices, at the top, with Cancel at the bottom — Apple's
  placement for an action sheet. Three buttons is inside the limit of four including Cancel.
- **Done.** The Outpost-access step: stop at today rather than keep allowing what is already visible. Plain
  *Leave* stays the default path and does not ask, and the reviewing choice is only offered when
  somebody actually holds access chosen in that room. `LeavingRoomView` is a sheet, which is what
  Apple names for a scoped task closely related to the current context, and because an action sheet
  holds no more than four buttons including Cancel. Three tests in `SessionLeavingTests`, including
  that access given for its own sake is **not** swept up — the step ends access that outlived its
  reason, never a separate decision.

**Dropped 2026-09-14.** The review screen reading a full consequence list before the confirm, and
each step announcing which step of how many. Apple: "Provide a message only if necessary. In
general, the title — combined with the context of the current action — provides enough information
to help people understand their choices."

**Testing.** `SessionLeavingTests`, and walked on the rig 2026-09-14. **Design.** The criteria above are
the specification. The boards that
described this as a multi-step flow predate Liquid Glass and cite no Apple guidance, so they are no
longer the reference — see
[Decisions](../decisions.md#leaving-a-room-is-an-action-sheet-because-the-hig-says-so).

</details>

<!-- COPY END 9a5eddd0 -->

<!-- COPY BEGIN be7a519a [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="delete-room-for-somebody-removed-or-gone">
<summary><b>Delete room for somebody removed or gone</b> — Complete (hardware proof owed)</summary>

**Story.** As somebody who was removed from a room or left it, I want to delete my copy, so that a
historical log I no longer want is not permanent.

**Acceptance criteria**

- **Done.** A Delete room control on a room the member is no longer in, behind a confirmation stating it
  cannot be undone, takes every message with it, and that being re-added may not bring the history
  back. Built 2026-09-17. *Delete* appears where *Leave* did — last in a room's context menu, with the
  trash symbol, destructive — and in the conversation's own menu and the edit list's swipe, so it is
  in the main interface as well as the context menu. It leads to an alert: *Delete* and the room's
  name, "Every message and photo in it goes from your devices, and being added back may not bring
  them back. This cannot be undone.", *Delete* and *Cancel*. It takes the room's entries out of the
  log on disk, its keys out of the keychain, its photos off the device, and what the device kept about
  it — the invitation that let the member in, read marks, repairs.
- **Done.** The deleted room does not come back. See the ruling below and
  [Architecture](../architecture.md#a-deleted-room-leaves-its-numbers-spent).
- **Done.** *Leave* is no longer offered on a room already left, and nothing is offered while the leaving
  has not been sent — Apple's Context menus page says to hide what is unavailable rather than dim it.

**The calls made building it** — every device, waiting for the leaving, photos left for others, the
alert's button style — are in
[Decisions](../decisions.md#deleting-a-conversation-reaches-every-device-waits-for-the-leaving-and-leaves-photos-for-others),
marked `PROPOSED`.

**What had to be decided first, found 2026-09-13.** Taking the entries out of the log is not the
simple half. Feeds are numbered without gaps, and a device works out what it is missing by looking
for positions nothing occupies — so entries deleted on purpose become holes the repair path names,
asks a peer for every hour, and refills. Delete the room and it comes back.

Three ways out, none free:

<!-- COPY END be7a519a -->

<!-- COPY BEGIN b0293248 [NEEDS HUMAN REVIEW] -->

- **Record the deletion as spent**, the way `RoomRoster.spent` records a finished invitation and
  `Replica.refusesForever` records an entry that can never be lifted. The gap index has to consult it,
  and it has to survive the hand-written decoder — the `greetedRooms` tax.
- **Keep the entries and drop only the room**, which is honest only if the copy stops saying it takes
  every message with it. That is a different feature with a different sentence.
- **Make the deletion an entry**, which the member's own other devices would fold — but this is a
  local act on a room nobody else can see them in, so putting it on the wire is the wrong shape.

**Ruled by Griff, 2026-09-14: the first, and built once.** Built 2026-09-17 as `SpentEntry` in
`Replica`: consensus hard delete and hard-delete-and-desync can spend individual entries through the
same list when they are built.

**The component.** An alert, not a confirmation dialog — the opposite of
[leaving](#the-multi-step-leave), and for the reason Apple gives: "when people take an uncommon
destructive action that they can't undo, it's important to display an alert in case they initiated
the action accidentally"
([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)). There are no
choices related to the action, so there is nothing for an action sheet to offer.

**Testing.** `SpentPositionsTests`, five: closing a room takes its entries and leaves no hole in a
feed it shared with another room; an entry for it offered again, held or never seen, is not kept; the
next entry a device writes follows a spent one rather than reusing its number; a relaunch restores
what was spent; reopening gives the numbers back to be filled. `LogRemovalTests`, two: the file keeps
every other entry in order across a reload, and removing nothing leaves it alone.
`DeletingARoomTests`, twelve, through the session: a room still in cannot be deleted; deleting after
a removal takes the messages, the log's entries, the keys and the room, and leaves another room with
the same person whole with no holes; a relaunch and an hour of automatic repair do not bring it back,
and the next message after it does not reuse a number; a message from a third person written before
the removal and delivered after the deletion is not kept; leaving waits to be sent; a key sent by
somebody who had not heard is refused; a photo in the room leaves the device while one the member
sent stays in the outbox through the sweep; a deletion cut off before the log was rewritten is
finished on the next launch; being invited back lets them in and write again; an Outpost cannot be
deleted; deleting on one device deletes on the other and a feed written before the deletion does not
hand the key back. Every guard was broken once to see a test fail: the spent number occupying its
position, absorbing a late entry, keeping photos for others, continuing from a spent head, dropping
the old invitation, finishing on launch, settling a sibling's deletion, refusing a sibling's key,
refusing a peer's key, reopening on an invitation, and waiting for the leaving.

<!-- COPY END b0293248 -->

<!-- COPY BEGIN df9676ec [NEEDS HUMAN REVIEW] -->

**Over the real wire.** `LiveRoundTests.aDeletedRoomStaysDeleted` puts a removal, the deletion, a
relaunch and a repair asking for history on real CloudKit, and passed on beta on 2026-09-17. Its first
version passed with the spent-entry machinery taken out, because the holes only appear once the log is
read back from disk; it relaunches now, and with the machinery taken out the room's messages come
back over the wire and it fails.

**On the rig, 2026-09-17, above the mailbox** (Trig and Quad, no Apple Account, a directory for a
mailbox — [the rig](../simulator-rig.md#members-without-an-apple-account)). Trig removed
Quad; Quad's copy read *You were removed from this room* with Trig's last message and *Trig removed
Quad* above it. The conversation's menu offered *Delete* and its alert; the room's context menu held
Pin, Silence, Tags and *Delete* — no *Leave* — and the alert read *Delete Checks* with its sentence,
*Cancel* and *Delete*. Deleting emptied the list, and a relaunch with Trig still running did not bring
it back. Trig then invited Quad again: Quad's copy greeted *Checks — Trig added you to this room*, two
members, and the compare-codes page opened on both halves.

**Owed.** Deleting on one phone and seeing it go from another needs one account on two phones.

</details>

<!-- COPY END df9676ec -->

<!-- COPY BEGIN 9ef7ccc5 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="verifying-who-somebody-is-later">
<summary><b>Verifying who somebody is, later</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want to compare fingerprints after we have already been talking, so that
verification is not a one-time thing I clicked past.

**Acceptance criteria**

- **Done.** A way to compare again at any later point, stating when you last checked. 2026-09-16: everybody
  in *Who you are talking to* opens a **Compare codes** page. The characters from an invitation only
  ever existed between inviter and invited, so a third member had nothing to compare; the page shows
  a code made of two halves, one per person, identical on both phones — see
  [Decisions](../decisions.md#verifying-somebody-later-a-shared-code-a-note-to-yourself-and-a-line-when-they-add-a-device)
  and [the crypto brief](../crypto-brief.md#the-code-two-people-compare-later).
- **Done.** A standalone comparison sheet, offered once, never blocking, skippable with a plain button.
  Ruled 2026-09-16: once per person, the first time a conversation with them opens after joining,
  skipped for the two people in an invitation and anybody already marked as matching. A sheet is the
  right component — "A sheet helps people perform a scoped task that's closely related to their
  current context" — with *Not now* as its plain dismissal
  ([Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)). It waits for the
  room's greeting rather than stacking on it.
- **Done.** …and what has happened since. *They match* is a dated note to yourself, and the page says so;
  afterwards it says when it was marked and whether that person has added a device since. *They don't
  match* says what it can mean and that nothing was sent.
- **Done.** Replaced, ruled 2026-09-16: a fingerprint cannot change here, because an identity **is** its
  keys. What can change is somebody's devices, so a dated *Alex added a device* appears in every
  conversation with them, for any device newer than the first thing this phone heard from them there.

<!-- COPY END 9ef7ccc5 -->

<!-- COPY BEGIN 68d60d12 [NEEDS HUMAN REVIEW] -->

**Testing.** `ComparisonCodeTests`, five: the halves are identical on both phones and in the same
order; ten characters from the reading alphabet; an impostor's half differs; each key counts; and a
half is pinned against a value computed independently in Python. `ComparingAgainTests`, three: in a
room Alice founded, where Alice invited Bob and Bob invited Carol, Alice and Carol are offered each
other and Bob is offered nobody; nobody is offered twice; Alice and Carol see the same code; marking
is a dated note that does not reach Bob. `DeviceAddedNoticeTests`: Bob's second phone reaches Alice
as one line dated by its certificate, placed before what Bob said next, and his first phone never
shows. **Rig, 2026-09-17, above the mailbox**: *Who you are talking to* and *Compare codes* on Trig
and on Quad, the same two halves in the same order on both — *3AZMZJA56H* and *QKB9XAFN5P*. It found
two things. The *Read these 10 characters aloud* caption sat centered over a narrower column than the
page, so it looked indented; the phrase is laid out across the page now. And **a member removed from
a room was offered a comparison in it — with the person who had invited them**, because a removal
clears the invitation the offer used to recognize their inviter. Nobody is offered a comparison in a
room they are not in now (`ComparingAgainTests.notAfterARemoval`). Then with a third member — a
temporary fifth simulator Trig invited beside Quad: Quad opening the room was offered *You and Fifth
have never compared codes*, and Trig, who invited them both, was offered nothing. **And the offer
never reached a new joiner on their first visit**: it waited for the room's greeting, as ruled, and
nothing asked again once the greeting closed, so it appeared only the next time they opened the room.
It asks again when the greeting closes now, and a new joiner tapping *Open Checks* was offered at once.
**Owed**: the device line needs one account on two phones.

**Design.** Boards 22, 81, 82, 80, 09, 57.

</details>

<!-- COPY END 68d60d12 -->

<!-- COPY BEGIN 5d533c56 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="why-nothing-is-happening">
<summary><b>Why nothing is happening</b> — Complete (proved above the mailbox)</summary>

**Story.** As a member watching a room that has not changed in a while, I want to know which people
this device is waiting on, so that "nothing is happening" has an answer other than worry.

Split out of [Verifying who somebody is, later](#verifying-who-somebody-is-later) on 2026-09-14: it
was sitting in that ticket and has nothing to do with identity.

**Acceptance criteria**

- **Done.** 2026-09-16. A screen naming which peers a sync is waiting on, and what was last heard from each.
  **Who this is waiting on**, in every conversation's menu and linked from the not-sent sheet, lists
  everybody else in the room with one of three answers: *has everything you sent here*, *has not
  collected N messages you sent here yet*, or *not checked since the app opened* — and *last heard*,
  the newest thing of theirs this phone holds, dated by their device.
- **Done.** It reads as a status, never as a fault. No warning color, no symbol, and the footer says that
  waiting on somebody who has not opened their app is the ordinary case.
- **Done.** It agrees with the marks on the messages. Both read `unsentEntries()` and
  `persisted.outstandingPackets`; the screen adds which recipient tags each outstanding packet is
  still addressed to, from the round's own `pendingDeliveries()`, and matches them against each
  person's tags for the seven-day window. A message not yet off this phone is missing for everybody.

**What it does not know, said on the screen.** The recipient tags are held in memory from the last
full round, so until a round has run since launch the answer is *not checked since the app opened*
rather than a guess. *Last heard* is what they wrote, not when their app last collected — a member
who reads and never writes shows *nothing heard from them yet*; the mailbox does not record when a
packet was collected, only whether it still waits.

**Testing.** `WaitingOnTests`: a message that has not left the phone is missing for the other member
before any round; after a round it is still missing and the message's own mark is *sent*; once Bob
collects, he has everything and the mark is collected, and once he writes he has been heard from.
Before a round, it says it has not checked. Rig, 2026-09-16, alpha: the menu item and the sheet,
which in Kitchen shows its empty case because nobody else is in it. Rig, 2026-09-17, above the
mailbox: *Waiting on* in Checks named Quad — *Has everything you sent here. Last heard* and the time
Quad's last message was written.

</details>

<!-- COPY END 5d533c56 -->

<!-- COPY BEGIN dc639b80 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="the-one-stranger">
<summary><b>The one stranger</b> — Complete (proved above the mailbox)</summary>

**Story.** As somebody reading a friend's Outpost, I want the whole thread under a post, so that what
people are replying to makes sense — and as somebody commenting on it, I want the readers I have never
met to get my words and nothing else about me.

**Acceptance criteria**

- **Done.** A comment on somebody's post seals under *their* Outpost epoch, so exactly the post's readers can
  open it. Reactions to a post or a comment go the same way.
- **Done.** Writing onto a wall this device holds no key for is refused, and never creates a chain for
  somebody else's wall.
- **Done.** Everybody unmet — no room now or ever, no Outpost grant either way, no nickname — is drawn as one
  shared figure, with one shared identifier, through every route a `ParticipantID` becomes a name.
- **Done.** Two different strangers are indistinguishable from one stranger commenting twice.
- **Done.** Meeting somebody afterwards names what they already wrote, with nothing rewritten.
- **Done.** The figure is the reader's own: six ready-made faces on the accent, a name they can change, a
  picture they can choose. It never leaves their devices.
- **Done.** The deal is said out loud the first time the tab opens, with or without anybody in it, and
  refusing has two shapes — read without joining in, or no Outposts at all.
- **Done.** *Read only* is refused in `AppSession`, not only hidden by the screens.
- **Done.** A comment crosses between two accounts under the new seal, and the reader names its author,
  because they have met.
- **Done.** The triangle, on three devices and three identities, **above the mailbox**. 2026-09-09.
- **Deferred.** The triangle on real accounts, over CloudKit. Needs a third Apple Account — moved off the
  roadmap 2026-09-14 to [Proofs a rig cannot run](../proofs-a-rig-cannot-run.md).

**Testing.** `AnonymousCommentTests` (five) and `OutpostConsentTests` (four). Four were
mutation-proven on 2026-09-07: dropping the anonymizing branch, sealing a comment under the writer's
own wall again, and skipping the read-only guard each fail them. On the rig the same day: the consent
sheet answered on both accounts, and Griff's comment on Outie's post arrived on Outie's device under
the nickname Outie has for Griff — sealed under Outie's wall, which is the change.

**The triangle, 2026-09-09.** Griff and Outie share rooms; Griff and Quad share the room *Pair*;
Outie and Quad share nothing at all. Griff let Outie and Quad both read his Outpost and posted
*Testing the stranger*. Quad commented. **Griff's device drew the author as Quad and Outie's drew the
same comment as User 403**, on the shared anonymous disc, with no way from one screen to the other.
That is the whole claim and it is now observed rather than argued — **proved above the mailbox,
unproven below it**: the rig replaces CloudKit with a directory, so zone routing, share acceptance,
the change feed and push are all untested by it.

**What is not covered:** the envelope — see
[Inbox](../inbox.md#privacy-on-the-wire).

<!-- COPY END dc639b80 -->

<!-- COPY BEGIN eccd971c [NEEDS HUMAN REVIEW] -->

### Backfill, and the recommendation not to

Alice reads a stranger's comment on Bob's wall. Later Alice and Carol meet, and it turns out Carol
wrote it. Should the old comment now say *Carol*?

**It already does, and that is the recommendation: change nothing.** The figure is a *rendering*, not
a stored attribution. `Projection.member(_:)` asks `met` on every read, so the moment Carol enters
Alice's `met` set — a shared room, a grant in either direction, a nickname — every comment Carol ever
left resolves to her name on Alice's screen, on every device Alice owns, with no entry rewritten, no
message sent and nobody asked. `meetingResolvesTheOldComment` is that test. This is the whole reason
the figure is shared rather than numbered: there was never a record of who the stranger was, so there
is nothing to correct.

**And the hard part is not a problem either.** The worry is that Bob knows Carol, Alice now knows
Carol, and Alice must not learn that *Bob* knows Carol. Nothing here tells her. What Alice's device
resolves is the author of an entry it already held, against a set Alice's own device computed from
Alice's own rooms and grants. Bob is not consulted, does not learn that Alice and Carol met, and sends
nothing. The only thing Alice can conclude is that Carol commented on Bob's post — which she can also
conclude by reading the post, and which is the ordinary consequence of Bob letting them both in.

**What to be careful of, if this is ever revisited.** Three ways to make it worse, all tempting:

- *Backfilling as a message.* Anything where Bob tells Alice "that was Carol" would put Bob's
  knowledge of Carol on the wire, which is exactly the fact to protect. There is no reason to: Alice's
  device already has the author.
- *Caching the rendered name.* Storing "this comment was by User 403" would turn a rendering into a
  record, and then meeting somebody really would need a migration — and un-meeting them would leave a
  name behind.
- *Numbering the strangers.* Numbering is what would make backfill hard: distinct figures are a
  durable handle a reader can count and follow, and resolving one of them would tell them which of
  their new acquaintances had been reading along.

The one thing that could still be worth building is the opposite direction — leaving a room or losing
a grant does not put somebody back into the fog, because `met` includes the absent on purpose.
Forgetting them would turn every comment they ever left into a stranger's, which reads as history
being edited. That is deliberate and worth leaving alone.

</details>

<!-- COPY END eccd971c -->

<!-- COPY BEGIN f1c57087 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="open-or-closed-on-other-peoples-outposts">
<summary><b>Open or closed on other people's Outposts</b> — Complete (proved above the mailbox)</summary>

**Story.** As somebody setting up the app, I want to be asked once whether I want Outposts at all and
how far what I write on other people's should travel, so that the answer is a decision I made rather
than one I discover.

<!-- COPY END f1c57087 -->

<!-- COPY BEGIN cdc96390 [NEEDS HUMAN REVIEW] -->

### Where it goes

The privacy check-up (`PrivacyCheckupView`) already walks a new member through the message settings,
including the advanced path. An Outpost section follows **the whole of that flow, advanced included** —
same shape, same voice, same one-question-per-screen. Every setting it asks about also lives under
Outpost settings on the You page, because a wizard is where a decision is *made* and settings are
where it is *changed*.

<!-- COPY END cdc96390 -->

<!-- COPY BEGIN e69f0064 [NEEDS HUMAN REVIEW] -->

### The two questions

**One: do you want Outposts?** Off takes the tab away and writes and fetches nothing for one. It is
reversible, and the copy says so.

**Two: how far does what you write on other people's Outposts travel?** Three answers, and the
naming below is the shape the settings take:

| Answer | Your posts | What you write on somebody else's post |
|---|---|---|
| **Open** | Only the people you let in, as always | Reaches everybody who can read that post. People you have not met see the one anonymous figure. |
| **Closed** | Only the people you let in, as always | Reaches only the post's author and the people *you* have let into your own Outpost. To everybody else it is not there at all. |
| **Read only** | Only the people you let in, as always | Nothing. You read and do not write. |

The middle column never changes, and the screen says so in as many words: **none of these touch your
own Outpost.** Who reads your posts is decided one person at a time and nothing here moves it. The
confusion to design against is a member reading "closed" as "my wall is now private", when their wall
was always private.

*Open* is the shape people arriving from a social network expect: a private account whose followers
can all see each other's replies. *Closed* is the shape people arrive from a group chat expecting:
what I say is seen by people I chose. Neither is the safe default to assume — that is why it is asked.

**Read only** is today's `OutpostConsent.quiet` and needs no new machinery. It stays, because refusing
the deal outright is a real answer and the consent sheet already offers it.

<!-- COPY END e69f0064 -->

<!-- COPY BEGIN 1f351e69 [NEEDS HUMAN REVIEW] -->

### How closed would work

A comment now seals under the wall it lands on, so the post's readers and the thread's readers are the
same set (see [Decisions](../decisions.md#a-comment-belongs-to-the-wall-it-lands-on)). Closed is the
other seal: under the **commenter's own** wall epoch, which is exactly what comments did before that
change — so the mechanism is proven, and what was a bug when it was the only behavior is a setting
when it is chosen. A reader who cannot open it does not see a gap; an unreadable Outpost entry is
already suppressed rather than drawn as "not readable" (`Projection.outpostEntries`).

The one thing that needs building is the post's author: they must read a comment on their own post
whether or not they are on the commenter's allow-list, or *closed* means writing into a void. That is
a pairwise wrap of the same content key to the author — `Pairwise.swift` is the seam — carried on the
same entry. Design it as a second recipient, not as a second entry.

**Acceptance criteria**

<!-- COPY END 1f351e69 -->

<!-- COPY BEGIN 0bfb0bdd [NEEDS HUMAN REVIEW] -->

- **Done.** The check-up's Outpost section runs after the messages flow completes — **both doors**, because a
  preset answers the messages half and neither preset has anything to say about Outposts.
- **Done.** *Do you want Outposts* asked first, and answering no skips the two pages after it rather than
  showing questions about something that is off. The step count follows the walk actually taken.
- **Done.** Three answers to *how far it travels*, each stating what it does to somebody else's post, with a
  live example whose stranger row flips from *reads it, as one anonymous figure* to *not there*.
- **Done.** Every screen says plainly that none of it touches your own Outpost.
- **Done.** The same four under Outpost settings on the You page, sharing one set of words with the check-up
  (`OutpostConsentCopy`) so they cannot drift into reading like two different settings.
- **Done.** The own-Outpost question — whether a new room-mate raises the offer at all — in the check-up and
  in settings. On by default, because it discloses nothing and grants nobody anything.
- **Done.** **Closed** seals a comment or reaction under the writer's own wall.
- **Done.** A reader who may not open a closed comment sees no trace of it — no gap, no placeholder, and no
  change to the comment count.
- **Done.** Enforced in `AppSession`, not only by the screens, the way *Read only* is.
- **Done.** **The post's author is wrapped in as a second recipient**, so a closed comment reaches the person
  it answers whether or not they are one of this member's readers. A second copy of the same words on
  the same entry, sealed under the pairwise secret, gated on a nil check so the fold never derives a
  key to find out it did not need one. The refusal it replaces is gone.
- **Done.** A thread says when it is short. The post's owner is the one person who can see the whole of it,
  so their device publishes the count — only where somebody wrote closed, so a wall of open readers
  writes none. An understated line, an *i*, and a sheet that admits the number is the one thing in
  the app that is not proof of itself, says what forging it would take and buy, and ends in a way
  through to this member's own settings.
- **Done.** A closed comment crossed between two real Apple Accounts on 2026-09-07, with the new seal shape,
  and the owner read it.
- **Done.** The triangle, on three devices and three identities, **above the mailbox**. 2026-09-09.
- **Deferred.** The triangle on real accounts, over CloudKit. Needs a third Apple Account — moved off the
  roadmap 2026-09-14 to [Proofs a rig cannot run](../proofs-a-rig-cannot-run.md).

<!-- COPY END 0bfb0bdd -->

<!-- COPY BEGIN 6a2bbcb9 [NEEDS HUMAN REVIEW] -->

**Testing.** `closedIsInvisibleToTheRest` is the one that matters and it is the triangle in memory:
Carol writes closed under Bob's post having let in Bob and not Alice; Bob reads it, Alice's thread is
empty and her count is zero. Plus `closedReachesOnlyYourOwnReaders`,
`closedRefusesWhereItWouldNotBeSeen`, `theTwoAnswersDiffer`, and four in `OutpostReviewOfferTests`.
Three mutations proven on 2026-09-07: sealing closed to the post's wall anyway, ignoring the review
offer, and drawing unreadable comments. The third caught nothing — the seal already excludes them,
because an entry nobody can open carries no `replyingTo` — and the filter is kept as the guard for the
day that stops being true.

**The triangle, 2026-09-09.** On Griff's post *Testing the stranger*, with Outie and Quad both let
into Griff's Outpost and sharing nothing with each other: Quad answered *Joining in* with **Closed**
and commented twice. Griff — the post's owner, and on nobody's allow-list of Quad's — **read both**,
which is the author wrap doing the one thing it exists for. Outie's thread showed the one open
comment, no gap where the closed ones are, and the line **"2 comments are not shown"** with the
*Missing comments* sheet behind it, saying it is a key rather than a decision, that nobody is named,
and that the number is the one thing in the app a reader cannot check. **Proved above the mailbox,
unproven below it.**

</details>

<!-- COPY END 6a2bbcb9 -->

<!-- COPY BEGIN b2e8fb10 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="an-invitation-that-runs-out-says-so-nowhere">
<summary><b>An invitation that runs out says so nowhere</b> — Complete (tested)</summary>

**Story.** As somebody who invited a person a fortnight ago, I want to see that the offer ran out, so
that a row reading *invited, nothing back* does not go on implying something might still arrive.

**Acceptance criteria**

- **Done.** `RoomRoster.lapsedInvitations(at:)` keeps an offer after its date rather than dropping it, so
  the room can say what became of it.
- **Done.** The row reads *Invited. Ran out yesterday. Sending another is the way back.* — named relative
  time, and the way forward in the same sentence.
- **Done.** It offers no controls. Every control the live row carries was about a live offer; taking back
  something already ended is a button that does nothing.

**Testing.** `AnOfferThatRanOutTests`. Split out of the verification design pass and closed the same
day, 2026-09-09.

</details>

<!-- COPY END b2e8fb10 -->

<!-- COPY BEGIN e9ae7047 [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="a-refusal-throws-the-six-characters-away">
<summary><b>A refusal throws the six characters away</b> — Complete (tested)</summary>

**Story.** As somebody who has just refused an invitation, I want to still see the characters I
was shown, so that I can ring the person I meant to talk to and compare them.

**Acceptance criteria**

- **Done.** The refused step carries the offer rather than only the code, so the phrase survives the refusal.
- **Done.** Both refusal screens draw the characters, in the same `VerificationPhrase` component every other
  screen uses.

**Testing.** Split out of the verification design pass and closed with finding 17 the same
afternoon, 2026-09-09.

</details>

<!-- COPY END e9ae7047 -->

<!-- COPY BEGIN 60408d2a [NEEDS HUMAN REVIEW] -->

<details markdown="1" id="the-removal-audits-open-cases">
<summary><b>The removal audit's open cases</b> — Complete (tested)</summary>

**Story.** As a member of a room of three, I want a removal to hold under the cases the audit named,
so that the two-member proof is not the whole proof.

**Acceptance criteria**

- **Done.** 2026-09-16. The non-atomic two halves of a removal survive a crash between them.
  `RemovalSurvivesACrashTests` builds a room of three, cuts Alice's removal of Carol off at each of
  the two points that matter — **after the removal entry is written and before the key turns**, and
  **after the key-turn entry is written and before its secret is kept** — throws the session away,
  opens a new one over the same files and keychain, and lets the round run.

  **Before the fix both cases failed, and the failure was worse than the audit said.** The audit
  claimed every device would agree Carol was out while the key never turned. Measured: that, *and*
  Carol read "after Carol went" — the removed member reading what was said after the removal. The
  message reaches her device whether or not she is in the room; the key turn is the only thing that
  stops it being read.

  **The fix is the one the Outpost already had.** Revoking a reader writes that a key turn is owed
  before it writes the revocation, and every full round retries an owed turn until it lands
  (`OutpostKeyTurnTests`). A room removal now does the same: `oweEpochTurn`, then the removal, then
  `turnOwedEpoch`. A crash before the removal is written leaves a turn owed for a room nobody left,
  which costs one extra key turn and nothing else.
- **Deferred.** Rival epoch secrets from two concurrent advances resolve identically everywhere.
- **Deferred.** The narrow grant window with a stale roster is closed end to end.

Both deferred items moved to [Proofs a rig cannot run](../proofs-a-rig-cannot-run.md) on 2026-09-14: two
members can only advance an epoch concurrently if there are three parties, and there are two
accounts.

**Detail.**
[the inbox](../inbox.md#membership).

</details>

<!-- COPY END 60408d2a -->

<!-- COPY BEGIN 47d9a5d0 [NEEDS HUMAN REVIEW] -->

## Test plan

<details markdown="1">
<summary>Three accounts if you can get them; two proves most of it</summary>

Two cannot prove independent admission.

**Membership.** A creates a room and invites B; B redeems; both verify the phrase. A invites C; B
admits C independently of A; C gets the room and its history. A refuses C: C stays in the room but
receives no further keys from A, and A's later messages are unreadable to C. Tighten the policy:
everybody already in stays in.

**Removal — all three passed on two Apple Accounts, 2026-09-02.** A removes C: every device agrees.
C's history is unchanged and the app does not claim it was removed. C receives no key for the next
epoch, so nothing said after the removal is readable: passed, and the one that matters.

**Outpost access.** A grants B from today: B sees nothing older. A upgrades B to
everything through the confirmation: B sees the history. A revokes: B sees nothing new and keeps what
they collected. Leaving a shared room changes neither.

</details>

<!-- COPY END 47d9a5d0 -->

<!-- COPY BEGIN a435fc91 [NEEDS HUMAN REVIEW] -->

**What would falsify the epic.** Somebody reading a room they were removed from. Somebody losing
history they legitimately held. A member count that disagrees between two devices. Any claim that a
removal reaches into somebody else's device.

<!-- COPY END a435fc91 -->
