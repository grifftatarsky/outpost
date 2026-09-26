---
# COPY BEGIN 718b2f42 [NEEDS HUMAN REVIEW]
title: Inbox
layout: default
nav_order: 7
---

# Inbox

{: .no_toc }

Things noticed and deliberately not acted on, parked here so they stay findable.

Nothing here is a commitment. The [Roadmap](roadmap.md) holds work groomed into stories, and
[Open questions](open-questions.md) holds what needs Griff's answer. This is the rest. Take something
out by doing it, or by writing down why it does not matter. Closed items are deleted; what they taught
is in `CLAUDE.md` under the traps, and what happened is in git. Checked against the code on
2026-09-17.

1. TOC
{:toc}

<!-- COPY END 718b2f42 -->

<!-- COPY BEGIN 9d913254 [NEEDS HUMAN REVIEW] -->

## Privacy, on the wire

**The anonymity is in the app, not on the wire.** Everybody a member has not met is drawn as one
shared figure, and every route from a comment to a name goes through `Projection.member(_:)`. What
that cannot reach is the envelope: an entry's author, device, room, sequence number and time sit
outside the seal. So somebody reading their own database can group an Outpost's anonymous comments by
author and count how many strangers read it. They cannot learn who. Sealing the author does not help;
see [Decisions](decisions.md#identity-stays-in-the-envelope-and-the-seal-is-the-wrong-place-for-it).

**Entries sealed before 2026-09-07 are not bound to their writer.** New seals carry the author and
device in the associated data, and `SealedPayload.opened` falls back to the old two-field context for
entries written before that. The fallback is permanent, so anything sealed before the fix can still be
lifted into another member's entry in the same room and epoch.

**An Outpost's room ID is half its owner's identity.** `RoomID.outpost(of:)` is the first 16 bytes of
the owner's `ParticipantID`, in the clear on every entry. It has to stay derivable so two devices
never disagree, which is what stops it being blinded.

**A friend of a friend stores and forwards sealed entries from a room they are not in.** Carol, who
shares a room with Bob and has never met Alice, ends up holding Alice's entries from a room Carol is
not in. She cannot read them; she can see that the room exists, who writes in it and how often.
Narrowing it means deciding per recipient what to offer, and two designs for that were declined on
2026-09-07 because both lost messages: a device tracks what it is missing per feed, and a feed
interleaves every room its writer is in, so a withheld entry becomes a hole nobody can fill or tell
from a real loss. `IntegrityReport` counts it as *Carried for other people* on the History check.
Not read on the rig yet.

**A clip plays from a readable file for the length of a launch.** `AVPlayer` reads files, so an opened
clip sits in the temporary directory, under complete file protection, until the next launch clears
it. A resource loader that decrypts ranges on demand would end it.

**A stolen unlocked phone gives up everything that phone holds.** The in-app lock was canceled because
iOS locks apps behind Face ID better than the app could. What is still missing is a sentence where the
app talks about what somebody with the phone can see, saying that iOS does the locking; see
[After TestFlight](after-testflight.md#an-in-app-lock).

<!-- COPY END 9d913254 -->

<!-- COPY BEGIN e80f8f25 [NEEDS HUMAN REVIEW] -->

## Membership

**A grant can reach somebody just removed.** If a removal entry fails to verify in a round (a device
certificate not yet arrived), that device holds the new epoch with a stale roster, and the next
outbound round could hand the removed member the new key. `AppSession.withholdsKeys` holds a room's
keys for one round when the last round refused something and somebody has been removed from that room.
The rule is tested; the round is not, because building a real mid-round refusal on top of a real
removal needs a third participant.

**Two concurrent advances could mint rival secrets for the same epoch.** *An audit's claim, not
verified.* One advancer is guaranteed per membership change, not per epoch number; two members removing
the same person inside one sync interval is the natural way in. On
[Proofs a rig cannot run](proofs-a-rig-cannot-run.md).

**A removal entry is offered once and its address expires.** *An audit's claim, not verified.* The entry
goes out once under one day's tag, and readers look back seven days, so a device that does not sync
for eight days might never learn it was removed, and its composer would stay live.

**The third and fourth member of a room have not been seen on real accounts.** `MembersOverTimeTests`
grows a room one member at a time against the fake mailbox, and the rig has shown it above the mailbox.
A third Apple Account without Advanced Data Protection would settle it over CloudKit.

**`requests` holds one invitation per person, so any member can decide which offer is on the table.**
Re-appending an earlier invitation's bytes makes it current again. Keying confirmations and admissions
by invitation guarantees an answer matches the offer it answers; it does not stop the offer being
swapped. The `.joinRequest` fold checks neither the signature nor the inviter's membership; both are
checked at write time only.

<!-- COPY END e80f8f25 -->

<!-- COPY BEGIN 7d12cbf4 [NEEDS HUMAN REVIEW] -->

**An invitation to somebody already in the room replaces the one they arrived on.** Nothing refuses
it, so *Who you are talking to* would show the new offer's date and characters over a check made
against the old ones. It is the only change in this area that touches people already in rooms, so it
was left.

**A withdrawal the room declined is still drawn.** The transcript draws *took back the invitation*
whenever the withdrawal decodes and the offer exists, so a withdrawal racing a join can be drawn in a
room the joiner is standing in. The fix is for the transcript to ask the roster.

**Only the original inviter can send an invitation again.** Any member may take one back, so a member
can end an offer they cannot remake. `attest(joiner:)` could support it; no screen offers it, and the
withdrawal sheet says so.

**The inviter is not told a confirmation arrived too late.** Recording it needs a persisted set keyed
by the invitation's signature, with a `decodeIfPresent` line and a name in
`decodingPersistedStateKeepsEveryFieldItWasGiven`, or it decodes empty on every launch.

**An invitation waiting on a split inbox shows on both tabs.** Found 2026-09-15: the Rooms tab was
given no awaiting invitations, so an invitation to a room showed only under Solos. Both tabs get it
now, so an invitation to a Solo also shows twice. The fix is for `AwaitingAdmission` to carry the kind
of room, a wire-visible change to make on purpose.

<!-- COPY END 7d12cbf4 -->

<!-- COPY BEGIN 95fed78f [NEEDS HUMAN REVIEW] -->

## Correctness

**Device sync can trap inside CloudKit on a conflict retry.** Seen once on the rig, 2026-09-07:
`EXC_BREAKPOINT` in `CloudKitEntrySync.Delegate.handleEvent`, at the `sendChanges()` inside the
`serverRecordChanged` retry, raised from CloudKit's own frames. A relaunch was fine. One crash is not
a diagnosis.

**A sync round runs before the identity is loaded.** `mailbox sync: peers=1 … rooms=0` is logged just
before `identity: load: ready` on every launch. Harmless as far as anything observed.

**`sync failed` is logged with no reason.** `AppRootView+Sync.swift` logs it from a flag, so the error
is gone before it is written down. The two refusals a member can act on, a full iCloud and being signed
out, are typed and shown; this is about everything else.

**A revocation that fails to verify on launch is dropped silently.** `restoreLog` replays
`persisted.revocations` with `try?`. An unknown device is the ordinary case and ignoring it is right; a
bad signature is not counted in `IntegrityReport` or logged.

**`grantsOwed`'s defensive path is covered by nothing.** `openRoomGrantsAtBaseEpoch` existed because a
grant once needed a link and the base epoch has none. An invitation now advances the epoch, so the
path is never taken.

**Posts and comments cannot be hidden.** Hiding covers messages, and reaches the member's own devices.

**`--reset-account` restarts device sync and undoes itself.** After the wipe, the change of session
state starts device sync again, which republishes a feed within about half a minute. The fix belongs in
the wipe: hold device sync down until relaunch. Until then, terminate the app as soon as the erase
lands.

**The recovery key's format is keyed on the product name.** `RecoveryKey.header` is
`OUTPOST RECOVERY KEY`, and reading a key looks for that prefix. Renaming the product would make every
saved key unreadable. The branding lint does not catch it because it matches the exact word. The fix
is to carry the source name in the format and the product name only in what a member reads, and it has
to happen before anybody saves a key from a shipped build.

**The saved key file has no useful name.** `RecoveryKeyView` shares a string through `ShareLink`, so
what lands in Files is named by the system rather than by the key's fingerprint. Two saved keys cannot
be told apart from the outside. Not re-checked on a phone since 2026-09-13.

<!-- COPY END 95fed78f -->

<!-- COPY BEGIN 88dfd060 [NEEDS HUMAN REVIEW] -->

## Tests

**`History from another device survives a relaunch` waits on a wall clock.** It rebuilds the session
every 50ms until the sibling's room appears, against a ten-second deadline. It failed once in a full
run on 2026-09-14 and passed four times alone. Raising the deadline would hide the next real failure
longer; the fix is to wait on the write.

**The UI tests run only by hand.** `CarpenterUITests` holds the accessibility audits and the rig steps,
which need booted simulators and minutes each. CI does not run them.

**Nothing measures cost outside the fold and screen reads.** `CausalOrder` on a long log, a round as the
outbox grows, and laying out a long transcript are unmeasured.

<!-- COPY END 88dfd060 -->

<!-- COPY BEGIN b81482a3 [NEEDS HUMAN REVIEW] -->

## Cost and scale

**Every packet is addressed to every peer.** A message in one room goes in a packet addressed to
everyone the sender holds keys for; the room key keeps non-members out. Traffic grows with a member's
whole circle rather than with the room, and the notification path has to narrow the audience back to
the room before ringing.

**A fetch reads whole zones.** `everything(in:of:)` pages a zone's change feed from the start every
round, with no change token. Correct, since a packet must be re-readable until acknowledged, but the
cost grows with what is in flight rather than what is new. Logs have shown 89 records scanned to find
one.

**Nothing cleans up bells.** One record per channel, overwritten, never deleted, because a delete would
ring the bell.

**The sibling feed is one record that only grows.** `CloudKitEntrySync` writes a device's whole sealed
feed, every entry, certificate and room key it holds and the member's preferences, into one field and
republishes it after every write. CloudKit accepted 16MB in a field, so it is not a wall yet, but a
member's hundredth message republishes the first ninety-nine to every device. Not measured at any real
size.

<!-- COPY END b81482a3 -->

<!-- COPY BEGIN 08ff1025 [NEEDS HUMAN REVIEW] -->

## Unwired or unwatched

**Reaping abandoned device feeds is written and tested, and not wired.** `AbandonedFeeds` decides which
feeds belong to devices that are gone. The deletion is destructive to a member's iCloud: wire it behind
a dry-run readout in the debug menu, watch it on a real account, then make it automatic.

**The sibling-device photo path is designed and unrun.** A second device asks its own outbox for the
bytes by name. Needs two phones on one account.

**The photo viewer's pan is unverified.** A bounded drag was added to a zoomed photo on 2026-09-13 with
a `GeometryReader` measuring the frame, and nobody has looked at it since. Open a photo before believing
it.

**A tapped invite link may not fill the field it opens.** Opening an invite link with `simctl openurl`
reached *Join a room* with the paste field empty. Confirm with a real tap.

**Backfill when two strangers meet is left undone on purpose.** See
[The one stranger](epics/rooms-and-membership.md).

**The rig holds a room named "Griff"**, made by the first *Send a Solo* before Solos were founded as
Solos. Left as a specimen.

<!-- COPY END 08ff1025 -->

<!-- COPY BEGIN 53ec92bc [NEEDS HUMAN REVIEW] -->

## Screens

**The people picker has no index bar.** SwiftUI has no first-class section index; a real one needs a
representable or a hand-drawn overlay, which native-first argues against.

**`RootView` presents fourteen sheets from its files.** They work. Setting a sheet's item from a `Task`
that finishes after a menu closed does not present it, so set the item in the menu action and let the
sheet fetch what it needs.

**A sheet handed a snapshot of `session.rooms` shows what had loaded.** On a cold start a room's name
arrives over a second or two, so a link tapped during launch can open a picker on an incomplete list.
`AddSomeoneView` re-reads on every draw; other sheets that capture a name at presentation have not been
checked.

**`AddSomeoneView` starts a new room through a nested sheet**, and afterwards the member is still on
the picker looking for the new room. It should make the room and issue the invitation in one step.

**A picture chosen for an Outpost stays on one device**, like a photo chosen for somebody in People.

**A keychain error a member reads says nothing.** When an account went *Temporarily Unavailable* on the
rig, the app showed "CarpenterKeychain.KeychainError error 1." and loaded fine next launch. Two
questions: what it should say, and whether one failed keychain read should stop a launch at all.

**Some readouts hand-roll what a `List` would give them.** `JoinRequestsView` and `IntegrityView`
would become `Form`s cheaply. The accent and icon pickers are legitimately custom grids.

**The empty rooms list cannot be pulled to refresh.** A bare `ContentUnavailableView` has no scroll
view. Putting the empty state in an overlay above the list was tried on 2026-09-14 and the pull showed
nothing, because the overlay covers the list's refresh indicator; it was reverted. The foreground loop
syncs every 20 seconds regardless. Worth a look with the HIG open.

**"13 of 16" sits below the fold on the longest check-up questions.** The position is in the section
footer, under the Next button's inset until you scroll.

**The Focus permission prompt holds the check-up's finish.** Choosing to share Do Not Disturb asks the
system for Focus access, and nothing is saved until that alert is answered, so a check-up can look
stuck behind a sheet.

<!-- COPY END 53ec92bc -->

<!-- COPY BEGIN 6444fc57 [NEEDS HUMAN REVIEW] -->

## Accessibility

**Apple's own audit still fails on the Conversation screen**, and this is the one screen in the app
where it does. Measured 2026-09-17 by running `AccessibilityAuditTests` rather than reading the
palette, which is what the contrast tests in the suite do. After the two defects found that day were
fixed, what is left on that screen is:

| Issue | Count | What it is |
|---|---|---|
| Dynamic Type partially unsupported | 15 | The transcript's system lines and timestamps — "Trig invited Quad", "4 members", a bubble's time — drawn at a size that does not scale the whole way. |
| Contrast failed / nearly passed | 5 | The same transcript system lines, tertiary text on the bubble ground. |
| Text clipped | 1 | *3 people here can't see your Outpost* in `OutpostReviewPrompt`, truncated rather than wrapped. |

**Why it is parked rather than done.** The Dynamic Type rows are one decision about how the
transcript's non-message lines scale, which is a design question for Griff rather than a bug — and
the roadmap's accessibility row claims "Dynamic Type and contrast done", which is true of the
palette and the screens' own text and is not true of these. Recorded here rather than silently left,
and the roadmap row now names the gap.

**Fixed on the way, not parked:** `Later` in `OutpostReviewPrompt` was a 31x16pt button, under the
44pt floor; and the prompt's `person.2.badge.key.fill` was decorative and unhidden, so VoiceOver read
the symbol's name aloud.

<!-- COPY END 6444fc57 -->

<!-- COPY BEGIN 3c1b60bb [NEEDS HUMAN REVIEW] -->

## The switch sweep of 2026-09-17

**Every member-facing switch in the app was traced to the code that reads it**, after three
consecutive defects in a row turned out to be the same shape: a control or a sentence whose effect
nothing tested — the Focus filter's preview switch not reaching a post, the two badge switches
reaching nothing at all, and two screens whose VoiceOver announcement nobody had heard.

**Fifty-six toggles. All but one trace to something that reads them.** The badge pair was the last of
its kind, and it is fixed. What the sweep turned up:

| Found | What it was |
|---|---|
| `ThemeStore.showsTabBarWhenSidebarCollapsed` | Stored, persisted to `theme.tabBarWhenCollapsed`, read by nothing and drawn by no control. Vestigial from the Mac sidebar work. **Deleted.** |
| *User Avatars* | The one control label in title case, and the one saying "user" — every neighbour is sentence case and the app says picture or photo to a member. Now *Pictures in conversations*, with the footer to match. |

**What the sweep does not prove.** It traces a switch to a *reader*, not to a *test*. Nine privacy
accessors are never named in the suite, which looked alarming and is not: the tests go through the
session's setters rather than the stored property, which is the right way round. `SharingTests`,
`FocusStatusTests`, `PrivacyCheckupTests`, `OutpostReviewOfferTests`, `SoloVerificationTests` and
`BeingToldAboutARestoreTests` cover the behavior behind them.

**How to redo it** if a batch of settings is ever added: list every `SettingsToggle`/`Toggle` and its
binding, resolve the binding to the accessor behind it, and grep that accessor outside
`MemberPreferences.swift`, the tests and the settings screens themselves. A hit count of zero is the
signal. `Scripts/lint/control-label-case.py` now holds the second half automatically.

<!-- COPY END 3c1b60bb -->

<!-- COPY BEGIN 14373dcf [NEEDS HUMAN REVIEW] -->

## Tooling

**`RandomSource` is a seam nothing uses.** Every byte of key material comes from CryptoKit directly,
which is the good outcome, but the file reads as though a seam existed. Delete it or say what it is
for.

**The Reduce Motion lint excuses a whole file for one mention.** Rule 6 passes a file if it consults
Reduce Motion anywhere, so one unguarded animation among guarded ones passes. Every animation was read
at its call site on 2026-09-16 and none is unguarded. Tightening it to per call site is a mechanical
pass across the tree, with `cross-fade only` added to the cross-fades.

<!-- COPY END 14373dcf -->

<!-- COPY BEGIN 16d05a2e [NEEDS HUMAN REVIEW] -->

### The conversation screen still costs ~3,500µs a read

`deliveryMarks(in:of:)` is most of it:
`peers()` about 800µs, `unsentEntries()` about 700µs. Neither can be cached on a fold alone, because
blocking and the synced frontier change without one, and a stale one looks like a message that did not
send. `ProjectionCostTests` pins both reads at 5,000µs so they cannot get worse.

**Doc comments survive in the source.** Despite the rule that the repository has no comments, 152
lines of `///` remain, for example in `ShortAuthenticationString.swift` and
`MembershipAttestation.swift`, plus a few `//` lines such as one in `RootView+Phone.swift`. The lint
does not catch `///`. Found 2026-09-17 during the documentation pass.

**`AppIcon.appiconset` carries Mac sizes of an old drawing.** The Mac is not offered.

<!-- COPY END 16d05a2e -->

