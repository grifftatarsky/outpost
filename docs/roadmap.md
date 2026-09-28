---
# COPY BEGIN 550f36a8 [NEEDS HUMAN REVIEW]
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

<!-- COPY END 550f36a8 -->

<!-- COPY BEGIN 2e28e41a [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 2e28e41a -->

<!-- COPY BEGIN 2e97a3d8 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 2e97a3d8 -->

<!-- COPY BEGIN bc7d0367 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary><b>Getting a message there</b> · 10 tickets — 9 tested · 1 proved above the mailbox</summary>

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

</details>

<!-- COPY END bc7d0367 -->

<!-- COPY BEGIN 0ac943dc [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary><b>Telling someone it arrived</b> · 10 tickets — 4 tested · 6 hardware proof owed</summary>

| Ticket | Status | Evidence |
|---|---|---|
| A bell that rings for a message and nothing else | Complete (hardware proof owed) | The bell is written, subscribed to and **rung**: alpha logged `mailbox: rang a peer's bell` on 2026-09-14 with beta backgrounded, and **no push reached the app over five minutes** — measured, not inferred. Everything up to delivery is proved; delivery is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Notification previews | Complete (hardware proof owed) | Four rungs, per room, driven on the rig. The extension's banner needs a push to draw it — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Unread, and the number on the icon | Complete (tested) | Dot and badge on beta 2026-09-02, cleared by reading. The extension's half rides on the push. **2026-09-17: the number ignored the member's own switches** — `BadgeCount` counted unread rooms unconditionally, never read `BadgeChoices` and never counted Outposts, so two controls on the Notifications screen did nothing and all four sentences of `BadgeMeaningLine` were false. Fixed, and it is one `AppSession.badgeNumber` the app and the extension share rather than a sum written twice ([Decisions](decisions.md#the-number-on-the-app-icon-is-one-property-and-it-obeys-the-switches)). Measured on Quad: 1 with an unread room, none once the switch was off with the message still unread, and back again. |
| Asking for notifications honestly | Complete (tested) | Explainer on the first ready screen on both simulators 2026-09-04. |
| Tapping through, and what happens next | Complete (hardware proof owed) | A banner for a room this member no longer has opens the app and navigates nowhere; one tapped while already in that room does nothing. The decision sits in `AppSession.tapping(_:whileViewing:)` so it is testable (`TappingThroughTests`). Watching a real banner be tapped is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| A banner from a person | Canceled | Ruled out 2026-09-27 with every other Siri surface: a banner is an ordinary notification, with no sender or photo handed to Siri. See [No Siri and no Apple Intelligence](decisions.md#no-siri-and-no-apple-intelligence). |
| Silenced notifications, shared | Complete (tested) | Two switches and a custom message (`FocusStatusTests`). Beta's pretend Focus drew *Do Not Disturb*, then *Heads down till six*, over alpha's field 2026-09-06. |
| Focus filters | Complete (hardware proof owed) | A filter per Focus: which rooms may notify, whether banners carry the words (`FocusFilterTests`). 2026-09-17, found while making the extension's decisions testable: *Show what was said* was applied to a message and not to a post, so a Focus set to hide it still put a post's body on the lock screen. Fixed — the preview switch reaches a post, the room list deliberately does not ([Decisions](decisions.md#a-focus-filters-preview-switch-reaches-a-post-and-its-room-list-does-not)). A simulator has no Focus — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Settings split by what rings | Complete (hardware proof owed) | Notifications is a master switch over two pages, Messaging and Outposts, each with its own urgency; badges carry a separate setting saying what they count. `NotificationLevelTests`, `BadgeCountTests`, `WhatTheTabsBadgeTests`, driven on the rig 2026-09-11. Seeing one with a real push is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Asking for Outpost notifications | Complete (tested) | A step in onboarding, and a gear on an Outpost's own page for one wall at a time. Walked end to end on two Apple Accounts 2026-09-15: beta allowed alpha in from the room banner — behind an alert that says plainly it cannot be undone — beta posted, the post crossed, Outie appeared on alpha's rail, and the gear on that wall carried *Get notifications for this Outpost* with the honest footer that the other person is not told. Turned on and it held. |

</details>

<!-- COPY END 0ac943dc -->

<!-- COPY BEGIN 7e73965c [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary><b>Who is in a room</b> · 24 tickets — 14 tested · 3 proved above the mailbox · 3 hardware proof owed · 2 operational proof owed · 1 QA required · 1 incomplete</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Setting up a room | Complete (tested) | Creation sheet, policies, people picker, the invitee's sheet: 2026-09-01 and 02. |
| Removing somebody | Complete (tested) | Removed member could not read the next epoch: 2026-09-02. Two-member case only. |
| The room chain | Complete (QA required) | Ruled by Griff 2026-09-28 and built the same day: every entry names its device's last entry in the room, a removal or a departure names where each of the person's chains ends, and only those chains are shown. `TheRoomChainTests`; the package suite passes on Griff's Mac. **Not yet run on the rig**, and every device has to take this build together: an older build refuses chained entries. A removed device is not covered yet; Griff has asked for it closed ([Open questions](open-questions.md#raised-and-answered-2026-09-28)). |
| A removal holds against what the removed person writes after it | Incomplete | Found by reading 2026-09-28, not yet shown by a test: the member list reads a removed person's entries in the order their dates give, not by the chain, so their modified app could remove the person who removed them or bring in a second identity ([Open questions](open-questions.md#does-a-removal-decide-who-is-in-a-room-or-only-what-the-room-shows)). |
| Tapping two phones swaps codes | Complete (hardware proof owed) | Ruled by Griff 2026-09-28 and built the same day: the phones find each other over the local network, measure each other with the ultra-wideband chip, and swap codes, sealed between them, once exactly one phone is touching and both people say yes; an invite goes back the same way. `TappingPhonesTests`; the package suite passes on Griff's Mac. **Not run on any phone**; needs two iPhones with the chip, so it is proved on TestFlight. See [Decisions](decisions.md#tapping-two-phones-swaps-codes). |
| Leaving properly | Complete (tested) | Beta left, both drew it, alpha rotated the key: 2026-09-02. |
| Blocking a person | Complete (tested) | Local silent block built 2026-09-04; the key handover built 2026-09-14 against six tests. A blocked person is not a peer, so nothing of theirs is collected or acknowledged and their app stops being told *collected* — which is the signal the convention runs on — they are handed no future room keys, no media and no bell, and they are dropped from the Outpost audience. Nothing said while they were blocked is lost. The epoch turn this was first specified with was dropped on building it: in a group every other member re-grants the key anyway. |
| Reporting a message | Complete (operational proof owed) | Sheet seen on the rig 2026-09-04 and its copy checked. The addresses exist and receive mail (Griff, 2026-09-17); a send from a phone has not been watched, and the vault a filed report goes into does not exist yet — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md) and [Before TestFlight](pre-testflight.md#operational). |
| Per-person Outpost access | Complete (tested) | The wall is sealed to the people let in, two offers enforced by which epoch links a grant carries, the room's review, the allow-list and the reciprocal card. Driven on two accounts three times, 2026-09-07. |
| The one stranger | Complete (proved above the mailbox) | A comment seals under the wall it lands on, so everybody unmet is one shared figure. Nine tests, four mutation-proven. Three devices, 2026-09-09: the same comment drew as *Quad* to somebody sharing a room and as *User 403* to somebody sharing nothing. |
| Open or closed on other people's Outposts | Complete (proved above the mailbox) | Three answers plus off, asked in the check-up after both doors and changeable in Outpost settings. Closed seals a comment under the writer's own wall and carries a second copy for the post's author, so it never refuses. Sixteen tests, six mutation-proven. Three devices, 2026-09-09: the owner read both closed comments; the co-reader read *2 comments are not shown*. |
| A confirmation answers one invitation | Complete (tested) | Keyed by the invitation rather than the person, so somebody asked back after a removal reads the six characters again. The room's own half was closed 2026-09-14: `RoomRoster` keys admissions and refusals on the invitation too, so a vote cast for a superseded offer no longer admits somebody to the live one — pinned by `MembershipTests` and `JoinIsARoundTripTests`. |
| Invitations that are never accepted | Complete (operational proof owed) | The expiry is enforced at the inviter's relay as well as on the device holding the link and never when the log is read; the two lists split on whether the offer was taken; taking one back is open to any member in good standing; a date you pick has a control. The relay gate wants an inviter who stays offline past the date, which is a clock the rig cannot move — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
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
| The removal audit's open cases | Complete (tested) | 2026-09-16: `RemovalSurvivesACrashTests` cuts a removal off at both of its halves and relaunches. Before the fix, both left the key unrotated **and the removed member read what was said next**. A removal now records the key rotation it owes before it writes, the way an Outpost revocation already did, and every round retries it. The two three-party cases are in [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |

</details>

<!-- COPY END 7e73965c -->

<!-- COPY BEGIN 3282db1c [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary><b>Your identity across your devices</b> · 15 tickets — 7 tested · 1 proved above the mailbox · 5 hardware proof owed · 1 built, not yet on a phone · 1 incomplete</summary>

| Ticket | Status | Evidence |
|---|---|---|
| A new device needs approval | Complete (hardware proof owed) | Built 2026-09-26 on Griff's ruling: a code on both devices, approval hands over the identity, the recovery key is the only other way in. Package tests and a live CloudKit test; two real devices owed. |
| Removing a device cuts it off | Complete (hardware proof owed) | Built 2026-09-26: room keys sealed per device, a removed device erases itself, a removal step after a recovery-key restore. |
| Your devices send each other only what is new | Complete (hardware proof owed) | Built 2026-09-26: mail instead of the whole feed, deleted once read. Package tests and a live CloudKit test; two real devices on one account owed. |
| The sibling feed is sealed before it is written | Complete (tested) | Found and fixed 2026-09-13: the record had carried every epoch secret the member held, in the clear, since 2026-08-16. `SiblingFeedIsSealedTests`, mutation-proven. Proved over real CloudKit 2026-09-14: the raw CKRecord was fetched back off the server and the epoch secret is not in it, the payload is exactly the ciphertext, the member's identity reopens it and a stranger's is refused — and a second device was handed it and opened it (`LiveSiblingFeedTests`). The iCloud Keychain hand-off that makes two *real* devices one member is hardware-only. |
| One identity across a member's devices | Complete (hardware proof owed) | Keychain hand-off, device list, revocation, the checking screen: built. The sibling feed's wire and its delivery between two device identifiers were proved over real CloudKit 2026-09-14; the iCloud Keychain hand-off that makes two *real* devices one member cannot happen on a simulator — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Erase everything | Complete (tested) | Run from the sheet on alpha, 2026-09-15, which is what this row was waiting for. The sheet lists what is erased and — the half that matters — what is **not**: nothing leaves anybody else's device, rooms are not told, and nobody can restore it. A confirmation dialog then says the same in one sentence. The wipe ran, and the app came back to onboarding on a genuinely empty account. |
| Recovery settings, and telling people a restore asked them | Complete (tested) | Ruled 2026-09-13 and built the same day, against 24 tests. The recoverer chooses whether to ask peers at all; the person asked is always told, and can hold it behind a solo check. This row read "None of it built" until 2026-09-14, when the code was read — and writing a live test that day found the notice **defaulted to off**, with the friendly preset turning it off explicitly, so the members least likely to go looking were the ones not told. Fixed and pinned. The quiet restore — asking nobody, telling nobody, coming back to empty rooms — is proved over real CloudKit (`LiveRecoveryTests`). |
| Recovery from a lost device | Complete (tested) | *I have a recovery key* on the welcome screen **and on the stalled screen a new phone on an occupied account actually lands on** — it was reachable only from onboarding until 2026-09-13, which put it out of reach in the one case it exists for. The key is read on the device, the identity goes back in the keychain, a fresh device key is minted. Run end to end on two accounts 2026-09-13: export, restore, the room and its history back, and the peer's entries back after the restored device raises its own repair. What the rig found and the suite had not: a peer never re-offers an entry it has already spent, so a restored device has to raise its own repair (`askEverybodyForWhatWasSaid`) — without it `entriesReceived` was 0 on every round while the peer wrote `unsent=0`, and the peer's messages and even their display name never came back. With it, the room, both members' messages and the names all return. `RestoringFromAKeyTests` covers the round trip, the new device key, the sibling-device path, the peer path (mutation-proven), a device that already has a member, and each of the four ways a key can be wrong. |
| An in-app lock | Built, not yet on a phone | Reopened by Griff 2026-09-27 and built the same night: the app's own code or passphrase, Face ID on top, offered at setup and in Settings; setting it offers private notifications; the recovery key opens it; erasing after wrong codes if chosen. Package tests and a simulator walk-through; not run on a phone. It was canceled 2026-09-14 in favour of iOS's own app lock, which falls back to the phone's passcode. |
| Advanced On Device Security | Incomplete | Ruled by Griff 2026-09-28 and built the same day, for the phone's lock: everything the app keeps opens only while the phone is unlocked, nothing is fetched while it is locked, and the extension shows only "New message". `SealedWhileLockedTests` and `SystemKeychainTests` pass, the latter on the simulator; `FileProtectionTests` passes on an iPhone (a simulator does not keep a file's protection class, so it is skipped there). **Not yet tried with the phone locked.** Ruled and not built yet: Outpost's own lock with a PIN, a note on each option and a link to an article; collecting what arrives while locked, so nothing is lost; and sealing the app's preferences ([Decisions](decisions.md#advanced-on-device-security-seals-what-this-phone-keeps-while-it-is-locked)). |
| The device list tells the truth | Complete (hardware proof owed) | Every device used to self-certify at `.distantPast`, so *here since you made this identity* was true of the founding device and claimed by every later one — and a relaunch re-issued the certificate, making *added* really mean *last launched*. Both fixed 2026-09-13, with a third found on the way: on a fresh install the device a member is holding read *never been used*. A fourth was found on the rig the same day, once eight devices had accumulated: a device that had spoken plenty read *added, but it has never been used — setup may not have finished*, because `hasSpoken` is computed from the entries **this** device holds and a restored device holds few. That is an inference from absent evidence, which this app does not make about anything else; it now says what it knows — *nothing it sent has reached this device* — beside the real date. Each device also carries a **name** now — from its hardware identifier on first launch, renameable, private to the member because preferences ride the sealed sibling feed. `TheDeviceListTellsTheTruthTests`, `NamingYourDevicesTests`. A device that has written nothing now reaches its sibling's list and can be revoked, 2026-09-16 (`aSilentSiblingReachesTheList`; unproven across CloudKit). The one-identity-per-account policy is decided and enforced: an occupied account stops, and since 2026-09-16 one that cannot be reached waits (`ExistingRegistrationTests`). |
| Names and faces shared by choice | Complete (tested) | Names and photos both ways, off by default (`SharingTests`, `PhotoSharingTests`). Beta's photo collected on alpha and taken down again 2026-09-06. |
| A privacy check-up at first run | Complete (tested) | Three doors after the name, with examples (`PrivacyCheckupTests`). Both the preset and the walkthrough seen on the rig 2026-09-06. |
| A name and a face of your own for somebody | Complete (tested) | Nickname on the sibling feed, photo on this device, a People page under the identity row (`NicknameTests`). Seen on the rig 2026-09-06. |
| Supporter: the TestFlight year and the badge | Complete (proved above the mailbox) | Built 2026-09-17: the bar, the thank-you page, the badge question, the Supporter page and the badge on avatars (`SupporterStandingTests`, `SupporterBadgeTests`). The whole flow on gamma, and gamma's badge drawn on delta, over the directory mailbox. Re-run on gamma 2026-09-17 against the current build, both paths: the bar, the thank-you page, the badge question, the badge on the You row and the Supporter page; and the decline path, which leaves the bar gone, the year kept and the pencil where it was. That run **found the check was not repeatable** — it had claimed the year on a previous run and could never pass again, which is a check that silently stops checking. `--forget-supporter` clears the three preference fields on launch, in `#if DEBUG` and on the release-leaves list, and both tests now take it. Not yet seen on a TestFlight build, and the App Store purchase is not built. |

</details>

<!-- COPY END 3282db1c -->

<!-- COPY BEGIN 5d2c38e0 [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 5d2c38e0 -->

<!-- COPY BEGIN 959ea199 [NEEDS HUMAN REVIEW] -->

<details markdown="1">
<summary><b>What you can send</b> · 24 tickets — 14 tested · 3 tested, not yet on a real account · 3 hardware proof owed · 1 proved above the mailbox · 1 in progress · 2 QA required</summary>

| Ticket | Status | Evidence |
|---|---|---|
| Text, with formatting | Complete (tested) | Markers covered by the suite. The entries that carry them proved over real cloudkit 2026-09-14; the markers themselves are drawn on the reading device and never cross, so there is nothing further for two accounts to show. |
| Photos | Complete (tested) | 770 KB up, same bytes down, drawn on the other account: 2026-09-04. |
| Each pair of people gets its own mailbox | Complete (proved above the mailbox) | Built 2026-09-27 and 2026-09-28: one space per contact in your own iCloud, read by that contact alone; links swapped in codes, invites, and sealed room entries passed on by whoever talks to both. After a review of the build: a link counts only from a device that still counts, a contact is read only from accounts such links name, and blocking closes the space kept for them. `EachPairHasASpaceOfItsOwnTests`, `WhoCanTellYouWhereToReadSomebodyTests`, every guard mutation-checked. Three simulators over the directory mailbox, 2026-09-28: two members the room introduced talked with the inviter's app closed. **Not yet run over iCloud**: both rig accounts wanted their passwords; `LivePairTests` is ready. See [Decisions](decisions.md#each-pair-of-people-gets-its-own-mailbox). |
| Each person's copy of a photo sealed apart | Complete (QA required) | Ruled by Griff 2026-09-28 and built the same day: each copy sealed again under its pair's original secret and named from it, the label that says which photo it is sealed too, receipts named after the copy. `PhotoCopiesAreSealedApartTests`; the package suite passes on Griff's Mac. **Not yet run on two accounts.** See [Decisions](decisions.md#a-photo-is-copied-for-each-person-it-goes-to-and-each-copy-is-sealed-apart). |
| A space closes nine days after nothing is shared | Complete (QA required) | Ruled by Griff 2026-09-28 (always on) and built the same day: a device marks when it first shares nothing with somebody, closes the space nine days later and stops writing to them; sharing again opens a new space. `ASpaceClosesWhenNothingIsSharedTests`; the package suite passes on Griff's Mac. **Not yet run on the rig.** See [Decisions](decisions.md#the-space-kept-for-somebody-closes-nine-days-after-you-last-shared-anything-with-them). |
| Your hidden address changes when a device is removed | Complete (tested), unproven on a real account | A removed device can no longer work out where your packets are left or open them: removing a device gives you a new address salt your other devices hold and your contacts take from a signed announcement (`ChangingYourHiddenAddressTests`, `AnAddressOnlyYourDevicesKnowTests`, every guard mutation-checked). See [Decisions](decisions.md#your-hidden-address-changes-when-a-device-is-removed). **Owed**: a removal on the rig, with a message crossing afterwards. |
| Asking for a photo again | Complete (tested), unproven on a real account | A photo that is gone can be asked for; the sender sees *Photo requests* in the conversation's menu with the person, the photo and a way back to it, and nothing goes up until they tap *Send* (`AskingForAPhotoAgainTests`, every guard mutation-checked). See [Decisions](decisions.md#a-photo-can-be-asked-for-again-and-the-sender-decides). **Owed**: seeing the screens on a device, and an ask across two accounts. |
| Only the sender clears a photo | Complete (tested), unproven on a real account | Readers sign for a photo with a receipt instead of deleting it; the sender clears it once one device of everybody it was for has signed or after nine days, puts back one that left early, and keeps its own copy (`NobodyButTheSenderClearsAPhotoTests`, `APhotoAndTwoDevicesTests`, every guard mutation-checked). See [Decisions](decisions.md#only-the-sender-clears-a-photo-and-keeps-its-own-copy). **Owed**: the live mailbox tests on the rig. |
| Clips | Complete (tested) | Sent, screened as a file, played on the other account: 2026-09-04. Up to 287 MB in 16 MB pieces since 2026-09-27: in the package and a 35 MB clip live; not yet between two accounts. Sent as recorded since 2026-09-27, with *Make it fit* for a clip over the limit: in the package only. |
| Captions | Complete (tested) | "Ice plants in bloom" under the photo on the other account: 2026-09-04. |
| On-device screening and the blur | Complete (hardware proof owed) | The analyzer ran on the rig and judged clear; `notScreened` and `clear` are both proved. A positive verdict needs Apple's test profile on a device — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| The deny list | Complete (tested) | `BlockingTests`. A listed sender is shut out the same way a blocked one is since 2026-09-14 — not answered rather than not drawn — and the switch plus a round restores them with nothing lost. |
| Reactions on messages | Complete (tested) | Two-circle stack on the receiving account 2026-09-04. |
| Scale and crop a picked avatar | Complete (tested) | A crop step before anything is saved, on all three pickers (`AvatarCropTests`, mutation-checked). Verified on alpha against a picture with its subject hard off to one side. |
| An Outpost inherits your face | Complete (tested) | A member's own wall draws their own avatar, with two controls to override it there and nowhere else (`AvatarPrecedenceTests`, `OutpostPhotoSharingTests`). Proved over real CloudKit 2026-09-14: a wall's own face crossed and the reader fetched the same bytes (`LiveOutpostTests`). |
| Photos on an Outpost | Complete (tested) | Up to four photos or clips as one post, with the words as the caption (`OutpostPhotoTests`). Proved over real CloudKit 2026-09-14: a post with a photo reached a reader and the bytes came back identical — an attachment travels as a CKAsset, a different path from every other proof here (`LiveOutpostTests`). |
| What is new on somebody's wall | Complete (hardware proof owed) | A ring on the rail and a flag in the list, from a device-local mark set when this member was let in (`OutpostUnseenTests`). Proved over real CloudKit 2026-09-14: a post crossed, lit as unseen for the reader, stayed unseen-free for its author and cleared when read (`LiveOutpostTests`). The **banner** for it waits on a push, which is hardware — [Proofs a rig cannot run](proofs-a-rig-cannot-run.md). |
| Editing and deleting your own posts | Complete (tested) | Rendering always could; the session, the read model and the menus now say so (`OutpostEditingTests`). Proved over real CloudKit 2026-09-14: an edit and a withdrawal both reached the reader, for posts and for messages (`LiveOutpostTests`, `LiveRoundTests`). A photo post is deliberately not editable — rendering refuses it. |
| Storage and retention | Complete (tested) | The number is on the You screen since 2026-09-05, read from `FileMediaStore.byteCount()`, and **nothing being deleted on its own is the answer rather than a gap** (ruled 2026-09-13). The date-based clear went to [After TestFlight](after-testflight.md#clearing-media-older-than-a-date) on 2026-09-14, which is the whole of what was outstanding. |
| Search | Complete (tested) | A search tab with sectioned results over conversations, message text, photos and posts. `SearchTests`: twelve tests over what it finds and what it refuses — withdrawn, hidden, blocked — the ordering and the tiebreak. Search reads the local replica, and the entries it reads proved over real cloudkit 2026-09-14. |
| Test profiles | In progress (debug builds, never run) | Griff's design, 2026-09-26: a world of its own on a mailbox the member hosts, opened from You → Test profiles and from the stalled registration screens. Separate storage, a device-only identity and switching are in (`TestProfilesTests`); the only mailbox is the rig's shared directory, there is no server mailbox yet, and the app has not been built for iOS or run since, because Xcode 27's licence is not accepted on the build Mac. See [Decisions](decisions.md#a-test-profile-is-a-world-of-its-own). |
| A searchable emoji picker | Complete (tested) | Built 2026-09-15. `Scripts/make-emoji-table.py` turns Unicode's `emoji-test.txt` into a 1,914-emoji resource in nine groups. Searchable by name, whole-word matches first. Walked on the rig 2026-09-16 with the software keyboard: it was a popover and its field went under the navigation bar when the keyboard rose, so a phone now gets a sheet with detents and a wide screen a popover — [why the documented default was not trusted](epics/content-and-composer.md#the-system-emoji-picker). Named limit: the names are English only. |
| Blocking reaches posts, not only messages | Complete (tested) | `block` set a local preference that only `messages(in:)` consulted, so a blocked person stayed on the Outposts tab, in search and in the badge. `feed()`, `outpostAuthors()`, `comments(on:)` and `outpostAuthorsWithUnseen()` all filter now, and since 2026-09-14 so do `peers()`, both rewrap paths, the media upload, the bell and `outpostReaders()`. |
| The disabled affordances | Complete (hardware proof owed) | Every drawn control does something. *Create the invite* waits for a parseable code, compose-from-feed works, emoji in room names and local nicknames were built (2026-09-14, 2026-09-06). Camera scanning, 2026-09-16: a Scan button beside Paste, asked about first in the app's words and kept apart from the camera prompt so the HIG's pre-alert rules hold, with a setting in Privacy & Safety. **The scanner itself has not run** — a simulator has no camera; a phone must scan a real invite. |

</details>

<!-- COPY END 959ea199 -->

<!-- COPY BEGIN 87319ce6 [NEEDS HUMAN REVIEW] -->

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
| A test seam that cannot lie | Complete (tested) | The in-memory mailbox goes through the wire mapping, counts every server operation, holds the record ceiling and hands a photo to anybody who can read the outbox, as CloudKit does; the in-memory log encodes each entry; the sibling relay holds `Data`. Six tests hold the fakes to those contracts (`TheFakeIsNoEasierTests`). The one gap the fakes cannot have an opinion about — **order** — is pinned on the real server now, twice: at the mailbox and across a twenty-four-entry round. |
| Before TestFlight | Incomplete | The language pass is done 2026-09-05, the debug leaves are out of a release build, the dark-and-light sweep is done except the surfaces that need a push or a phone, the deprecation warnings are all fixed and `ITSAppUsesNonExemptEncryption` is set, 2026-09-17. Left: the hardware proofs, both suites and a rig walk on an iOS 27 runtime, and the operational list — the report vault, refusing attachments at `abuse@`, publishing the source under its license (the license exists), and App Store Connect. The mailboxes exist. The marketing site was rewritten against the build on 2026-09-17: its screens are screenshots of the app now rather than a retired design export, and every page's copy was checked against the code. |
| A CloudKit integration target | Complete (tested) | The seam driven against a real account, and since 2026-09-14 the whole round above it. Nine tests on the mailbox — the wire round trip, every scanned field, the change feed, acknowledgment, a photo's bytes, the order records come back in, and the record ceiling in both directions — plus thirteen on rounds, the sibling feed and the Outpost (`LiveRoundTests`, `LiveSiblingFeedTests`, `LiveOutpostTests`). The unlock was that a packet is addressed by `RecipientTag` and never by an account, so two whole sessions in one account prove a round. |
| The help the welcome tour promises | Complete (tested) | Broken on iPhone until 2026-09-15, and broken the same way twice. *Help on every screen* first wrote a preference nothing read; that was fixed — on the desktop path. The **iPhone tab** built its own `YouView` and left `tutorialMode:` off the argument list entirely, so it took the `.constant(false)` default: the switch moved, wrote nothing, and no `?` ever appeared on the only platform this app ships on. Found by walking the rig. There is one `youScreen` now, used by both platforms, so the two argument lists cannot drift again — which also restored three settings the *desktop* was missing. Four tests in `HelpOnEveryScreenTests`, and the `?` was seen opening *How this works*. |
| Light mode, from rules rather than drawings | Complete (tested) | Every swatch carries a real light value and the contrast audit covers both appearances. The sweep of surfaces the system draws was done 2026-09-15. 2026-09-17: every color a view picks for itself was measured in both appearances, with Increase Contrast on and off, for every accent — the destructive red, Increase Contrast fills, unlit marks, four filled buttons, accent words on cards, the anonymous face and white words on glass over photos were all fixed, seven audit tests added, and what stays is in [Decisions](decisions.md#a-color-is-measured-on-every-ground-it-is-drawn-on-in-both-appearances). |
| Transitions | Complete (tested) | Sheet, tab switch and navigation push use the system's motion, by decision. The accent retint is one 0.2s cross-fade; recorded frame by frame 2026-09-16, the system tab bar changes about 85ms ahead of the app's own surfaces, and Griff ruled the same day to keep the fade. |
| The crypto, written down | Complete (tested) | Written 2026-09-15: [The crypto, written down](crypto-brief.md), from the twelve files rather than from the architecture doc. Covers every construction twice — plain and technical — with the threat model, what the relay is handed, and what is out of scope. Found one thing that needs a ruling (the six-character phrase is ~29.4 bits with **no commitment step**, so one side of a MITM can grind it offline in hours — **ruled 2026-09-15**: ten characters *and* a commitment, see [Decisions](decisions.md#the-verification-phrase-gets-ten-characters-and-a-commitment)), three trade-offs accepted with reasons and two small things parked, all in [Decisions](decisions.md#what-the-crypto-brief-found). The app now states the limit too: *Who has checked this* on the How it works screen. The outside review was canceled 2026-09-14. |

</details>

<!-- COPY END 87319ce6 -->

<!-- COPY BEGIN e3aa4f04 [NEEDS HUMAN REVIEW] -->

## Next up

Taken from the table rather than from what was last touched, 2026-09-17.

1. **The marketing site**, rewritten against the build, with a roadmap page and a page for Bullet
   ([Before TestFlight](pre-testflight.md#the-marketing-site)).
2. **Before a build goes out** — the report vault, refusing attachments at `abuse@`, publishing the
   source, and App Store Connect ([Before TestFlight](pre-testflight.md#operational)).
3. **A phone on iOS 27**, and a second phone on the same account, for the tickets owed a hardware
   proof, both suites, a walk, and the VoiceOver pass.

<!-- COPY END e3aa4f04 -->

<!-- COPY BEGIN 39410734 [NEEDS HUMAN REVIEW] -->

## To research

1. **Siri, completely privately.** Griff, 2026-09-27: people may want to ask Siri to write a message.
   Today the app gives Siri nothing. The question is whether a message can be composed through Siri
   without the words, the person or the conversation being handed to the system's stores. Nothing
   is built until the answer is yes.
2. **Closing the window before a removal is heard.** A stolen phone keeps working until its owner
   removes it and the people they talk to hear about it, and nothing can start the clock before the
   owner knows something is wrong. Is there some method, however unusual, that narrows it? Probably
   not; recorded so the question is asked once properly.

<!-- COPY END 39410734 -->

<!-- COPY BEGIN 94574bfb [NEEDS HUMAN REVIEW] -->

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

<!-- COPY END 94574bfb -->
