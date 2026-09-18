---
title: Advanced data etiquette
layout: default
parent: Roadmap
nav_order: 5
---

# Taking things back

{: .no_toc }

Deletion as a shared decision, and what it costs to keep that true.

1. TOC
{:toc}

## The principle

> You can tell someone you never want something again. We require that behavior to use this system.
> It is always allowed. You cannot, however, alter someone's personal conversation history. Shared
> ownership is the right privacy and accountability model.

Two rules follow, and every decision here comes from them: **refusal is unilateral and always
available**, and **removal from somebody else is never unilateral.** Using rooms means opting into
this pattern, and that is the price of the second rule being real rather than advisory.

## Where this stands

Three words, and they mean three different things. **Editing** and **withdrawing** are your own
words on everybody's screens, within a window, and neither is reversible. **Hiding** is anybody's
words on your own devices, and reversible. All three are built, and hiding reaches the member's
other devices. Everything that reaches into somebody else's storage, consensus deletion and deleting
while letting a conversation diverge, is specified and was moved past TestFlight on 2026-09-14. Statuses are defined
on the [Roadmap](../roadmap.md#how-to-read-this).

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="editing-and-withdrawing-your-own-words">
<summary><b>Editing and withdrawing your own words</b> — Complete (tested)</summary>

**Story.** As a member, I want to fix what I just said, or take it back, so that a typo or a message
sent to the wrong room is not permanent.

**Acceptance criteria**

- **Done.** Editing within fifteen minutes and withdrawing within two, matching iMessage, both measured
  from when the message was written and not from delivery.
- **Done.** The window is enforced in the fold on every device, not only the sender's, so a modified client
  cannot rewrite an old message on somebody else's screen.
- **Done.** Only the author. A withdrawn message cannot then be edited; the tombstone wins in either order.
  Withdrawing clears the revision history.
- **Done.** The first edit stores the original as revision one; an edited message carries an *Edited* mark;
  the wording history is on the message detail page.
- **Done.** The app never says "delete". The placeholder reads *withdrawn*.

**Testing**

- Suite: nineteen tests over the fold and the session.
- Two accounts, 2026-09-02: Alpha edited a message Beta had already drawn and Beta's copy changed
  with the mark; Alpha withdrew one and Beta's became the placeholder; Beta's menu on Alpha's
  message offered neither; a three-minute-old message offered Edit and not Withdraw, a two-hour-old
  one neither.

<details markdown="1">
<summary>Record — why withdrawing is not deleting, and two defects the rig found</summary>

The entry is not removed from anybody's device. A second entry, a tombstone, says the first is
withdrawn, and every device draws a placeholder where the words were. The original stays in the log,
stays hash-linked, and is still forwarded. That is the data-ownership model doing exactly what it
says: a withdrawal is a request the other devices honor in what they draw, not a reach into storage
the sender does not own. Anybody running a modified client keeps the words, and the app does not
pretend otherwise. Taking the bytes off other people's devices is consensus hard delete.

`Editing` holds the two windows and the one predicate; `Fold` gates the edit and tombstone branches
on it; `AppSession` refuses with `tooLateToEdit` and `tooLateToWithdraw` before writing, but neither
of those is what makes it true.

**Two defects the rig found and the tests did not.** The placeholder said *"This message was
deleted."*, the one word the feature exists to avoid. And the join prompt introduced the same room on
every launch: `PersistedState` decodes by hand and `greetedRooms` had never been added to the
decoder, so it was reset and rewritten empty every launch. Fixed, with a test that fails if any
persisted field the encoder writes is not read back.

</details>

</details>

<details markdown="1" id="hiding-follows-the-member-not-the-device">
<summary><b>Hiding follows the member, not the device</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want a message I hid to stay hidden on every device I own, so that the
thing I did not want to see is not waiting on my iPad.

**Acceptance criteria**

- **Done.** Hidden flags ride `MemberPreferences` on the sibling feed, which reaches the member's own
  devices and nobody else.
- **Done.** Every flag is stamped with when and which device; the later one wins; putting a message back
  records false rather than deleting the flag, so it can beat an older hide arriving late.
- **Done.** Revealing is per room and all-or-nothing, and messages return to their original places.
- **Done.** A local edit is authoritative on the device making it.
- **Done.** Hidden entries still sync; hiding reaches the projection and never the log.

**Testing**

- Suite: the preferences merge suites, including the same-instant edit that was silently dropped.
- Hardware only: a second device on one account has not been seen taking the flag.

**Design.** Boards 76, 77.

<details markdown="1">
<summary>Record — the bug this turned up, what it unblocked, and the known cost</summary>

Hiding is stored as a set of entry hashes rather than written as an entry, because an entry would
reach every peer and so announce that you had hidden something. The way back is in the ordinary
settings list, showing a count and not a list, because naming what was hidden would undo the hiding
for anyone reading over a shoulder.

**The bug.** A local edit was going through the merge rule, which is only correct for reconciling two
devices. When both stamps came from the same device in the same instant, `>` was false and the edit
was silently dropped, so tapping hide and then show inside one clock tick did nothing the second
time.

**What it unblocked.** The field is the shared one. The read-receipt opt-in and the per-room
notification level are both a field on it rather than a mechanism of their own.

**Known cost.** The sibling feed is republished whole on every change. It is bounded by how much a
person hides and tiny beside the room keys already traveling there; if it stops being tiny, the
answer is a separate record rather than a bigger feed.

</details>

</details>

<details markdown="1" id="hiding-as-the-set-draws-it">
<summary><b>Hiding, as the set draws it</b> — Complete (tested)</summary>

**Story.** As a member, I want hiding to behave predictably when I undo it, so that the reversal is
not its own surprise.

**Acceptance criteria**

- **Done.** Hidden messages are excluded from local search. `search()` reads through `messages(in:)`, which
  filters `isDrawn`, and `SearchTests` pins it: *A hidden message is not findable*. This criterion
  read **Not done.** until 2026-09-14, when the code was read.
- **Done.** The count stays a count, and the omission is stated so it does not read as a loading failure.
  A room says how many of its own messages this member hid, at the foot of the transcript, and
  tapping it shows them again. `hiddenMessageCount(in:)`, two tests in `HiddenCountTests`.
- **Done.** The hide sheet quotes the message it is about, and carries "nobody else is affected" before the
  buttons rather than after the act. It is a **confirmation dialog** and withdrawing is an alert,
  and the difference is Apple's own: an alert is for an uncommon destructive action that cannot be
  undone, and "Avoid displaying alerts for common, undoable actions, even when they're destructive"
  ([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)). Hiding can be
  undone; withdrawing cannot. The title is cut to one line, which is what Apple asks of a dialog.
- **Done.** **Hiding reaches this member's own other devices.** `hiddenEntries` lives on `MemberPreferences`,
  which rides `SiblingFeed` and merges by stamp in `AppSession+DeviceSync`. Hardware-only to prove. Ruled 2026-09-13: the per-message hidden
  flags ride the sibling feed, the way the member-level preferences already do. The copy has said
  "your devices", plural, the whole time. The feed is sealed under the identity since 2026-09-13, so
  what somebody chose not to see is not readable by the transport.

**Testing.** Nothing yet. Restoring all-or-nothing per room, in place, is already built. **Design.**
Boards 76 (Delete for me: the paragraph must refuse the reading people bring to it) and 77 (Show hidden
messages).

</details>

<details markdown="1" id="consensus-hard-delete">
<summary><b>Consensus hard delete</b> — Pushed out</summary>

**Story.** As a member, I want to ask everybody in a room to destroy a message, so that something
said by mistake can be unsaid with their agreement rather than over their heads.

**Acceptance criteria** — pushed to [After TestFlight](../after-testflight.md) on 2026-09-14.

- **Deferred.** Offered as a room action beside the ordinary soft delete, and only with *Show hard delete by
  consensus in rooms* on in security settings. The setting does not prevent receiving a request.
- **Deferred.** Succeeds only with every member approving; the initiator can close the request.
- **Deferred.** On success the data is purged and members get a push reading exactly **"Consensus reached."**,
  carrying no identifier of what it related to.
- **Deferred.** On failure each participant chooses: keep, kept from syncing to members who chose hard delete;
  soft delete, hidden and restorable; hard delete, gone and never re-synced.
- **Deferred.** **Silence is silence.** Somebody who never answers neither consents nor refuses; the request
  hangs until the member who started it closes it. Ruled 2026-09-13 — both timed answers put a
  decision in somebody's mouth.
- **Deferred.** **Tapping the push opens the room** and shows, **where the message was, permanently**, a line
  saying it was deleted by consensus. The push still carries no identifier; the device folding the
  tombstone knows the room, so this is not a guess.
  **The form is settled — Griff, 2026-09-15**, after the HIG was read as he asked. It is not a
  transient notice: Apple says to prefer "an alternative way to communicate it **within the relevant
  context**" and offers "a nonintrusive label", and there is no toast in the HIG because Apple does
  not want one. The relevant context for a deleted message is the gap it left, and the transcript
  already draws system lines there. A notice the member misses is a thing the app did not tell them.
  See [Decisions](../decisions.md#a-deletion-leaves-a-line-in-the-transcript-not-a-notice-that-fades).

**Unblocked 2026-09-09.** A purge is a tombstone and the link survives it — see
[Decisions](../decisions.md#a-purge-is-a-tombstone-and-the-link-survives-it). Repair, the other
dependency, was built 2026-09-06. Nothing here is blocked; none of it is built.

**Design: needed** for the request, the vote, the outcome and the three-way choice.

</details>

<details markdown="1" id="hard-delete-and-desync-quietly">
<summary><b>Hard delete and desync quietly</b> — Pushed out</summary>

**Story.** As a member, I want to destroy something and stop syncing with the people who kept it,
so that I am not forced to keep re-receiving a thing I have refused.

**Acceptance criteria** — pushed to [After TestFlight](../after-testflight.md) on 2026-09-14.

- **Deferred.** Behind the same security setting as consensus delete.
- **Deferred.** The flag is silent to the other party, and the app is honest with its own member that it is.
- **Deferred.** What "silently" costs is stated: the conversation diverges, and the app cannot repair it.

**Unblocked by the same decision.** **Design: needed.**

</details>

## What is still open

The question that blocked this epic, what a purge does to the hash chain, was answered on 2026-09-09:
the entry stays, its payload becomes a tombstone, and the chain verifies unchanged. The price is that
a purge is visible and not deniable. The three smaller questions are answered too: a *Consensus
reached.* push opens the room and leaves a permanent line in the transcript; a member who never
answers does not consent and does not refuse, so the request stays open until its starter closes it;
and hiding reaches a member's own devices. See [Decisions](../decisions.md#deleting-and-hiding). What
is left is building consensus deletion, [after TestFlight](../after-testflight.md#consensus-hard-delete).

## Test plan

<details markdown="1">
<summary>Three accounts; consensus cannot be tested with two</summary>

**Soft delete, built.** Hide on A: it disappears from A and stays on B and C. Hide a message before
it has ever synced: it still reaches B and C, the case that would withhold it if hiding reached into
the log. Relaunch A: still hidden, and the count in You is right. Show hidden messages: it comes
back, in place, in order.

**Repair.** Remove an entry from B's log by hand: B's repair names it and recovers it. A message A
soft-deleted is not reported missing on A.

**Consensus.** A requests; B and C approve: gone from all three, each gets "Consensus reached." with
nothing identifying. A requests; B approves, C abstains: nothing is purged, each is offered the
three-way choice. C chose hard delete: A, who chose keep, stops attempting to sync it to C. Somebody
with the setting off still receives and can answer a request.

</details>

**What would falsify the epic.** A message destroyed on somebody's device without their agreement. A
"consensus reached" push that identifies what it was about. A history that fails to load after a
purge. The last is the one to watch: it is the hash chain, and it is why the open question comes
first.
