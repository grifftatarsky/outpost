---
title: Roadmap
layout: default
nav_order: 7
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
| **Complete (hardware proof owed)** | Built and proved as far as a simulator goes. What is left needs a phone, and is named on [Still to prove](roadmap.md#still-to-prove). Nothing on this list is waiting on a decision or a keystroke at this desk. |
| **Complete (operational proof owed)** | Built, and waiting on something outside the app existing — a live mailbox, a vault. Also on [Still to prove](roadmap.md#still-to-prove). |
| **Incomplete** | Some acceptance criteria are met and some are not. |
| **Not started** | Nothing built beyond what the log format already allows. |
| **Pushed out** / **Canceled** | Decided against for now, or for good, with the reason under [What came off, and why](#what-came-off-and-why). |

A green suite has been wrong about CloudKit more than once here, which is why "tested" means the
real transport rather than a passing run.

**The bar for "a rig cannot do it" moved on 2026-09-14**, and it moved a long way. A packet is
addressed by a `RecipientTag` and never by an Apple Account, so two whole `AppSession`s sharing one
zone in **one** account prove an entire round over real CloudKit. Thirteen rows that said *unproven
on two accounts* were proved that way in an afternoon. Before anything is called un-runnable, that
trick has to have been tried.

Every area is here: the iPhone, the iPad and the Mac, what is pushed out, and what is still to prove.
The epic pages carry the long form: the story, the acceptance criteria, what was observed and when,
and the test plan. [Open questions](open-questions.md) holds what is unbuilt or uncertain.
[Inbox](inbox.md) holds what was noticed and parked.

## Where everything stands

Eight epics, 104 tickets, counted 2026-09-20.

| Status | Count |
|---|---|
| Complete (tested) | 67 |
| Complete (proved above the mailbox) | 6 |
| Complete (QA required) | 5 |
| Complete (hardware proof owed) | 17 |
| Complete (operational proof owed) | 3 |
| Incomplete | 2 |
| Not started | 1 |
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
<summary><b>Telling someone it arrived</b> · 11 tickets — 7 hardware proof owed · 4 tested</summary>

| Ticket | Status | Evidence |
|---|---|---|
| A bell that rings for a message and nothing else | Complete (hardware proof owed) | The bell is written, subscribed to and **rung**: alpha logged `mailbox: rang a peer's bell` on 2026-09-14 with beta backgrounded, and **no push reached the app over five minutes** — measured, not inferred. Everything up to delivery is proved; delivery is on [Still to prove](#still-to-prove). |
| Notification previews | Complete (hardware proof owed) | Four rungs, per room, driven on the rig. The extension's banner needs a push to draw it — [Still to prove](#still-to-prove). |
| Unread, and the number on the icon | Complete (tested) | Dot and badge on beta 2026-09-02, cleared by reading. The extension's half rides on the push. **2026-09-17: the number ignored the member's own switches** — `BadgeCount` counted unread rooms unconditionally, never read `BadgeChoices` and never counted Outposts, so two controls on the Notifications screen did nothing and all four sentences of `BadgeMeaningLine` were false. Fixed, and it is one `AppSession.badgeNumber` the app and the extension share rather than a sum written twice ([Decisions](decisions.md#the-number-on-the-app-icon-is-one-property-and-it-obeys-the-switches)). Measured on Quad: 1 with an unread room, none once the switch was off with the message still unread, and back again. |
| Asking for notifications honestly | Complete (tested) | Explainer on the first ready screen on both simulators 2026-09-04. |
| Tapping through, and what happens next | Complete (hardware proof owed) | A banner for a room this member no longer has opens the app and navigates nowhere; one tapped while already in that room does nothing. The decision sits in `AppSession.tapping(_:whileViewing:)` so it is testable (`TappingThroughTests`). Watching a real banner be tapped is on [Still to prove](#still-to-prove). |
| A banner from a person | Complete (hardware proof owed) | The extension attaches the sender, their photo and the conversation to every banner that names them, and since 2026-09-13 a banner about a post prefers the picture on the wall it came from (`ABannersFaceTests`). Seeing one drawn is on [Still to prove](#still-to-prove). |
| Silenced notifications, shared | Complete (tested) | Two switches and a custom message (`FocusStatusTests`). Beta's pretend Focus drew *Do Not Disturb*, then *Heads down till six*, over alpha's field 2026-09-06. |
| Focus filters | Complete (hardware proof owed) | A filter per Focus: which rooms may notify, whether banners carry the words (`FocusFilterTests`). 2026-09-17, found while making the extension's decisions testable: *Show what was said* was applied to a message and not to a post, so a Focus set to hide it still put a post's body on the lock screen. Fixed — the preview switch reaches a post, the room list deliberately does not ([Decisions](decisions.md#a-focus-filters-preview-switch-reaches-a-post-and-its-room-list-does-not)). A simulator has no Focus — [Still to prove](#still-to-prove). |
| Settings split by what rings | Complete (hardware proof owed) | Notifications is a master switch over two pages, Messaging and Outposts, each with its own urgency; badges carry a separate setting saying what they count. `NotificationLevelTests`, `BadgeCountTests`, `WhatTheTabsBadgeTests`, driven on the rig 2026-09-11. Seeing one with a real push is on [Still to prove](#still-to-prove). |
| Asking for Outpost notifications | Complete (tested) | A step in onboarding, and a gear on an Outpost's own page for one wall at a time. Walked end to end on two Apple Accounts 2026-09-15: beta allowed alpha in from the room banner — behind an alert that says plainly it cannot be undone — beta posted, the post crossed, Outie appeared on alpha's rail, and the gear on that wall carried *Get notifications for this Outpost* with the honest footer that the other person is not told. Turned on and it held. |
| Answering from the notification | Complete (hardware proof owed) | Reply and Mark as Read on a message banner, through the composer's send path (`NotificationAnswerTests`). Proved above the mailbox on gamma and delta 2026-09-19, warm and cold, after two faults the rig found: a reply dropped because a cold launch's window answered before the session had loaded, and a reply left unsent because the app was suspended while a round was flagged to go again. Then on alpha and beta, two Apple Accounts over CloudKit, the same day: a warm reply, a cold reply and Mark as Read. The extension attaching the actions to a real push is phone-only — [epic](epics/notifications.md#answering-from-the-notification). |

</details>

<details markdown="1">
<summary><b>Who is in a room</b> · 23 tickets — 15 tested · 4 proved above the mailbox · 2 operational proof owed · 2 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Setting up a room | Complete (tested) | Creation sheet, policies, people picker, the invitee's sheet: 2026-09-01 and 02. |
| Removing somebody | Complete (tested) | Removed member could not read the next epoch: 2026-09-02. Two-member case only. |
| Leaving properly | Complete (tested) | Beta left, both drew it, alpha turned the key: 2026-09-02. |
| Blocking a person | Complete (tested) | Local silent block built 2026-09-04; the key handover built 2026-09-14 against six tests. A blocked person is not a peer, so nothing of theirs is collected or acknowledged and their app stops being told *collected* — which is the signal the convention runs on — they are handed no future room keys, no media and no bell, and they are dropped from the Outpost audience. Nothing said while they were blocked is lost. The epoch turn this was first specified with was dropped on building it: in a group every other member re-grants the key anyway. |
| Reporting a message | Complete (operational proof owed) | Sheet seen on the rig 2026-09-04 and its copy checked. The addresses exist and receive mail (Griff, 2026-09-17); a send from a phone has not been watched, and the vault a filed report goes into does not exist yet — [Still to prove](#still-to-prove) and [Before a build goes out](epics/foundations.md#operational). |
| Per-person Outpost access | Complete (tested) | The wall is sealed to the people let in, two offers enforced by which epoch links a grant carries, the room's review, the allow-list and the reciprocal card. Driven on two accounts three times, 2026-09-07. |
| The one stranger | Complete (proved above the mailbox) | A comment seals under the wall it lands on, so everybody unmet is one shared figure. Nine tests, four mutation-proven. Three devices, 2026-09-09: the same comment drew as *Quad* to somebody sharing a room and as *User 403* to somebody sharing nothing. |
| Open or closed on other people's Outposts | Complete (proved above the mailbox) | Three answers plus off, asked in the check-up after both doors and changeable in Outpost settings. Closed seals a comment under the writer's own wall and carries a second copy for the post's author, so it never refuses. Sixteen tests, six mutation-proven. Three devices, 2026-09-09: the owner read both closed comments; the co-reader read *2 comments are not shown*. |
| A confirmation answers one invitation | Complete (tested) | Keyed by the invitation rather than the person, so somebody asked back after a removal reads the six characters again. The room's own half was closed 2026-09-14: `RoomRoster` keys admissions and refusals on the invitation too, so a vote cast for a superseded offer no longer admits somebody to the live one — pinned by `MembershipTests` and `JoinIsARoundTripTests`. |
| Invitations that are never accepted | Complete (operational proof owed) | The expiry is enforced at the inviter's relay as well as on the device holding the link and never in the fold; the two lists split on whether the offer was taken; taking one back is open to any member in good standing; a date you pick has a control. The relay gate wants an inviter who stays offline past the date, which is a clock the rig cannot move — [Still to prove](#still-to-prove). |
| Who may agree to an invitation | Complete (tested) | Built 2026-09-19 on Griff's ruling. A named approver is a list, any one of whom is enough, and a rule written by an older build still decodes. Under *any member*, *a set number* and *unanimous* the person who sent the invitation is not one of the people who may agree to it — unless there is nobody else to ask. `WhoMayApproveTests`, and six older tests rewritten rather than deleted. |
| Joining a room from today, not from the beginning | Complete (proved above the mailbox) | Built 2026-09-19 on Griff's ruling. The invitation carries `sharesHistory`, signed; the inviter turns the key when the joiner is established, records the floor on the admission and restates the room so the newcomer can see who is in it; every member withholds keys until that floor exists, and grants then carry only the links above it. `JoiningFromTodayTests` — before stays sealed, after arrives, full history unchanged, and an older invitation still verifies. Not yet run on the rig. |
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
| The removal audit's open cases | Complete (tested) | 2026-09-16: `RemovalSurvivesACrashTests` cuts a removal off at both of its halves and relaunches. Before the fix, both left the key unturned **and the removed member read what was said next**. A removal now records the key turn it owes before it writes, the way an Outpost revocation already did, and every round retries it. The two three-party cases are in [Still to prove](#still-to-prove). |

</details>

<details markdown="1">
<summary><b>Your identity across your devices</b> · 12 tickets — 8 tested · 2 hardware proof owed · 1 canceled · 1 proved above the mailbox</summary>

| Ticket | Status | Evidence |
|---|---|---|
| The sibling feed is sealed before it is written | Complete (tested) | Found and fixed 2026-09-13: the record had carried every epoch secret the member held, in the clear, since 2026-08-16. `SiblingFeedIsSealedTests`, mutation-proven. Proved over real CloudKit 2026-09-14: the raw CKRecord was fetched back off the server and the epoch secret is not in it, the payload is exactly the ciphertext, the member's identity reopens it and a stranger's is refused — and a second device was handed it and opened it (`LiveSiblingFeedTests`). The iCloud Keychain hand-off that makes two *real* devices one member is hardware-only. |
| One identity across a member's devices | Complete (hardware proof owed) | Keychain hand-off, device list, revocation, the checking screen: built. The sibling feed's wire and its delivery between two device identifiers were proved over real CloudKit 2026-09-14; the iCloud Keychain hand-off that makes two *real* devices one member cannot happen on a simulator — [Still to prove](#still-to-prove). |
| Erase everything | Complete (tested) | Run from the sheet on alpha, 2026-09-15, which is what this row was waiting for. The sheet lists what is erased and — the half that matters — what is **not**: nothing leaves anybody else's device, rooms are not told, and nobody can restore it. A confirmation dialog then says the same in one sentence. The wipe ran, and the app came back to onboarding on a genuinely empty account. |
| Recovery settings, and telling people a restore asked them | Complete (tested) | Ruled 2026-09-13 and built the same day, against 24 tests. The recoverer chooses whether to ask peers at all; the person asked is always told, and can hold it behind a solo check. This row read "None of it built" until 2026-09-14, when the code was read — and writing a live test that day found the notice **defaulted to off**, with the friendly preset turning it off explicitly, so the members least likely to go looking were the ones not told. Fixed and pinned. The quiet restore — asking nobody, telling nobody, coming back to empty rooms — is proved over real CloudKit (`LiveRecoveryTests`). |
| Recovery from a lost device | Complete (tested) | *I have a recovery key* on the welcome screen **and on the stalled screen a new phone on an occupied account actually lands on** — it was reachable only from onboarding until 2026-09-13, which put it out of reach in the one case it exists for. The key is read on the device, the identity goes back in the keychain, a fresh device key is minted. Run end to end on two accounts 2026-09-13: export, restore, the room and its history back, and the peer's entries back after the restored device raises its own repair. What the rig found and the suite had not: a peer never re-offers an entry it has already spent, so a restored device has to raise its own repair (`askEverybodyForWhatWasSaid`) — without it `entriesReceived` was 0 on every round while the peer wrote `unsent=0`, and the peer's messages and even their display name never came back. With it, the room, both members' messages and the names all return. `RestoringFromAKeyTests` covers the round trip, the new device key, the sibling-device path, the peer path (mutation-proven), a device that already has a member, and each of the four ways a key can be wrong. |
| An in-app lock | Canceled | Ruled 2026-09-14. iOS locks apps behind Face ID already and enforces it better than the app could. [below](#an-in-app-lock). |
| The device list tells the truth | Complete (hardware proof owed) | Every device used to self-certify at `.distantPast`, so *here since you made this identity* was true of the founding device and claimed by every later one — and a relaunch re-issued the certificate, making *added* really mean *last launched*. Both fixed 2026-09-13, with a third found on the way: on a fresh install the device a member is holding read *never been used*. A fourth was found on the rig the same day, once eight devices had accumulated: a device that had spoken plenty read *added, but it has never been used — setup may not have finished*, because `hasSpoken` is computed from the entries **this** device holds and a restored device holds few. That is an inference from absent evidence, which this app does not make about anything else; it now says what it knows — *nothing it sent has reached this device* — beside the real date. Each device also carries a **name** now — from its hardware identifier on first launch, renameable, private to the member because preferences ride the sealed sibling feed. `TheDeviceListTellsTheTruthTests`, `NamingYourDevicesTests`. A device that has written nothing now reaches its sibling's list and can be revoked, 2026-09-16 (`aSilentSiblingReachesTheList`; unproven across CloudKit). The one-identity-per-account policy is decided and enforced: an occupied account stops, and since 2026-09-16 one that cannot be reached waits (`ExistingRegistrationTests`). |
| Names and faces shared by choice | Complete (tested) | Names and photos both ways, off by default (`SharingTests`, `PhotoSharingTests`). Beta's photo collected on alpha and taken down again 2026-09-06. |
| A privacy check-up at first run | Complete (tested) | Three doors after the name, with examples (`PrivacyCheckupTests`). Both the preset and the walkthrough seen on the rig 2026-09-06. |
| A name and a face of your own for somebody | Complete (tested) | Nickname on the sibling feed, photo on this device, a People page under the identity row (`NicknameTests`). Seen on the rig 2026-09-06. |
| The Supporter badge is two switches | Complete (tested) | Built 2026-09-19 on Griff's ruling: one switch draws the mark on your own picture, a separate one announces it to your rooms and Outposts. The question a new Supporter is asked still sets both, and a state file written before the split keeps its meaning. Walked on alpha — shown on, shared off, the preference written both ways (`SupporterBadgeTests`). |
| Supporter: the TestFlight year and the badge | Complete (proved above the mailbox) | Built 2026-09-17: the bar, the thank-you page, the badge question, the Supporter page and the badge on avatars (`SupporterStandingTests`, `SupporterBadgeTests`). The whole flow on gamma, and gamma's badge drawn on delta, over the directory mailbox. Re-run on gamma 2026-09-17 against the current build, both paths: the bar, the thank-you page, the badge question, the badge on the You row and the Supporter page; and the decline path, which leaves the bar gone, the year kept and the pencil where it was. That run **found the check was not repeatable** — it had claimed the year on a previous run and could never pass again, which is a check that silently stops checking. `--forget-supporter` clears the three preference fields on launch, in `#if DEBUG` and on the release-leaves list, and both tests now take it. Not yet seen on a TestFlight build, and the App Store purchase is not built. |

</details>

<details markdown="1">
<summary><b>Taking things back</b> · 5 tickets — 2 tested · 2 pushed out · 1 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Editing and withdrawing your own words | Complete (tested) | Edit and withdrawal reached the other account 2026-09-02. |
| Hiding follows the member, not the device | Complete (hardware proof owed) | Built 2026-08-18 with tests; the flags ride `MemberPreferences` on the sibling feed and merge by stamp. The feed itself crosses real CloudKit; hiding on one real device and seeing it hidden on another needs the keychain hand-off — [Still to prove](#still-to-prove). |
| Hiding, as the set draws it | Complete (tested) | Two of four criteria were already built and unmarked — search exclusion and reaching the member's own devices — both found by reading the code 2026-09-14. The other two were built and walked on the rig the same day: the confirmation quotes the message and states the scope before the buttons, and the transcript says *1 hidden by you. Nobody else is affected.* at its foot, which shows them again when tapped. |
| Consensus hard delete | Pushed out | Ruled 2026-09-14. Unblocked and unbuilt; the most protocol-heavy unbuilt feature here, and nothing shipped claims it. [below](#consensus-hard-delete). |
| Hard delete and desync quietly | Pushed out | Ruled 2026-09-14. The harder of the two to explain honestly — the app would knowingly let a conversation diverge with no repair. [below](#hard-delete-and-desync-quietly). |

</details>

<details markdown="1">
<summary><b>What you can send</b> · 19 tickets — 15 tested · 4 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Text, with formatting | Complete (tested) | Markers covered by the suite. The entries that carry them proved over real cloudkit 2026-09-14; the markers themselves are drawn on the reading device and never cross, so there is nothing further for two accounts to show. |
| Photos | Complete (tested) | 770 KB up, same bytes down, drawn on the other account: 2026-09-04. |
| Clips | Complete (tested) | Re-encoded, sent, screened as a file, played on the other account: 2026-09-04. |
| Captions | Complete (tested) | "Ice plants in bloom" under the photo on the other account: 2026-09-04. |
| Trimming a long clip | Complete (hardware proof owed) | The system trimmer refuses every file on a simulator — [Still to prove](#still-to-prove). |
| On-device screening and the blur | Complete (hardware proof owed) | The analyzer ran on the rig and judged clear; `notScreened` and `clear` are both proved. A positive verdict needs Apple's test profile on a device — [Still to prove](#still-to-prove). |
| The bundled list locks the app for a member on it | Complete (tested) | Built 2026-09-19 on Griff's instruction. A member whose own fingerprint is on the bundled list gets one red screen and nothing else: the mark in white, the sentence, and a button to the contact form's *A mistaken ban*. It is checked at launch and again when an identity comes back from a recovery key, and it holds whether or not the member turned the list off. No round runs while it holds, so nothing more is sent or collected (`BannedFromTheAppTests`, `RootDecisionsTests`). Drawn on alpha 2026-09-19 with the check forced, and the button watched opening the form. |
| The deny list | Complete (tested) | `BlockingTests`. A listed sender is shut out the same way a blocked one is since 2026-09-14 — not answered rather than not drawn — and the switch plus a round restores them with nothing lost. |
| Reactions on messages | Complete (tested) | Two-circle stack on the receiving account 2026-09-04. |
| Scale and crop a picked avatar | Complete (tested) | A crop step before anything is saved, on all three pickers (`AvatarCropTests`, mutation-checked). Verified on alpha against a picture with its subject hard off to one side. |
| An Outpost inherits your face | Complete (tested) | A member's own wall draws their own avatar, with two controls to override it there and nowhere else (`AvatarPrecedenceTests`, `OutpostPhotoSharingTests`). Proved over real CloudKit 2026-09-14: a wall's own face crossed and the reader fetched the same bytes (`LiveOutpostTests`). |
| Photos on an Outpost | Complete (tested) | Up to four photos or clips as one post, with the words as the caption (`OutpostPhotoTests`). Proved over real CloudKit 2026-09-14: a post with a photo reached a reader and the bytes came back identical — an attachment travels as a CKAsset, a different path from every other proof here (`LiveOutpostTests`). |
| What is new on somebody's wall | Complete (hardware proof owed) | A ring on the rail and a flag in the list, from a device-local mark set when this member was let in (`OutpostUnseenTests`). Proved over real CloudKit 2026-09-14: a post crossed, lit as unseen for the reader, stayed unseen-free for its author and cleared when read (`LiveOutpostTests`). The **banner** for it waits on a push, which is hardware — [Still to prove](#still-to-prove). |
| Editing and deleting your own posts | Complete (tested) | The fold always could; the session, the read model and the menus now say so (`OutpostEditingTests`). Proved over real CloudKit 2026-09-14: an edit and a withdrawal both reached the reader, for posts and for messages (`LiveOutpostTests`, `LiveRoundTests`). A photo post is deliberately not editable — the fold refuses it. |
| Storage and retention | Complete (tested) | The number is on the You screen since 2026-09-05, read from `FileMediaStore.byteCount()`, and **nothing being deleted on its own is the answer rather than a gap** (ruled 2026-09-13). The date-based clear went to [below](#clearing-media-older-than-a-date) on 2026-09-14, which is the whole of what was outstanding. |
| Search | Complete (tested) | A search tab with sectioned results over conversations, message text, photos and posts. `SearchTests`: twelve tests over what it finds and what it refuses — withdrawn, hidden, blocked — the ordering and the tiebreak. Search reads the local replica, and the entries it reads proved over real cloudkit 2026-09-14. |
| A searchable emoji picker | Complete (tested) | Built 2026-09-15. `Scripts/make-emoji-table.py` turns Unicode's `emoji-test.txt` into a 1,914-emoji resource in nine groups. Searchable by name, whole-word matches first. Walked on the rig 2026-09-16 with the software keyboard: it was a popover and its field went under the navigation bar when the keyboard rose, so a phone now gets a sheet with detents and a wide screen a popover — [why the documented default was not trusted](epics/content-and-composer.md#the-system-emoji-picker). Named limit: the names are English only. |
| Blocking reaches posts, not only messages | Complete (tested) | `block` set a local preference that only `messages(in:)` consulted, so a blocked person stayed on the Outposts tab, in search and in the badge. `feed()`, `outpostAuthors()`, `comments(on:)` and `outpostAuthorsWithUnseen()` all filter now, and since 2026-09-14 so do `peers()`, both rewrap paths, the media upload, the bell and `outpostReaders()`. |
| The disabled affordances | Complete (hardware proof owed) | Every drawn control does something. *Create the invite* waits for a parseable code, compose-from-feed works, emoji in room names and local nicknames were built (2026-09-14, 2026-09-06). Camera scanning, 2026-09-16: a Scan button beside Paste, asked about first in the app's words and kept apart from the camera prompt so the HIG's pre-alert rules hold, with a setting in Privacy & Safety. **The scanner itself has not run** — a simulator has no camera; a phone must scan a real invite. |

</details>

<details markdown="1">
<summary><b>Groundwork</b> · 13 tickets — 10 tested · 1 operational proof owed · 1 hardware proof owed · 1 incomplete</summary>

| Ticket | Status | Evidence |
|---|---|---|
| The contrast finding, and the test that missed it | Complete (tested) | Seven accents, both appearances, pinned by tests 2026-08-18. |
| Haptics, bounded to three cues | Complete (tested) | `HapticCueTests`. |
| Asking for photos honestly | Complete (tested) | Explainer, then the system picker's own Private Access banner: 2026-09-04. |
| Trust and safety in the app | Complete (operational proof owed) | Report, block, filter, contact and EULA findable. The mailboxes exist; the report vault does not, and mail to `abuse@` with an attachment is not yet refused — [Before a build goes out](epics/foundations.md#operational). |
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
   ([Before a build goes out](epics/foundations.md#the-marketing-site)).
2. **Before a build goes out** — the report vault, refusing attachments at `abuse@`, publishing the
   source, and App Store Connect ([Before a build goes out](epics/foundations.md#operational)).
3. **A phone on iOS 27**, and a second phone on the same account, for the tickets owed a hardware
   proof, both suites, a walk, and the VoiceOver pass.

## The desktop

The Mac **runs**: a window, three columns, a folding sidebar, and a keychain that behaves like iOS's
rather than the legacy file-based one — without that last part a Mac and an iPhone carried two
different identities while claiming to be one member. It keeps working because Griff uses it. It is
not offered, described or supported, and no member has ever been shown it.

The iPad at full width uses the Mac's layout, in both orientations, walked on a simulator by
`WideLayoutTests` — [Decisions](decisions.md#the-mac-and-an-ipad-at-full-width-share-one-layout-areas-a-list-and-what-is-open).
It has not been drawn by a designer; the implementation decided it.

### Desktop tickets

| Ticket | Status | Evidence |
|---|---|---|
| The Mac window feels like a Mac app | Incomplete | Runs in three columns; invite control restored 2026-09-01. **The Mac stopped compiling the day `HardwareName` arrived** — an unconditional `import UIKit` — and builds again as of 2026-09-18. Return and Shift-Return, the flicker, the new-post sheet and the keyboard path all need measuring in a live window: see below. |
| The app icon on macOS | Complete (QA required) | Not yet seen in the Dock. An Icon Composer document with a dark appearance, scoped to the macOS SDK; checked in the compiled `.icns` at every size. The full mark does not read at 16 points. [Decisions](decisions.md#the-mac-icon-is-an-icon-composer-document-and-ios-keeps-its-own). |
| The desktop wall | Complete (QA required) | Not yet seen in a window. An inspector beside your own Outpost holding *Who sees your Outpost*, open by default, hidden with ⌥⌘I. [Decisions](decisions.md#the-desktop-wall-is-an-inspector-open-by-default-and-hideable). |
| A Settings window | Complete (QA required) | Panes drawn offscreen, the real window not yet opened. ⌘, opens a Settings window with a toolbar of panes — Appearance, Behavior, Notifications, Privacy & Safety, Outposts, Devices, Data — holding the same pages the iPhone pushes from You. You on the Mac keeps your name, People, Supporter, your Outpost, help, and a *Settings* row. [Decisions](decisions.md#the-mac-has-a-settings-window-built-from-the-same-pages). |
| What's waiting, in the toolbar | Complete (QA required) | Rendered offscreen, not yet seen live. The filled mailbox; a popover of unread rooms and new Outposts; a count that is the Dock's number and shows only when badges are on. Rendered offscreen at 3, 12 and 99+, unclipped. [Decisions](decisions.md#the-mac-toolbars-mailbox-carries-a-hand-drawn-count-and-only-when-badges-are-on). |
| The wide layout, Mac and iPad | Complete (tested) | Areas, the iPhone's own lists, and what is open, in three columns. The Mac's sidebar had no unread marks, pins, tags, search, waiting invitations or way to start a room; it has all of them now because the list is the iPhone's. [Decisions](decisions.md#the-mac-and-an-ipad-at-full-width-share-one-layout-areas-a-list-and-what-is-open). |
| Paste a photo | Complete (tested) | ⌘V with a copied photo or media file attaches it in the composer and a new post; words paste as before. [Decisions](decisions.md#v-with-a-photo-on-the-clipboard-attaches-it-and-words-still-paste-as-words). Not on an iPad. |
| Drag and drop | Complete (tested) | A photo or clip dragged onto a conversation or a new post is staged as the picker would stage it, and a path a text view inserts is turned back into the file. [Decisions](decisions.md#a-photo-or-clip-dragged-onto-a-conversation-or-a-new-post-is-attached-never-pasted-as-its-path). Not dragged by a real pointer. |
| The menu bar | Complete (QA required) | Structure dumped from a windowless probe; the menus have not been used against a window. File, View, Go and Help carry the app's commands with standard shortcuts, and a compose button in the sidebar starts a room, a solo or joins with an invite — the Mac had no way to do any of the three. [Decisions](decisions.md#the-macs-menu-bar-carries-the-apps-commands). |
| Draw the platforms the set claims | Not started | Design work: two platforms, neither drawn. |

### What needs a person at the Mac

Everything below was left because it can only be settled by looking at a window, and on the night of
2026-09-18 the display was asleep: every window counted as occluded, and SwiftUI draws no scrolling
content into an occluded window, so the sidebar and every list rendered blank. None of it was guessed
at instead.

- **The wide layout on a Mac — seen 2026-09-18**, in a real window on screen in both appearances:
  rooms with a room open, an empty detail, Outposts, your Outpost with the inspector, Search and You.
  It found one defect, now fixed: a sidebar row carrying a badge showed no selection on the Mac.
  Not seen: the window as the key window, so the focused selection color and a keyboard path.
- **The menus against a window.** Their structure was dumped from a windowless probe; with a window
  in front, New Room, the Conversation menu's items, ⌘1 onward and ⌘F should all enable and act.
- **Escape on a sheet — measured.** It leaves *New room* on the Mac, cursor in the field or not.
- **Return and Shift-Return — done 2026-09-18.** Return sends; Shift-Return and Option-Return write a
  line, measured on the real field — [Decisions](decisions.md#shift-return-writes-a-line-on-the-mac).
- **Sheets.** Every sheet goes through `sizedSheet`, which gives it a form size on the Mac: macOS
  sizes a sheet to its content, and a `List`, a `ScrollView` or a `TextEditor` has no natural height.
  Seen on Griff's Mac 2026-09-18 as the notifications explainer arriving as a lone *Continue* bar.
  `Scripts/lint/sheet-sizing.py` fails a bare `.sheet(`. Fixed after that screenshot; not yet seen fixed.
- **Titles.** Three screens printed their title twice on the Mac, once from the window and once from a
  `.principal` item. Fixed; the conversation's member count moved to the window subtitle.
- **The field's border while typing.** An observed behavior, so it needs observing.
- **A full keyboard path** through sidebar, list and detail, with a visible focus ring on every stop.
- **The icon at 16 points.** A design call: a simpler mark for the smallest sizes, or live with it.
- **The Settings window.** Each pane is the system's grouped form, as tall as what it holds up to
  620 points — [Decisions](decisions.md#on-the-mac-a-settings-page-is-the-systems-grouped-form).
  Every pane was drawn offscreen in both appearances; the real window's toolbar, and a page pushed
  inside a pane, were not.
- **The mailbox count on glass**, in light and dark. An offscreen window draws no Liquid Glass.

## What came off, and why

### Pushed out

`RULED` — Griff, 2026-09-14, working through the roadmap ticket by ticket.

#### Consensus hard delete

Asking everybody in a room to destroy a message, and purging it only if all of them agree.

Unblocked and unbuilt. The part every purge needs — recording what was taken out as spent, so the
repair path does not name it and ask for it back — was built on 2026-09-17 for deleting a room, as
`SpentEntry` in `Replica`. It still needs a vote protocol, a push reading exactly **"Consensus reached."**
carrying no identifier, a three-way choice when the vote fails, and a request that hangs for ever
when somebody never answers — ruled 2026-09-13, because both kinds of timed answer put a decision in
somebody's mouth.

**Why it waits.** Nothing in the shipped app claims it, it is the most protocol-heavy unbuilt feature
here, and real use is what should say whether anybody wants it.

**When it is built**, the transient notice after a successful purge is an in-context indicator, not a
toast. iOS has no toast and Apple does not add one: "prefer finding an alternative way to communicate
it within the relevant context. For example, when a server connection is unavailable, Mail displays
an indicator that people can choose to learn more"
([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)).

#### Hard delete and desync quietly

Destroying a message on this device and letting the conversation diverge, with the other party never
told.

**Why it waits.** Same machinery as consensus delete, and it is the harder of the two to explain
honestly: the app would be knowingly letting a conversation diverge with no way to repair it. That
sentence has to be right before the feature exists.

#### Clearing media older than a date

A control that clears media older than a date the member picks, showing what it would free first.

**Why it waits.** Nothing deletes itself on its own — ruled 2026-09-13 as the answer rather than a
gap — and the size is already on the You screen, so a member who wants space can see it and act.
This is convenience on top of an honest baseline.

### Canceled

#### An in-app lock

`RULED` — Griff, 2026-09-14: **canceled.** iOS already locks an app behind Face ID — Settings ›
Face ID & Passcode › Require Face ID for individual apps — so the app would be reimplementing a
thing the system does, and doing it worse: the system's version is enforced before the process is
resumed, covers the app switcher snapshot, and cannot be defeated by the app crashing.

What was asked for and is not being built:

- Locking behind the device's own biometric or passcode, on a timeout the member chooses.
- Notification content respecting the lock and interacting correctly with previews.
- The lock stated as a lock rather than a curtain — the limit spoken rather than protection at rest
  implied.

**What survives the cancellation.** The third point is a copy question, not a lock: wherever the app
talks about what somebody else can see on this phone, it should say that iOS locks apps and that the
app itself does not hold anything back once the phone is open. That belongs in the Safety pages.

**What would reopen it.** A member reporting that the system control is not discoverable enough, or a
case where the app needs to lock something *inside* itself — a single conversation rather than the
whole app — which the system cannot do.

## Later

### Devices to eventually support

Not scheduled, not designed, and not blocking anything. This is the list of things Griff has said he
wants the app to run on one day, kept so that a decision taken now against one of them is taken
knowingly rather than by accident.

| Device | Added | What it would need |
|---|---|---|
| **Mac and iPad** | 2026-09-14 | Has its own page — [the desktop section](roadmap.md#the-desktop) — because the work is sized and sequenced. It builds and runs on a Mac today; that is not the same as being offered. |
| **iPhone Duo** | 2026-09-16 | **Not supported at this time** — Griff, 2026-09-16, while installing iOS 27. **Named by Griff, and this page deliberately does not describe it.** Nobody here has measured what the device is or what it asks of an app, so any sentence about screens, folds or sizes would be a guess dressed as a requirement. When it is real, the first job is to read Apple's guidance for it and write that here — not to infer it from the name. |

**What the app already has that helps.** Every screen is laid out in points with Dynamic Type rather
than in fixed frames, the rig already checks two phone widths (402pt and 440pt), and
`CarpenterUI` has no idea where its data came from — so a new size class is a layout question rather
than an architecture one. What it does **not** have is any notion of two displays, a hinge, or a
window that changes shape while it is open.

### Future enhancements

Named by Griff, recorded in his words, not designed. What the design called *extensions* — first-party
features switched on per room — are **Packs** (Outpost Packs) from 2026-09-16, Griff's rename.

| Enhancement | Added | As Griff put it |
|---|---|---|
| **The Bullet Pack** | 2026-09-16 | "Build bullet extension, lock to subscriber" — and the same night: call it a **Pack**, an **Outpost Pack**, "because that's more fun". It starts with the $0.99 subscribers having Bullet's shared simple list, and anyone who used the app in TestFlight gets one year of subscriber free. Built while the main app is in TestFlight. |
| **Buying Supporter** | 2026-09-17 | "12$ value, since we don't do discounts, it's just annual 12$ and monthly 1$." The TestFlight build grants the free year and the badge instead; the purchase comes with the App Store release. |
| **YubiKey support** | 2026-09-17 | "yubikey support". **Named by Griff, and this page deliberately does not describe it.** Nobody here has read what the platform offers a key over Lightning, USB-C or NFC, or which of the three things it could touch Griff means — holding the identity key off the Keychain, gating the app or a recovery, or being a second factor where this app has no first one to add to. Any sentence about which would be a guess dressed as a requirement. When it is real, the first job is to read Apple's guidance and write that here. |

### Questions for later, not decided

#### Whether a member can be written into Contacts

`RULED` — Griff, 2026-09-15: **"idk how we want to deal with that and def not before release."**
Parked here so the question survives without becoming work.

**What it is about.** Per-*person* Focus breakthrough — the iMessage behavior where a particular
person reaches you through a Focus — needs the sender to be in Contacts, because that is how Apple's
Focus settings name somebody. This app has no contacts relationship at all: `NotificationService`
passes `contactIdentifier: nil` in its `INSendMessageIntent`, necessarily, because there is nothing
to point at.

**What is already true and needs nothing.** A person can allow *the app* through a Focus today —
Apple's own words are "People identify the contacts **and apps** that can break through a Focus" —
and Griff ruled on 2026-09-15 that this is enough for now. What the app should do is *say so*, which
is one sentence on the Notifications screen and is on [the roadmap](roadmap.md).

**What it would cost if it were ever built.** A Contacts permission, for a feature most people will
not use, on an app whose whole proposition is that it holds no directory and knows nobody's details.
Writing a member into Contacts means writing a name this app was told into a store every other app
on the phone can read. That tension is the reason this is a question rather than a ticket.

## Still to prove

Everything here is built and covered by the suite. What is listed is the *proof* that four simulators
on two Apple Accounts cannot run: it needs a third account, a phone, or something outside the app to
exist. Nothing here blocks a build going out.

### Needs a third Apple Account

| Proof                                                                                                                   | Where it stands                                                                                                                                                | What is not yet watched |
|-------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **A comment crosses a triangle over CloudKit** — three identities, an Outpost post, a comment from the third party      | Proved above the mailbox 2026-09-09 on three devices and three identities; proved between **two** real accounts over CloudKit 2026-09-07 with the current seal | A three-party Outpost thread has never run over the real transport. The two-account path is proven, and the third party's seal is the same shape, so the risk is in the addressing rather than the crypto.       |
| **A closed comment crosses a triangle over CloudKit** — the same, where the thread is closed and the count is published | Proved above the mailbox 2026-09-09; proved between two real accounts 2026-09-07                                                                               | The published comment count is the one thing in the app that is not proof of itself. Its three-party case is unproven over CloudKit.                                                                             |
| **Rival epoch secrets from two concurrent advances resolve identically everywhere**                                     | Untested                                                                                                                                                       | Two members advancing a room's epoch at the same moment is only possible with three parties. If they resolve differently, members hold different keys for the same epoch and messages stop opening for somebody. |
| **The narrow grant window with a stale roster, closed end to end**                                                      | Untested                                                                                                                                                       | A grant issued against a roster that has since changed. With two members the window barely exists; with three it is real.                                                                                        |

#### What would clear that section

One more Apple Account on the rig, without Advanced Data Protection, signed into a fourth simulator.
[The rig doc](simulator-rig.md) has the constraints — chiefly that ADP makes a simulator useless for
this app, and that `--reset-account` is destructive to the Apple Account rather than the device.

The work is a scripted pass, not a build. Each row above names what it would prove.

### Needs hardware

A simulator can do far more than this project once believed — real CloudKit against a live account,
real APNs, and the notification extension all run on one. These are what it still cannot do.

| Proof                                                                               | Why a simulator cannot                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | What is not yet watched |
|-------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **A push actually arriving** — a banner drawn from a bell rung by the other account | Griff reported a banner arriving on a phone from the other account on 2026-09-09; no log was read. On the simulator on 2026-09-14, alpha rang beta's bell and nothing arrived in five minutes, and again on 2026-09-19 in 90 seconds; `simctl push` no longer runs the extension either. Reply and Mark as Read are proved on two accounts from a banner whose payload carried the category and room, so the extension attaching them to a real message is on this list too. The extension has changed since the phone report: it stopped writing to the shared container on 2026-09-17. | Beyond that one report, everything downstream of a push is unwatched: the four notification rungs, tapping through, and a banner carrying a person and their picture. The app does not depend on push, because it collects in the foreground, but five rows rest on it.                                                                                                                                                                                                      |
| **The notification extension drawing a real banner**                                | Follows from the above; the extension runs on a simulator, but nothing wakes it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | The banner's words, its sender, its picture and its thread are covered by tests and have never been seen on a screen. Narrower since 2026-09-17: what the extension *decides* — which arrival wins, whether it is new, which rung, whether to deliver passively, and whether to attach the sender — was a nested function in a target `swift test` does not run, and is now `WhatArrived.since` with fourteen tests over it. What is owed is the drawing, not the reasoning. |
| **Focus filters attached to a Focus**                                               | A simulator has no Focus.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | A filter per Focus is built and tested (`FocusFilterTests`); no Focus has ever selected one.                                                                                                                                                                                                                                                                                                                                                                                 |
| **The system clip trimmer**                                                         | It refuses every file on a simulator.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Trimming a long clip is offered and has never been watched working.                                                                                                                                                                                                                                                                                                                                                                                                          |
| **A positive screening verdict**                                                    | Needs Apple's test profile on a device.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | The analyzer has run and judged clear. `notScreened` and `clear` are proved; a genuine positive is not, and it is the branch the Safety copy is about.                                                                                                                                                                                                                                                                                                                       |
| **One identity across two devices**                                                 | A simulator cannot join the Octagon trust circle, so it never receives an iCloud Keychain hand-off; every CKKS view sits in `waitfortrust`. Verified 2026-09-01.                                                                                                                                                                                                                                                                                                                                                                                                                         | The sibling feed's wire and its delivery between two devices were both proved over real CloudKit on 2026-09-14 — but with two device identifiers in one process. The hand-off that makes two *real* devices one member has never run.                                                                                                                                                                                                                                        |
| **The VoiceOver walk-through**                                                      | Stronger than this row used to say, measured 2026-09-17: a script cannot step VoiceOver on a simulator *at all*. Injected flicks do not move its cursor, injected touch paths do not either, and synthesized keystrokes never reach the device — with the window frontmost, *Simulate Hardware Keyboard* on and a field focused, typing put nothing in it. It needs a person's hands on a keyboard, or a phone. Griff ruled 2026-09-17 that it waits for a phone on TestFlight.                                                                                                          | Reading **order**, grouping and the rotor are still unheard. What is no longer owed is the **arrival announcement** on every screen: that is capturable headlessly from the caption panel, was walked on 2026-09-17, and found three real defects, all fixed — see [testing.md](testing.md).                                                                                                                                                                                 |
| **A device that has written nothing reaching its sibling's list**                   | The sibling feed between two real devices needs the Keychain hand-off above.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | `aSilentSiblingReachesTheList` holds it in the suite; a silent second phone has never appeared on a first one.                                                                                                                                                                                                                                                                                                                                                               |
| **Hiding reaching a member's own other devices**                                    | Same reason: it rides the sibling feed, which needs the hand-off above to be a second real device.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | The merge is tested and the feed crosses; the end-to-end act of hiding on a phone and seeing it hidden on a tablet has not been seen.                                                                                                                                                                                                                                                                                                                                        |
| **Deleting a conversation reaching the member's other phone**                       | Same reason.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Deletion is proved on one device and over real CloudKit, including after a relaunch; the other phone closing the room too has not been seen.                                                                                                                                                                                                                                                                                                                                 |
| **A line saying somebody added a device**                                           | Needs one account on two phones, for the same reason.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Tested in the suite; never seen drawn from a real second device.                                                                                                                                                                                                                                                                                                                                                                                                             |
| **A TestFlight build offering the free Supporter year**                             | Needs a build installed from TestFlight, where `AppTransaction` reports the sandbox environment. Debug builds skip the check.                                                                                                                                                                                                                                                                                                                                                                                                                                                            | If the detection is wrong, TestFlight testers see no Supporter bar, or an App Store build shows one.                                                                                                                                                                                                                                                                                                                                                                         |

### Needs something outside the app

| Proof                                             | Why                                                                                                                                                                                     | What is not yet watched |
|---------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| **Sending an abuse report from the app**          | The addresses exist, and Griff confirmed on 2026-09-17 that mail to them arrives. A simulator has no mail account, so the report sheet's send has not been watched from a phone.        | The sheet is seen and its copy checked.                                                                                                         |
| **The report vault**                              | Same: it has to exist before anything can be filed in it.                                                                                                                               | Trust and safety is findable in the app and has nowhere to land.                                                                                |
| **An invitation expiring at the inviter's relay** | The gate wants an inviter who stays offline past the expiry date. `--clock-ahead-days` can now move one device's clock, which may make this runnable on the rig; it has not been tried. | The expiry is enforced on the device holding the link and in the relay; only the relay half is unproven, and only for the offline-inviter case. |

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
