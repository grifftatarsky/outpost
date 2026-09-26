---
# COPY BEGIN 7d756458 [NEEDS HUMAN REVIEW]
title: Proofs a rig cannot run
layout: default
nav_order: 7
---

# Proofs a rig cannot run

{: .no_toc }

Verification — not building — that four simulators and two Apple Accounts cannot do, whatever is
written. Two reasons only: it needs a third Apple Account, or it needs hardware.

1. TOC
{:toc}

<!-- COPY END 7d756458 -->

<!-- COPY BEGIN b9a781b3 [NEEDS HUMAN REVIEW] -->

## Why this page exists

`RULED` — Griff, 2026-09-14, twice: first for three-account work, then for everything manual.

**Nothing lands here until a rig workaround has been looked for and not found.** That bar moved a
long way on 2026-09-14. A packet is addressed by a `RecipientTag` and never by an Apple Account, so
two whole `AppSession`s sharing one zone in **one** account prove an entire round over real
CloudKit — a message crossing, a round over the cap arriving in order, every packet acknowledged, a
hole refilled, a read report moving a mark, an edit and a withdrawal landing, a photo reaching a
reader, a wall's own face, a comment coming back. Thirteen rows that said *unproven on two accounts*
were proved that way in an afternoon, without leaving the machine.

What survives is only what genuinely cannot be reached: a **share** needs a second account to accept
it, a third party needs a third account, and some things need a phone.

Nothing here blocks TestFlight on its own. What it costs is stated in each row, so the decision to
ship without them is taken with the cost visible rather than by forgetting they exist.

<!-- COPY END b9a781b3 -->

<!-- COPY BEGIN 6c541474 [NEEDS HUMAN REVIEW] -->

## Needs a third Apple Account

| Proof | Where it stands | What shipping without it costs |
|---|---|---|
| **A comment crosses a triangle over CloudKit** — three identities, an Outpost post, a comment from the third party | Proved above the mailbox 2026-09-09 on three devices and three identities; proved between **two** real accounts over CloudKit 2026-09-07 with the current seal | A three-party Outpost thread has never run over the real transport. The two-account path is proven, and the third party's seal is the same shape, so the risk is in the addressing rather than the crypto. |
| **A closed comment crosses a triangle over CloudKit** — the same, where the thread is closed and the count is published | Proved above the mailbox 2026-09-09; proved between two real accounts 2026-09-07 | The published comment count is the one thing in the app that is not proof of itself. Its three-party case is unproven over CloudKit. |
| **Rival epoch secrets from two concurrent advances resolve identically everywhere** | Untested | Two members advancing a room's epoch at the same moment is only possible with three parties. If they resolve differently, members hold different keys for the same epoch and messages stop opening for somebody. |
| **The narrow grant window with a stale roster, closed end to end** | Untested | A grant issued against a roster that has since changed. With two members the window barely exists; with three it is real. |

<!-- COPY END 6c541474 -->

<!-- COPY BEGIN fc028c33 [NEEDS HUMAN REVIEW] -->

### What would clear that section

One more Apple Account on the rig, without Advanced Data Protection, signed into a fourth simulator.
[The rig doc](simulator-rig.md) has the constraints — chiefly that ADP makes a simulator useless for
this app, and that `--reset-account` is destructive to the Apple Account rather than the device.

The work is a scripted pass, not a build. Each row above names what it would prove.

<!-- COPY END fc028c33 -->

<!-- COPY BEGIN 07591ce1 [NEEDS HUMAN REVIEW] -->

## Needs hardware

A simulator can do far more than this project once believed — real CloudKit against a live account,
real APNs, and the notification extension all run on one. These are what it still cannot do.

| Proof | Why a simulator cannot | What shipping without it costs |
|---|---|---|
| **A push actually arriving** — a banner drawn from a bell rung by the other account | Griff reported a banner arriving on a phone from the other account on 2026-09-09; no log was read. On the simulator on 2026-09-14, alpha rang beta's bell and nothing arrived in five minutes. The extension has changed since the phone report: it stopped writing to the shared container on 2026-09-17. | Beyond that one report, everything downstream of a push is unwatched: the four notification rungs, tapping through, and a banner carrying a person and their picture. The app does not depend on push, because it collects in the foreground, but five rows rest on it. |
| **The notification extension drawing a real banner** | Follows from the above; the extension runs on a simulator, but nothing wakes it. | The banner's words, its sender, its picture and its thread are covered by tests and have never been seen on a screen. Narrower since 2026-09-17: what the extension *decides* — which arrival wins, whether it is new, which rung, whether to deliver passively, and whether to attach the sender — was a nested function in a target `swift test` does not run, and is now `WhatArrived.since` with fourteen tests over it. What is owed is the drawing, not the reasoning. |
| **Focus filters attached to a Focus** | A simulator has no Focus. | A filter per Focus is built and tested (`FocusFilterTests`); no Focus has ever selected one. |
| **The system clip trimmer** | It refuses every file on a simulator. | Trimming a long clip is offered and has never been watched working. |
| **A positive screening verdict** | Needs Apple's test profile on a device. | The analyzer has run and judged clear. `notScreened` and `clear` are proved; a genuine positive is not, and it is the branch the Safety copy is about. |
| **One identity across two devices** | A simulator cannot join the Octagon trust circle, so it never receives an iCloud Keychain hand-off; every CKKS view sits in `waitfortrust`. Verified 2026-09-01. | The sibling feed's wire and its delivery between two devices were both proved over real CloudKit on 2026-09-14 — but with two device identifiers in one process. The hand-off that makes two *real* devices one member has never run. |
| **The VoiceOver walk-through** | Stronger than this row used to say, measured 2026-09-17: a script cannot step VoiceOver on a simulator *at all*. Injected flicks do not move its cursor, injected touch paths do not either, and synthesized keystrokes never reach the device — with the window frontmost, *Simulate Hardware Keyboard* on and a field focused, typing put nothing in it. It needs a person's hands on a keyboard, or a phone. Griff ruled 2026-09-17 that it waits for a phone on TestFlight. | Reading **order**, grouping and the rotor are still unheard. What is no longer owed is the **arrival announcement** on every screen: that is capturable headlessly from the caption panel, was walked on 2026-09-17, and found three real defects, all fixed — see [testing.md](testing.md). |
| **A device that has written nothing reaching its sibling's list** | The sibling feed between two real devices needs the Keychain hand-off above. | `aSilentSiblingReachesTheList` holds it in the suite; a silent second phone has never appeared on a first one. |
| **Hiding reaching a member's own other devices** | Same reason: it rides the sibling feed, which needs the hand-off above to be a second real device. | The merge is tested and the feed crosses; the end-to-end act of hiding on a phone and seeing it hidden on a tablet has not been seen. |
| **Deleting a conversation reaching the member's other phone** | Same reason. | Deletion is proved on one device and over real CloudKit, including after a relaunch; the other phone closing the room too has not been seen. |
| **A line saying somebody added a device** | Needs one account on two phones, for the same reason. | Tested in the suite; never seen drawn from a real second device. |
| **A TestFlight build offering the free Supporter year** | Needs a build installed from TestFlight, where `AppTransaction` reports the sandbox environment. Debug builds skip the check. | If the detection is wrong, TestFlight testers see no Supporter bar, or an App Store build shows one. |

<!-- COPY END 07591ce1 -->

<!-- COPY BEGIN cf3a8fa4 [NEEDS HUMAN REVIEW] -->

## Needs something outside the app

| Proof | Why | What it costs |
|---|---|---|
| **Sending an abuse report from the app** | The addresses exist, and Griff confirmed on 2026-09-17 that mail to them arrives. A simulator has no mail account, so the report sheet's send has not been watched from a phone. | The sheet is seen and its copy checked. |
| **The report vault** | Same: it has to exist before anything can be filed in it. | Trust and safety is findable in the app and has nowhere to land. |
| **An invitation expiring at the inviter's relay** | The gate wants an inviter who stays offline past the expiry date. `--clock-ahead-days` can now move one device's clock, which may make this runnable on the rig; it has not been tried. | The expiry is enforced on the device holding the link and in the relay; only the relay half is unproven, and only for the offline-inviter case. |

<!-- COPY END cf3a8fa4 -->

<!-- COPY BEGIN 3c3ca04e [NEEDS HUMAN REVIEW] -->

## What is NOT on this page

Anything a rig *can* prove. That now includes every one-account round over real CloudKit, the whole
in-memory suite, and the three-identity triangle above the mailbox, which has been run twice. The
removal audit's third case — the non-atomic two halves of a removal surviving a crash between them —
needed a crash harness rather than a third account, and has one: `RemovalSurvivesACrashTests`.

<!-- COPY END 3c3ca04e -->
