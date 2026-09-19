---
title: Roadmap
layout: default
nav_order: 5
has_children: true
---

# Roadmap

{: .no_toc }

Every ticket in the product and where it stands.

1. TOC
{:toc}

## How to read this

Epics are areas of the product. Tickets are pieces of work inside them. Neither has a number; a
ticket is called by its name, and that name is the heading of its story on the epic's page.

This page is the status of record. Each ticket has exactly one status:

| Status | Meaning |
|---|---|
| **Complete (tested)** | Built and seen working. Where the network is involved, seen on two devices on two Apple Accounts. |
| **Complete (proved above the mailbox)** | Seen working on three devices, with a directory standing in for CloudKit. The logic is proved; the transport under it is not. |
| **Complete (QA required)** | Built and the suite is green. A proof that a rig *can* run has not been run, or ran only in part. This status is work somebody still has to do here. |
| **Complete (hardware proof owed)** | Built and proved as far as a simulator goes. What is left needs a phone, and is named on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). Nothing on this list is waiting on a decision or a keystroke at this desk. |
| **Complete (operational proof owed)** | Built, and waiting on something outside the app existing — a live mailbox, a vault. Also on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| **Incomplete** | Some acceptance criteria are met and some are not. |
| **Not started** | Nothing built beyond what the log format already allows. |
| **Pushed out** / **Canceled** | Decided against for now, or for good, with the reason on [After TestFlight](after-testflight.md). |

A green suite has been wrong about CloudKit more than once here, which is why "tested" means the
real transport rather than a passing run.

**The bar for "a rig cannot do it" moved on 2026-09-14**, and it moved a long way. A packet is
addressed by a `RecipientTag` and never by an Apple Account, so two whole `AppSession`s sharing one
zone in **one** account prove an entire round over real CloudKit. Thirteen rows that said *unproven
on two accounts* were proved that way in an afternoon. Before anything is called un-runnable, that
trick has to have been tried.

**The Mac and iPad are not on this page.** Griff ruled on 2026-09-13 that the product is iPhone
until TestFlight, and on 2026-09-14 that the desktop work should be sequenced *after* it rather than
carried alongside. It has its own page — [the desktop roadmap](desktop-roadmap.md) — and nothing on
it is scheduled until an iPhone build is up. This page is the iPhone product.

**Nor is verification that needs a third Apple Account.** An account cannot take part in its own
share, so a three-party proof genuinely needs a third account and no rig trick stands in for one.
Those proofs live on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md) with what shipping without each
one costs. Anything three-party that the rig *can* prove above the mailbox stays on this page.

**Nor is anything else that waits for a build in somebody's hands.**
[After TestFlight](after-testflight.md) carries the work taken off this page on purpose, and the
reason each one came off. A ticket canceled outright is recorded there rather than deleted.

The epic pages carry the long form: the story, the acceptance criteria, what was observed and when,
and the test plan. [Open questions](open-questions.md) holds what is unbuilt or uncertain.
[Inbox](inbox.md) holds what was noticed and parked.

## Where everything stands

Seven epics, 87 tickets, counted 2026-09-17.

| Status | Count |
|---|---|
| Complete (tested) | 60 |
| Complete (proved above the mailbox) | 5 |
| Complete (QA required) | 0 |
| Complete (hardware proof owed) | 16 |
| Complete (operational proof owed) | 3 |
| Incomplete | 1 |
| Not started | 0 |
| Pushed out or canceled | 3 |

<details markdown="1">
<summary><b>Getting a message there</b> · 11 tickets — 10 tested · 1 proved above the mailbox</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Messages between two people, through the mailbox | Complete (tested) | Both ways, app closed, two in succession: 2026-09-01. Two steps need hardware. |
| Delivery marks, and who reports | Complete (tested) | Sent, delivered and read marks seen both ways 2026-09-05; "does not report" seen 2026-09-01. |
| A round bigger than a packet | Complete (tested) | `PacketCapTests` above the mailbox, and Proved over real CloudKit 2026-09-14: twenty-four entries sent, all twenty-four arrived, **in the order they were written** — the real server returns a zone unordered, so this is the test a fake cannot stand in for (`LiveRoundTests`). |
| The rendezvous heals a dead share | Complete (tested) | Rotated on purpose 2026-09-05: retracted, re-offered, accepted, a message each way. |
| A round acknowledges every packet it can | Complete (tested) | `RoundAcknowledgementTests`, and Proved over real CloudKit 2026-09-14: a twenty-four packet round settled and the outbox emptied, with nothing left on offer (`LiveRoundTests`). |
| Solos: a conversation with one person | Complete (tested) | *Send a Solo* founds one as a solo; both sides list it under Solos and title it by the other (`SoloTests`). Seen beta → alpha 2026-09-05. |
| Sending feels like sending | Complete (proved above the mailbox) | Send failure inline, iCloud refusals named, arrival animation — all built. 2026-09-16: the ruled not-sent mark — an orange circle replacing the delivery marks when two newer messages have been collected or the room's time (1–7 days or off, three if unset) has passed, with a sheet saying why and a link to the room setting — and the refusal sentence shown in the conversation. `NotGoneTests`. Seen on the rig in the demo Solo; a real stuck message and a full iCloud still need a device. Rig, 2026-09-17: the orange mark on a message really left uncollected for four days, and its sheet. And both refusal sentences, forced on the rig — which found the rooms list's *Nothing is going out* had never been drawn on the phone, fixed. |
| Per-room read reporting | Complete (tested) | A room can report while the rest do not, or never report while the rest do; each change writes that room's own `readPolicy` entry (`PerRoomReportingTests`). Proved over real CloudKit 2026-09-14: a reader reported a message shown and the sender's mark moved (`LiveRoundTests`). |
| The read-by detail view | Complete (tested) | A section on message detail, reached from the message's own actions and never from the marks, in the marks' own words (`WhoHasReadItTests`). The observation it draws proved over real cloudkit 2026-09-14. |
| Repairing a history with holes in it | Complete (tested) | Gaps named from an index kept where entries enter, chased after two minutes, answered with what a peer holds (`HistoryRepairTests`). Proved over real CloudKit 2026-09-14: a packet was deleted off the server, the reader named exactly one missing entry, asked, and **got the words back** (`LiveRoundTests`). This row said a hole recovered over the network had never been seen. |
| A draft that survives | Complete (tested) | One per conversation, one for a new post, one per comment, back after a relaunch; a conversation's shows in the rooms list as *Draft*, cleared by sending; Outpost settings deletes the Outpost's. Sealed on disk under a key kept in this device's keychain (`DraftTests`); walked on gamma 2026-09-19 (`RigChecks.testDraftSurvives`). A failed reply from a banner joins it — [epic](epics/messaging.md#a-draft-that-survives). |

</details>

<details markdown="1">
<summary><b>Telling someone it arrived</b> · 11 tickets — 4 tested · 7 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| A bell that rings for a message and nothing else | Complete (hardware proof owed) | The bell is written, subscribed to and **rung**: alpha logged `mailbox: rang a peer's bell` on 2026-09-14 with beta backgrounded, and **no push reached the app over five minutes** — measured, not inferred. Everything up to delivery is proved; delivery is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Notification previews | Complete (hardware proof owed) | Four rungs, per room, driven on the rig. The extension's banner needs a push to draw it — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Unread, and the number on the icon | Complete (tested) | Dot and badge on beta 2026-09-02, cleared by reading. The extension's half rides on the push. **2026-09-17: the number ignored the member's own switches** — `BadgeCount` counted unread rooms unconditionally, never read `BadgeChoices` and never counted Outposts, so two controls on the Notifications screen did nothing and all four sentences of `BadgeMeaningLine` were false. Fixed, and it is one `AppSession.badgeNumber` the app and the extension share rather than a sum written twice ([Decisions](decisions.md#the-number-on-the-app-icon-is-one-property-and-it-obeys-the-switches)). Measured on Quad: 1 with an unread room, none once the switch was off with the message still unread, and back again. |
| Asking for notifications honestly | Complete (tested) | Explainer on the first ready screen on both simulators 2026-09-04. |
| Tapping through, and what happens next | Complete (hardware proof owed) | A banner for a room this member no longer has opens the app and navigates nowhere; one tapped while already in that room does nothing. The decision sits in `AppSession.tapping(_:whileViewing:)` so it is testable (`TappingThroughTests`). Watching a real banner be tapped is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| A banner from a person | Complete (hardware proof owed) | The extension attaches the sender, their photo and the conversation to every banner that names them, and since 2026-09-13 a banner about a post prefers the picture on the wall it came from (`ABannersFaceTests`). Seeing one drawn is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Silenced notifications, shared | Complete (tested) | Two switches and a custom message (`FocusStatusTests`). Beta's pretend Focus drew *Do Not Disturb*, then *Heads down till six*, over alpha's field 2026-09-06. |
| Focus filters | Complete (hardware proof owed) | A filter per Focus: which rooms may notify, whether banners carry the words (`FocusFilterTests`). 2026-09-17, found while making the extension's decisions testable: *Show what was said* was applied to a message and not to a post, so a Focus set to hide it still put a post's body on the lock screen. Fixed — the preview switch reaches a post, the room list deliberately does not ([Decisions](decisions.md#a-focus-filters-preview-switch-reaches-a-post-and-its-room-list-does-not)). A simulator has no Focus — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Settings split by what rings | Complete (hardware proof owed) | Notifications is a master switch over two pages, Messaging and Outposts, each with its own urgency; badges carry a separate setting saying what they count. `NotificationLevelTests`, `BadgeCountTests`, `WhatTheTabsBadgeTests`, driven on the rig 2026-09-11. Seeing one with a real push is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Asking for Outpost notifications | Complete (tested) | A step in onboarding, and a gear on an Outpost's own page for one wall at a time. Walked end to end on two Apple Accounts 2026-09-15: beta allowed alpha in from the room banner — behind an alert that says plainly it cannot be undone — beta posted, the post crossed, Outie appeared on alpha's rail, and the gear on that wall carried *Get notifications for this Outpost* with the honest footer that the other person is not told. Turned on and it held. |
| Answering from the notification | Complete (hardware proof owed) | Reply and Mark as Read on a message banner, through the composer's send path (`NotificationAnswerTests`). Proved above the mailbox on gamma and delta 2026-09-19, warm and cold, after two faults the rig found: a reply dropped because a cold launch's window answered before the session had loaded, and a reply left unsent because the app was suspended while a round was flagged to go again. Then on alpha and beta, two Apple Accounts over CloudKit, the same day: a warm reply, a cold reply and Mark as Read. The extension attaching the actions to a real push is phone-only — [epic](epics/notifications.md#answering-from-the-notification). |

</details>

<details markdown="1">
<summary><b>Who is in a room</b> · 21 tickets — 14 tested · 3 proved above the mailbox · 2 hardware proof owed · 2 operational proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Setting up a room | Complete (tested) | Creation sheet, policies, people picker, the invitee's sheet: 2026-09-01 and 02. |
| Removing somebody | Complete (tested) | Removed member could not read the next epoch: 2026-09-02. Two-member case only. |
| Leaving properly | Complete (tested) | Beta left, both drew it, alpha turned the key: 2026-09-02. |
| Blocking a person | Complete (tested) | Local silent block built 2026-09-04; the key handover built 2026-09-14 against six tests. A blocked person is not a peer, so nothing of theirs is collected or acknowledged and their app stops being told *collected* — which is the signal the convention runs on — they are handed no future room keys, no media and no bell, and they are dropped from the Outpost audience. Nothing said while they were blocked is lost. The epoch turn this was first specified with was dropped on building it: in a group every other member re-grants the key anyway. |
| Reporting a message | Complete (operational proof owed) | Sheet seen on the rig 2026-09-04 and its copy checked. The addresses exist and receive mail (Griff, 2026-09-17); a send from a phone has not been watched, and the vault a filed report goes into does not exist yet — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md) and [Before TestFlight](pre-testflight.md#operational). |
| Per-person Outpost access | Complete (tested) | The wall is sealed to the people let in, two offers enforced by which epoch links a grant carries, the room's review, the allow-list and the reciprocal card. Driven on two accounts three times, 2026-09-07. |
| The one stranger | Complete (proved above the mailbox) | A comment seals under the wall it lands on, so everybody unmet is one shared figure. Nine tests, four mutation-proven. Three devices, 2026-09-09: the same comment drew as *Quad* to somebody sharing a room and as *User 403* to somebody sharing nothing. |
| Open or closed on other people's Outposts | Complete (proved above the mailbox) | Three answers plus off, asked in the check-up after both doors and changeable in Outpost settings. Closed seals a comment under the writer's own wall and carries a second copy for the post's author, so it never refuses. Sixteen tests, six mutation-proven. Three devices, 2026-09-09: the owner read both closed comments; the co-reader read *2 comments are not shown*. |
| A confirmation answers one invitation | Complete (tested) | Keyed by the invitation rather than the person, so somebody asked back after a removal reads the six characters again. The room's own half was closed 2026-09-14: `RoomRoster` keys admissions and refusals on the invitation too, so a vote cast for a superseded offer no longer admits somebody to the live one — pinned by `MembershipTests` and `JoinIsARoundTripTests`. |
| Invitations that are never accepted | Complete (operational proof owed) | The expiry is enforced at the inviter's relay as well as on the device holding the link and never in the fold; the two lists split on whether the offer was taken; taking one back is open to any member in good standing; a date you pick has a control. The relay gate wants an inviter who stays offline past the date, which is a clock the rig cannot move — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| An invitation is an offer, not an admission | Complete (tested) | All six stages built and driven on two Apple Accounts 2026-09-09: refuse, accept, take back, and the solo check both ways. |
| Solo verification | Complete (tested) | Solos are exempt from the room model and get their own check. Driven both ways 2026-09-09: held, confirmed, refused, reopened. |
| A design pass over verification | Complete (tested) | Ran 2026-09-09, the day the functionality was proved. Sixty-seven findings, thirty-one after deduplication, all fixed. |
| An invitation that runs out says so nowhere | Complete (tested) | `RoomRoster.lapsedInvitations` keeps them, the row says *Ran out yesterday, with nothing back*, and it offers no controls because every one of them was about a live offer. |
| A refusal throws the six characters away | Complete (tested) | The refused step carries the offer rather than the code, and both refusal screens draw the characters. |
| Padding on the join prompt's member list | Complete (tested) | Rows had no vertical padding and the avatars touched. Ten points on the stack, 2026-09-08. |
| The multi-step leave | Complete (tested) | Built and walked on the rig 2026-09-14. A confirmation dialog rather than an alert — Apple's answer for a choice related to an intentional action — offering *Leave and Review Outpost Access* / *Leave* / *Cancel*, with the reviewing choice shown only when somebody actually holds access chosen in that room, which the rig confirmed is correctly absent when nobody does. The review is a sheet. Three tests in `SessionLeavingTests`, including that access given for its own sake is not swept up. |
| Delete room for somebody removed or gone | Complete (hardware proof owed) | Built 2026-09-17 on the ruling of 2026-09-14: a deleted room's numbers are recorded as spent (`SpentEntry` in `Replica`), so repair never asks for them and a late arrival is not kept; the entries leave the log on disk, the keys the keychain, the photos the device. *Delete* replaces *Leave* on a room already left or removed — context menu, conversation menu, edit list — behind an alert. It reaches the member's other devices, waits for a departure to be sent, and leaves photos the member sent for the people owed them ([Decisions](decisions.md#deleting-a-conversation-reaches-every-device-waits-for-the-leaving-and-leaves-photos-for-others), `PROPOSED`). Nineteen tests, every guard mutation-checked. The live CloudKit test passed on beta 2026-09-17 — delete, relaunch, ask for history over the real wire, and the room stays gone — and fails with the machinery taken out. Seen on the rig 2026-09-17 above the mailbox: the removal notice, *Delete* in the conversation's menu and the room's context menu, the alert, the room gone and staying gone after a relaunch, and being invited back. **Owed**: deleting on one phone reaching another, which needs one account on two phones. |
| Verifying who somebody is, later | Complete (hardware proof owed) | 2026-09-16, on Griff's answers: any two people can compare a two-half code from *Who you are talking to* (the invitation's characters only ever existed between inviter and invited); the comparison is offered once per person; *They match* is a dated note to yourself with what happened since; and *Alex added a device* appears, dated, in conversations with them, replacing a fingerprint-change warning that cannot happen when identity is keys. Not yet seen on a screen: needs a third account, or one account on two phones. Rig, 2026-09-17: the compare page on both phones with the same halves; it found a removed member offered a comparison with their own inviter, fixed. With a third member: the offer reached the right pair and not the inviter, and it found the offer skipped a new joiner's first visit, fixed. Owed: the device line, one account on two phones. |
| Why nothing is happening | Complete (proved above the mailbox) | 2026-09-16: *Who this is waiting on*, in the conversation menu and linked from the not-sent sheet, names each person in the room, whether they hold everything you sent there, and when this phone last heard from them — from the same record as the delivery marks. A status, not a fault. `WaitingOnTests`. Needs a two-account room on the rig. Seen on the rig 2026-09-17 naming Quad, with when Quad was last heard from. |
| The removal audit's open cases | Complete (tested) | 2026-09-16: `RemovalSurvivesACrashTests` cuts a removal off at both of its halves and relaunches. Before the fix, both left the key unturned **and the removed member read what was said next**. A removal now records the key turn it owes before it writes, the way an Outpost revocation already did, and every round retries it. The two three-party cases are in [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |

</details>

<details markdown="1">
<summary><b>Your identity across your devices</b> · 11 tickets — 7 tested · 1 proved above the mailbox · 2 hardware proof owed · 1 canceled</summary>

| Ticket | Status | Evidence |
|---|---|---|
| The sibling feed is sealed before it is written | Complete (tested) | Found and fixed 2026-09-13: the record had carried every epoch secret the member held, in the clear, since 2026-08-16. `SiblingFeedIsSealedTests`, mutation-proven. Proved over real CloudKit 2026-09-14: the raw CKRecord was fetched back off the server and the epoch secret is not in it, the payload is exactly the ciphertext, the member's identity reopens it and a stranger's is refused — and a second device was handed it and opened it (`LiveSiblingFeedTests`). The iCloud Keychain hand-off that makes two *real* devices one member is hardware-only. |
| One identity across a member's devices | Complete (hardware proof owed) | Keychain hand-off, device list, revocation, the checking screen: built. The sibling feed's wire and its delivery between two device identifiers were proved over real CloudKit 2026-09-14; the iCloud Keychain hand-off that makes two *real* devices one member cannot happen on a simulator — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Erase everything | Complete (tested) | Run from the sheet on alpha, 2026-09-15, which is what this row was waiting for. The sheet lists what is erased and — the half that matters — what is **not**: nothing leaves anybody else's device, rooms are not told, and nobody can restore it. A confirmation dialog then says the same in one sentence. The wipe ran, and the app came back to onboarding on a genuinely empty account. |
| Recovery settings, and telling people a restore asked them | Complete (tested) | Ruled 2026-09-13 and built the same day, against 24 tests. The recoverer chooses whether to ask peers at all; the person asked is always told, and can hold it behind a solo check. This row read "None of it built" until 2026-09-14, when the code was read — and writing a live test that day found the notice **defaulted to off**, with the friendly preset turning it off explicitly, so the members least likely to go looking were the ones not told. Fixed and pinned. The quiet restore — asking nobody, telling nobody, coming back to empty rooms — is proved over real CloudKit (`LiveRecoveryTests`). |
| Recovery from a lost device | Complete (tested) | *I have a recovery key* on the welcome screen **and on the stalled screen a new phone on an occupied account actually lands on** — it was reachable only from onboarding until 2026-09-13, which put it out of reach in the one case it exists for. The key is read on the device, the identity goes back in the keychain, a fresh device key is minted. Run end to end on two accounts 2026-09-13: export, restore, the room and its history back, and the peer's entries back after the restored device raises its own repair. What the rig found and the suite had not: a peer never re-offers an entry it has already spent, so a restored device has to raise its own repair (`askEverybodyForWhatWasSaid`) — without it `entriesReceived` was 0 on every round while the peer wrote `unsent=0`, and the peer's messages and even their display name never came back. With it, the room, both members' messages and the names all return. `RestoringFromAKeyTests` covers the round trip, the new device key, the sibling-device path, the peer path (mutation-proven), a device that already has a member, and each of the four ways a key can be wrong. |
| An in-app lock | Canceled | Ruled 2026-09-14. iOS locks apps behind Face ID already and enforces it better than the app could. [After TestFlight](after-testflight.md#an-in-app-lock). |
| The device list tells the truth | Complete (hardware proof owed) | Every device used to self-certify at `.distantPast`, so *here since you made this identity* was true of the founding device and claimed by every later one — and a relaunch re-issued the certificate, making *added* really mean *last launched*. Both fixed 2026-09-13, with a third found on the way: on a fresh install the device a member is holding read *never been used*. A fourth was found on the rig the same day, once eight devices had accumulated: a device that had spoken plenty read *added, but it has never been used — setup may not have finished*, because `hasSpoken` is computed from the entries **this** device holds and a restored device holds few. That is an inference from absent evidence, which this app does not make about anything else; it now says what it knows — *nothing it sent has reached this device* — beside the real date. Each device also carries a **name** now — from its hardware identifier on first launch, renameable, private to the member because preferences ride the sealed sibling feed. `TheDeviceListTellsTheTruthTests`, `NamingYourDevicesTests`. A device that has written nothing now reaches its sibling's list and can be revoked, 2026-09-16 (`aSilentSiblingReachesTheList`; unproven across CloudKit). The one-identity-per-account policy is decided and enforced: an occupied account stops, and since 2026-09-16 one that cannot be reached waits (`ExistingRegistrationTests`). |
| Names and faces shared by choice | Complete (tested) | Names and photos both ways, off by default (`SharingTests`, `PhotoSharingTests`). Beta's photo collected on alpha and taken down again 2026-09-06. |
| A privacy check-up at first run | Complete (tested) | Three doors after the name, with examples (`PrivacyCheckupTests`). Both the preset and the walkthrough seen on the rig 2026-09-06. |
| A name and a face of your own for somebody | Complete (tested) | Nickname on the sibling feed, photo on this device, a People page under the identity row (`NicknameTests`). Seen on the rig 2026-09-06. |
| Supporter: the TestFlight year and the badge | Complete (proved above the mailbox) | Built 2026-09-17: the bar, the thank-you page, the badge question, the Supporter page and the badge on avatars (`SupporterStandingTests`, `SupporterBadgeTests`). The whole flow on gamma, and gamma's badge drawn on delta, over the directory mailbox. Re-run on gamma 2026-09-17 against the current build, both paths: the bar, the thank-you page, the badge question, the badge on the You row and the Supporter page; and the decline path, which leaves the bar gone, the year kept and the pencil where it was. That run **found the check was not repeatable** — it had claimed the year on a previous run and could never pass again, which is a check that silently stops checking. `--forget-supporter` clears the three preference fields on launch, in `#if DEBUG` and on the release-leaves list, and both tests now take it. Not yet seen on a TestFlight build, and the App Store purchase is not built. |

</details>

<details markdown="1">
<summary><b>Taking things back</b> · 5 tickets — 2 tested · 1 hardware proof owed · 2 pushed out</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Editing and withdrawing your own words | Complete (tested) | Edit and withdrawal reached the other account 2026-09-02. |
| Hiding follows the member, not the device | Complete (hardware proof owed) | Built 2026-08-18 with tests; the flags ride `MemberPreferences` on the sibling feed and merge by stamp. The feed itself crosses real CloudKit; hiding on one real device and seeing it hidden on another needs the keychain hand-off — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Hiding, as the set draws it | Complete (tested) | Two of four criteria were already built and unmarked — search exclusion and reaching the member's own devices — both found by reading the code 2026-09-14. The other two were built and walked on the rig the same day: the confirmation quotes the message and states the scope before the buttons, and the transcript says *1 hidden by you. Nobody else is affected.* at its foot, which shows them again when tapped. |
| Consensus hard delete | Pushed out | Ruled 2026-09-14. Unblocked and unbuilt; the most protocol-heavy unbuilt feature here, and nothing shipped claims it. [After TestFlight](after-testflight.md#consensus-hard-delete). |
| Hard delete and desync quietly | Pushed out | Ruled 2026-09-14. The harder of the two to explain honestly — the app would knowingly let a conversation diverge with no repair. [After TestFlight](after-testflight.md#hard-delete-and-desync-quietly). |

</details>

<details markdown="1">
<summary><b>What you can send</b> · 18 tickets — 14 tested · 4 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Text, with formatting | Complete (tested) | Markers covered by the suite. The entries that carry them proved over real cloudkit 2026-09-14; the markers themselves are drawn on the reading device and never cross, so there is nothing further for two accounts to show. |
| Photos | Complete (tested) | 770 KB up, same bytes down, drawn on the other account: 2026-09-04. |
| Clips | Complete (tested) | Re-encoded, sent, screened as a file, played on the other account: 2026-09-04. |
| Captions | Complete (tested) | "Ice plants in bloom" under the photo on the other account: 2026-09-04. |
| Trimming a long clip | Complete (hardware proof owed) | The system trimmer refuses every file on a simulator — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| On-device screening and the blur | Complete (hardware proof owed) | The analyzer ran on the rig and judged clear; `notScreened` and `clear` are both proved. A positive verdict needs Apple's test profile on a device — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| The deny list | Complete (tested) | `BlockingTests`. A listed sender is shut out the same way a blocked one is since 2026-09-14 — not answered rather than not drawn — and the switch plus a round restores them with nothing lost. |
| Reactions on messages | Complete (tested) | Two-circle stack on the receiving account 2026-09-04. |
| Scale and crop a picked avatar | Complete (tested) | A crop step before anything is saved, on all three pickers (`AvatarCropTests`, mutation-checked). Verified on alpha against a picture with its subject hard off to one side. |
| An Outpost inherits your face | Complete (tested) | A member's own wall draws their own avatar, with two controls to override it there and nowhere else (`AvatarPrecedenceTests`, `OutpostPhotoSharingTests`). Proved over real CloudKit 2026-09-14: a wall's own face crossed and the reader fetched the same bytes (`LiveOutpostTests`). |
| Photos on an Outpost | Complete (tested) | Up to four photos or clips as one post, with the words as the caption (`OutpostPhotoTests`). Proved over real CloudKit 2026-09-14: a post with a photo reached a reader and the bytes came back identical — an attachment travels as a CKAsset, a different path from every other proof here (`LiveOutpostTests`). |
| What is new on somebody's wall | Complete (hardware proof owed) | A ring on the rail and a flag in the list, from a device-local mark set when this member was let in (`OutpostUnseenTests`). Proved over real CloudKit 2026-09-14: a post crossed, lit as unseen for the reader, stayed unseen-free for its author and cleared when read (`LiveOutpostTests`). The **banner** for it waits on a push, which is hardware — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Editing and deleting your own posts | Complete (tested) | The fold always could; the session, the read model and the menus now say so (`OutpostEditingTests`). Proved over real CloudKit 2026-09-14: an edit and a withdrawal both reached the reader, for posts and for messages (`LiveOutpostTests`, `LiveRoundTests`). A photo post is deliberately not editable — the fold refuses it. |
| Storage and retention | Complete (tested) | The number is on the You screen since 2026-09-05, read from `FileMediaStore.byteCount()`, and **nothing being deleted on its own is the answer rather than a gap** (ruled 2026-09-13). The date-based clear went to [After TestFlight](after-testflight.md#clearing-media-older-than-a-date) on 2026-09-14, which is the whole of what was outstanding. |
| Search | Complete (tested) | A search tab with sectioned results over conversations, message text, photos and posts. `SearchTests`: twelve tests over what it finds and what it refuses — withdrawn, hidden, blocked — the ordering and the tiebreak. Search reads the local replica, and the entries it reads proved over real cloudkit 2026-09-14. |
| A searchable emoji picker | Complete (tested) | Built 2026-09-15. `Scripts/make-emoji-table.py` turns Unicode's `emoji-test.txt` into a 1,914-emoji resource in nine groups. Searchable by name, whole-word matches first. Walked on the rig 2026-09-16 with the software keyboard: it was a popover and its field went under the navigation bar when the keyboard rose, so a phone now gets a sheet with detents and a wide screen a popover — [why the documented default was not trusted](epics/content-and-composer.md#the-system-emoji-picker). Named limit: the names are English only. |
| Blocking reaches posts, not only messages | Complete (tested) | `block` set a local preference that only `messages(in:)` consulted, so a blocked person stayed on the Outposts tab, in search and in the badge. `feed()`, `outpostAuthors()`, `comments(on:)` and `outpostAuthorsWithUnseen()` all filter now, and since 2026-09-14 so do `peers()`, both rewrap paths, the media upload, the bell and `outpostReaders()`. |
| The disabled affordances | Complete (hardware proof owed) | Every drawn control does something. *Create the invite* waits for a parseable code, compose-from-feed works, emoji in room names and local nicknames were built (2026-09-14, 2026-09-06). Camera scanning, 2026-09-16: a Scan button beside Paste, asked about first in the app's words and kept apart from the camera prompt so the HIG's pre-alert rules hold, with a setting in Privacy & Safety. **The scanner itself has not run** — a simulator has no camera; a phone must scan a real invite. |

</details>

<details markdown="1">
<summary><b>Groundwork</b> · 13 tickets — 10 tested · 1 hardware proof owed · 1 operational proof owed · 1 incomplete</summary>

| Ticket | Status | Evidence |
|---|---|---|
| The contrast finding, and the test that missed it | Complete (tested) | Seven accents, both appearances, pinned by tests 2026-08-18. |
| Haptics, bounded to three cues | Complete (tested) | `HapticCueTests`. |
| Asking for photos honestly | Complete (tested) | Explainer, then the system picker's own Private Access banner: 2026-09-04. |
| Trust and safety in the app | Complete (operational proof owed) | Report, block, filter, contact and EULA findable. The mailboxes exist; the report vault does not, and mail to `abuse@` with an attachment is not yet refused — [Before TestFlight](pre-testflight.md#operational). |
| Tab roots on system navigation bars | Complete (tested) | The bars are the system's and the wash is audited at all seven accents in both appearances. Rooms and Outposts are inline-titled. **You carries no title at all** — the mark stands where one would be, ruled a deliberate departure 2026-09-14 with its cost written down in [Decisions](decisions.md#the-mark-stands-where-yous-title-would-be-and-that-is-a-departure). This row claimed *You is large* until the code was read. |
| An accessibility pass | Complete (hardware proof owed) | Targets, Dynamic Type and contrast done, the last with a sixteen-test audit — **true of the palette and of the screens' own text, and not true of the transcript's system lines**, where Apple's audit still reports fifteen Dynamic Type and five contrast findings; parked with the reason in [Inbox](inbox.md#accessibility). 2026-09-16: labels, Reduce Motion and color-only state audited in source and clean, with one defect fixed — a message somebody else edited told VoiceOver an empty string (`DeliveryMarkSpeaksTests`). The Dynamic Type pass walked every screen at the largest size; what stays fixed is recorded. Apple's audit extended to Appearance, Color, Privacy & Safety, Join a room and a room's sheets. **This row said VoiceOver "was right on the first stop of every screen tried", and the walk of 2026-09-17 disproved it** — on the two screens of the Supporter claim flow the first stop was the dismiss control, so a member was never told they had become a Supporter or what the badge question was asking. Walked as far as a script can: the arrival announcement on the Supporter flow and the privacy screens, read off VoiceOver's own caption panel. Three defects, all fixed and re-measured — two screens announcing chrome instead of their headline, two announcing a headline with no heading trait, the last now failed over by `Scripts/lint/screen-headings.py`. What a script cannot do was measured the same day: injected flicks, touch paths and synthesized keystrokes all fail to move VoiceOver's cursor, so reading **order**, grouping and the rotor are still unheard. **That half waits for TestFlight** — Griff ruled 2026-09-17 — and is done on a phone. |
| A test seam that cannot lie | Complete (tested) | The in-memory mailbox goes through the wire mapping, counts every server operation, holds the record ceiling and refuses a photo to a tag it was not sent to; the in-memory log encodes each entry; the sibling relay holds `Data`. Six tests hold the fakes to those contracts (`TheFakeIsNoEasierTests`). The one gap the fakes cannot have an opinion about — **order** — is pinned on the real server now, twice: at the mailbox and across a twenty-four-entry round. |
| Before TestFlight | Incomplete | The language pass is done 2026-09-05, the debug leaves are out of a release build, the dark-and-light sweep is done except the surfaces that need a push or a phone, the deprecation warnings are all fixed and `ITSAppUsesNonExemptEncryption` is set, 2026-09-17. Left: the hardware proofs, both suites and a rig walk on an iOS 27 runtime, and the operational list — the report vault, refusing attachments at `abuse@`, publishing the source under its license (the license exists), and App Store Connect. The mailboxes exist. The marketing site was rewritten against the build on 2026-09-17: its screens are screenshots of the app now rather than a retired design export, and every page's copy was checked against the code. |
| A CloudKit integration target | Complete (tested) | The seam driven against a real account, and since 2026-09-14 the whole round above it. Nine tests on the mailbox — the wire round trip, every scanned field, the change feed, acknowledgment, a photo's bytes, the order records come back in, and the record ceiling in both directions — plus thirteen on rounds, the sibling feed and the Outpost (`LiveRoundTests`, `LiveSiblingFeedTests`, `LiveOutpostTests`). The unlock was that a packet is addressed by `RecipientTag` and never by an account, so two whole sessions in one account prove a round. |
| The help the welcome tour promises | Complete (tested) | Broken on iPhone until 2026-09-15, and broken the same way twice. *Help on every screen* first wrote a preference nothing read; that was fixed — on the desktop path. The **iPhone tab** built its own `YouView` and left `tutorialMode:` off the argument list entirely, so it took the `.constant(false)` default: the switch moved, wrote nothing, and no `?` ever appeared on the only platform this app ships on. Found by walking the rig. There is one `youScreen` now, used by both platforms, so the two argument lists cannot drift again — which also restored three settings the *desktop* was missing. Four tests in `HelpOnEveryScreenTests`, and the `?` was seen opening *How this works*. |
| Light mode, from rules rather than drawings | Complete (tested) | Every swatch carries a real light value and the contrast audit covers both appearances. The sweep of surfaces the system draws was done 2026-09-15. 2026-09-17: every color a view picks for itself was measured in both appearances, with Increase Contrast on and off, for every accent — the destructive red, Increase Contrast fills, unlit marks, four filled buttons, accent words on cards, the anonymous face and white words on glass over photos were all fixed, seven audit tests added, and what stays is in [Decisions](decisions.md#a-color-is-measured-on-every-ground-it-is-drawn-on-in-both-appearances). |
| Transitions | Complete (tested) | Sheet, tab switch and navigation push use the system's motion, by decision. The accent retint is one 0.2s cross-fade; recorded frame by frame 2026-09-16, the system tab bar changes about 85ms ahead of the app's own surfaces, and Griff ruled the same day to keep the fade. |
| The crypto, written down | Complete (tested) | Written 2026-09-15: [The crypto, written down](crypto-brief.md), from the twelve files rather than from the architecture doc. Covers every construction twice — plain and technical — with the threat model, what the relay is handed, and what is out of scope. Found one thing that needs a ruling (the six-character phrase is ~29.4 bits with **no commitment step**, so one side of a MITM can grind it offline in hours — **ruled 2026-09-15**: ten characters *and* a commitment, see [Decisions](decisions.md#the-verification-phrase-gets-ten-characters-and-a-commitment)), three trade-offs accepted with reasons and two small things parked, all in [Decisions](decisions.md#what-the-crypto-brief-found). The app now states the limit too: *Who has checked this* on the How it works screen. The outside review was canceled 2026-09-14. |

</details>

## Next up

Taken from the table rather than from what was last touched, 2026-09-17.

1. **The marketing site**, rewritten against the build, with a roadmap page and a page for Bullet
   ([Before TestFlight](pre-testflight.md#the-marketing-site)).
2. **Before a build goes out** — the report vault, refusing attachments at `abuse@`, publishing the
   source, and App Store Connect ([Before TestFlight](pre-testflight.md#operational)).
3. **A phone on iOS 27**, and a second phone on the same account, for the tickets owed a hardware
   proof, both suites, a walk, and the VoiceOver pass.

## The epics

| Epic | What it covers |
|---|---|
| [Getting a message there](epics/messaging.md) | Messages, marks, solos, repair. Getting a message from one person to another and saying honestly how far it got. |
| [Telling someone it arrived](epics/notifications.md) | The bell, previews, unread, badges, settings, tapping through. |
| [Who is in a room](epics/rooms-and-membership.md) | Setup, removal, leaving, blocking, reporting, Outpost access, verification. |
| [Your identity across your devices](epics/identity-and-devices.md) | The Keychain hand-off, erase, recovery, the lock. |
| [Taking things back](epics/data-etiquette.md) | Hiding, editing, withdrawing, consensus deletion. Refusal is unilateral; removal from somebody else never is. |
| [What you can send](epics/content-and-composer.md) | Text, photos, clips, reactions, screening, search. |
| [Groundwork](epics/foundations.md) | Accessibility, the test seam, an outside review of the crypto, and shipping. |
