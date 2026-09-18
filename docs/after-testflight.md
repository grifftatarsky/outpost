---
title: After TestFlight
layout: default
nav_order: 6
---

# After TestFlight

{: .no_toc }

Work that was deliberately taken off the iPhone roadmap because it waits for a build to be in
somebody's hands. Nothing here blocks TestFlight; nothing here is scheduled.

1. TOC
{:toc}

## Why this page exists

`RULED` — Griff, 2026-09-14. The roadmap is the list of what stands between the app and a
TestFlight build. Anything that does not stand between those two things makes the list read longer
and more urgent than it is, so it comes off and lands here.

The Mac and the iPad are the same ruling with their own page, because a second platform is a
product rather than a ticket: [Desktop roadmap](desktop-roadmap.md).

## Pushed out, with the reason

`RULED` — Griff, 2026-09-14, working through the roadmap ticket by ticket.

### Consensus hard delete

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

### Hard delete and desync quietly

Destroying a message on this device and letting the conversation diverge, with the other party never
told.

**Why it waits.** Same machinery as consensus delete, and it is the harder of the two to explain
honestly: the app would be knowingly letting a conversation diverge with no way to repair it. That
sentence has to be right before the feature exists.

### Clearing media older than a date

A control that clears media older than a date the member picks, showing what it would free first.

**Why it waits.** Nothing deletes itself on its own — ruled 2026-09-13 as the answer rather than a
gap — and the size is already on the You screen, so a member who wants space can see it and act.
This is convenience on top of an honest baseline.

## Devices to eventually support

Not scheduled, not designed, and not blocking anything. This is the list of things Griff has said he
wants the app to run on one day, kept so that a decision taken now against one of them is taken
knowingly rather than by accident.

| Device | Added | What it would need |
|---|---|---|
| **Mac and iPad** | 2026-09-14 | Has its own page — [the desktop roadmap](desktop-roadmap.md) — because the work is sized and sequenced. It builds and runs on a Mac today; that is not the same as being offered. |
| **iPhone Duo** | 2026-09-16 | **Not supported at this time** — Griff, 2026-09-16, while installing iOS 27. **Named by Griff, and this page deliberately does not describe it.** Nobody here has measured what the device is or what it asks of an app, so any sentence about screens, folds or sizes would be a guess dressed as a requirement. When it is real, the first job is to read Apple's guidance for it and write that here — not to infer it from the name. |

**What the app already has that helps.** Every screen is laid out in points with Dynamic Type rather
than in fixed frames, the rig already checks two phone widths (402pt and 440pt), and
`CarpenterUI` has no idea where its data came from — so a new size class is a layout question rather
than an architecture one. What it does **not** have is any notion of two displays, a hinge, or a
window that changes shape while it is open.

## Future enhancements

Named by Griff, recorded in his words, not designed. What the design called *extensions* — first-party
features switched on per room — are **Packs** (Outpost Packs) from 2026-09-16, Griff's rename.

| Enhancement | Added | As Griff put it |
|---|---|---|
| **The Bullet Pack** | 2026-09-16 | "Build bullet extension, lock to subscriber" — and the same night: call it a **Pack**, an **Outpost Pack**, "because that's more fun". It starts with the $0.99 subscribers having Bullet's shared simple list, and anyone who used the app in TestFlight gets one year of subscriber free. Built while the main app is in TestFlight. |
| **Buying Supporter** | 2026-09-17 | "12$ value, since we don't do discounts, it's just annual 12$ and monthly 1$." The TestFlight build grants the free year and the badge instead; the purchase comes with the App Store release. |
| **YubiKey support** | 2026-09-17 | "yubikey support". **Named by Griff, and this page deliberately does not describe it.** Nobody here has read what the platform offers a key over Lightning, USB-C or NFC, or which of the three things it could touch Griff means — holding the identity key off the Keychain, gating the app or a recovery, or being a second factor where this app has no first one to add to. Any sentence about which would be a guess dressed as a requirement. When it is real, the first job is to read Apple's guidance and write that here. |

## Questions for later, not decided

### Whether a member can be written into Contacts

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

## Canceled, with the reason

### An in-app lock

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
