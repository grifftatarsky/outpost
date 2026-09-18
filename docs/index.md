---
title: Home
layout: default
nav_order: 1
---

# Outpost

Outpost is group messaging for iPhone with no Outpost server. A message is sealed on the phone that
sends it and left in the sender's own iCloud; the people it is for collect it from there. There is no
sign-up and no directory, and the developer runs nothing that holds a conversation.

These pages are the project's working record: how the app works, what is built, what has been
proved on real devices, and every decision along with who made it. The app has not been released.
The source is licensed under the Mozilla Public License 2.0.

It also builds and runs on a Mac. The Mac is not offered: Griff ruled on 2026-09-13 that the product
is iPhone, and the [desktop roadmap](desktop-roadmap.md) is sequenced after the iPhone beta.

## Where to start

**To understand the app**

- [Architecture](architecture.md): how a message gets from one phone to another.
- [The crypto, written down](crypto-brief.md): every key, what it is bound to, what an attacker in
  each position sees, and what has already gone wrong.
- [Who you are talking to](verification.md): invitations, the characters two people read to each
  other, and comparing codes later.
- [What an Outpost promises](outpost-privacy.md): what a member's own page guarantees and what it
  does not.
- [Trust and safety](trust-and-safety.md): blocking, reporting and screening, with no server to
  moderate.

**To work on it**

- [Testing](testing.md) and [the simulator rig](simulator-rig.md): the suites, and how anything that
  crosses the network is proved.
- [Design](design.md): where the design boards are and what they do not cover.
- `CLAUDE.md` in the repository root: the rules the lint enforces and the traps this codebase has
  fallen into.

**To see where it stands**

- [Roadmap](roadmap.md): every ticket and its status. This is the status of record.
- [Before TestFlight](pre-testflight.md) and [After TestFlight](after-testflight.md): what is left
  for the beta, and what was moved past it on purpose.
- [Proofs a rig cannot run](proofs-a-rig-cannot-run.md): what needs a third Apple Account or a phone.
- [Open questions](open-questions.md): what is unbuilt or uncertain.
- [Decisions](decisions.md): what is settled and who settled it. Read its first section before citing
  an entry.
- [Inbox](inbox.md): things noticed and deliberately parked.
- [App Store](app-store.md): the listing, export compliance and the age rating.

## How honest this documentation is meant to be

The app's whole claim is that what it says is true, so a page that overstates it does more damage
than a missing feature. Two rules follow, taken from the copy guide that governs anything a member
reads.

**Present tense means it is in the build.** Anything designed, half-built or built and unproven gets
a callout instead:

{: .unbuilt }
> Not built.

{: .unproven }
> Built, and not yet proved on two devices. This project has had code that passed every test and did
> not work over CloudKit, more than once.

**Never report an inference as a measurement.** If a number was not measured, the page says what is
known, including "not measured".

## What is built

Proved between two people on two Apple Accounts unless the [Roadmap](roadmap.md) says otherwise:

- Rooms with a shared roster, an admission policy, removal and leaving. An invitation is an offer:
  nobody is in a room until they and their inviter have read ten characters to each other.
- Solos, a conversation with one person, with their own check.
- Messages sealed under a room key, with photos, clips, captions, reactions, editing and withdrawal.
- Delivery and read marks drawn from what was observed, never from how many people are in a room.
- Outposts: a member's own page, sealed to the people they let in one at a time, with posts, comments
  and photos.
- Hiding anybody's words on your own devices, and deleting a conversation you are no longer in.
- Blocking, reporting that never carries media, a bundled list of known abusers, and on-device
  screening of sensitive photos.
- Notifications split by what rings them, with the icon's number told what to count.
- Search across conversations, message text, photos and posts.
- A recovery key, and a member's own devices kept in step through their private database.
- Repairing a history with holes in it: a device names what it is missing and asks for it.
- Comparing a code with anybody in a room, at any time after the introduction.
- The Supporter badge and a free Supporter year for beta testers.

## What is not

**Not proved yet.** Griff saw a banner arrive on a phone from another account on 2026-09-09, and
nothing since: the notification settings, the banner's details and tapping through it have not been
watched with a real push. Nothing that needs a third Apple Account, or one account on two real phones,
has been run. Each is listed on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md) with what shipping
without it costs.

**Not built.** Buying Supporter, and Packs, the features Supporters will pay for. Consensus deletion,
deleting and letting a conversation diverge, and clearing media older than a date were moved past the
beta on purpose. An in-app lock was canceled, because iOS already locks apps behind Face ID. Each has
its reason on [After TestFlight](after-testflight.md).
