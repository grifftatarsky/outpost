---
title: Home
layout: default
nav_order: 1
---

# Outpost

Outpost is a peer-to-peer messaging application, with no server behind it. A message is sealed on the phone
sending it, and left in an outbox in the sender's own iCloud storage. The people it's intended for collect it. There is no
sign-up, and no directory. The developer (me) has no access to a conversation; there are no analytics, there is no server (besides iCloud itself), there is no tracking, advertisement, algorithm—it's just an app to talk to your friends, securely and privately. 

These pages, on GitHub, seek to describe how Outpost works, the decisions made during development, and how Outpost policies and philosophy are applied and enforced.
The source is licensed under the Mozilla Public License 2.0.

Currently, Outpost is built for iOS, and macOS. It supports the iPhone, iPad, and Mac Desktops.

First-class support for the iPhone Duo is an upcoming roadmap item.

## Where to start

**Technical Documentation**

- [Architecture](architecture.md): how Outpost passes your shared content to the recipient(s).
- [Cryptographic procedure](crypto-brief.md): how Outpost secures your data.
- [Verification procedure](verification.md): how Outpost makes sure you're talking to the right person.
- [Privacy](outpost-privacy.md): Outpost's stance on privacy and how to customize it.
- [Trust and safety](trust-and-safety.md): Outpost's options for blocking, reporting, and screening.

**Status Documentation**

- [Roadmap](roadmap.md): upcoming and in-process improvements.
- [Before TestFlight](pre-testflight.md) and [After TestFlight](after-testflight.md): how to help Outpost out with development testing through TestFlight.
- [Open questions](open-questions.md): unsurprisingly, the questions the developer hasn't answered, and how they're thinking about them.
- [Decisions](decisions.md): choices made during development and why they were made.
- [Inbox](inbox.md): ideas, thoughts, unticketed/roadmapped work. Scratch. Don't take anything too seriously here.
- [App Store](app-store.md): how Outpost approaches the App Store, and documentation on all things Apple.

**Working on Outpost**  
*TODO:  Add contributor terms and agreements and a blurb about the open source license, CP, and TM.*
- [Testing](testing.md): which suite to run, how to run it against a real account, and what to drive by hand.
- [The simulator rig](simulator-rig.md): setting up the four simulators, and what a simulator can and cannot do.

## Currently supported by Outpost

### The Core Messaging System

- Group messaging, called "Rooms."
- Solos, what Outpost calls a DM. One-on-one conversations. Same key challenge options.
- All messages are sealed under the room or solo current key.
- Message formatting, photos, clips, captions, reactions, editing, and withdrawal.
- Delivery and read marks. Read is disabled by default. Delivery is not disableable.
- An unsent message is displayed with details and help, as the P2P model is slightly different from the norm.
- Deleting rooms and solos users have left.

### Encryption, Keys, and Signatures

- Every message, photo, clip, post, and comment is sealed on the writing device, with
  ChaCha20-Poly1305, before it goes anywhere. *Nothing reaches iCloud unsealed!*
- Apple's CryptoKit primitives: Ed25519 for signatures, X25519 for agreement, HKDF-SHA256 for deriving keys, HMAC-SHA256 for addressing, and
  SHA-256 for identifiers and fingerprints.
- Identity is formed from two independent seeds, one for signing, and one for agreement.
- Every entry is signed by the writing device, and every device carries a certificate signed
  by that member's identity. A lost device is revoked, without changing who you are.
- A room has a key per epoch, and the entry's canonical bytes are the associated data — so a sealed
  payload cannot be moved to another room, epoch, or writer, and still open.
- Each pair of users derives one shared secret from their own keys. Room keys are handed over
  wrapped to that secret.
- Recipients are addressed by a tag that rotates, so the same person is never a fixed name sitting
  in iCloud.
- A device sends only what its reader is allowed to read. Nobody is handed another conversation's
  messages, even sealed, and nobody is handed a copy of who you talk to. An entry's envelope names
  only the conversation it was written in.
- Every device keeps a separate log for each conversation, so nothing about what you write in one
  conversation shows in another — not even how much.
- Members vouch for each other's logs, so somebody shown a different version of a conversation than
  everyone else is found out.
- Photos and clips are sealed under their own key, separately from the message carrying them.
- Drafts are sealed on disk, under a key that never leaves the device, bound to the conversation
  they were written in.
- A user's own devices stay synced through a feed, sealed before write.
- The key challenge characters are derived from a hash over both sides' keys, with a commitment
  first, so neither side can choose their half after seeing the other's.
- Keys live in the keychain with the identity synchronized so a new phone can pick it up and that device's
  own keys never leave it. Everything on disk is written with iOS file protection.

### Advanced Invitation/Admission Settings

- Room settings for when a new member is added:
  - No approval required.
  - The room creator can approve.
  - Specific existing members can approve.
  - Any existing member can approve.
  - A set number of approvals by existing members.
  - Unanimous approval.
- For unanimous, set number, and any existing, the approving user cannot be the user who added the
  member, unless there are no other members able to approve.
- Rooms support sharing all history, or only forward history, when invites are issued.
- Key challenge for invites and checkup: ten characters, or twenty (high security, defaulted off), to confirm identity.
- Room member removal and voluntary exit, both of which rotate the room's key. Anyone who is removed or left cannot read what is
  said next. Cryptographically cut off!

### Outposts

- Outposts: serverless, simple social media.
  - Fully disableable.
  - Each enabled user has an Outpost, a page for posts, sealed to the people they allow to see it.
  - Posts have comments, reactions, and photos.
  - Outpost access for other users is fully configurable; like rooms, access can be forward-only, or full.
  - Outpost access is clear, with easy access to what another user (specifically, them) can see.
- When viewing another Outpost, all strangers are shown as a single anonymous user (with avatar and name customization). No users who have not connected directly are ever connected, and you can't tell who strangers are.

### Advanced Safety

- Any message received can be hidden with tombstones: search respects that.
- Blocking users.
- Abuse reporting system and sensitive content settings.
  - Tools create a report which is submitted through outpostmessaging.com, as not to have any API or server involved in the app.
  - The report is created, then stored in the site for review and action. Policies defined.
  - Reports never carry media or sensitive material.
  - The app includes a bundled list of known abusers, which can be turned on or off for auto-blocking.
  - Bundled-list-based app banning. Mistaken ban contact form.
  - On-device screening of sensitive photos and clips.

### Configurable Notifications

- Notifications.
  - Supports Focus filters with a shared Do Not Disturb.
  - Replying, and marking read, from push banners.
  - App badge settings to determine what the count says.
  - Configurable privacy settings and granular options here.

### Search, Pins, and Tagging

- Search. Across conversations, message text, photos and posts.
- Pinned conversations.
- Conversation tagging and filtering.

### Personalization

- Avatars and names.
  - Names and faces are shared by choice (settings).
  - A private, visible-only-to-you name and face to give another user.
- A privacy check-up which runs at first app open, and from settings.
- Recovery via key. Followed by a device list with revocation, and an option for nuking everything.
- A member's own devices are kept in step through their private database, fully synced and revocable.
- History repair. A device names what it is missing, and asks for it.

### Supporter

- Supporter tier.
  - Users who like what the developer (me) has done can become Supporters, with a 99¢ monthly sub
    available upon release. See Unsupported for in-app purchase status.
  - TestFlight users get a free year of Supporter tier.
  - Supporters get a badge on their avatar (optional).
  - No core functionality will ever be locked by this tier!

## Currently unsupported by Outpost

### Supporter and Packs

- The actual in-app purchasing of the Supporter tier.
- The Packs themselves, planned as extensions for added, non-core functionality.
  - Supporters will get access to Packs.
  - A Supporter will enable messaging Packs for the entire room or the solo they're in.
  - •bullet todo lists, shared in rooms and solos, is the first slated Pack.

### Advanced "Cleanup"

- Consensus deletion: a message taken back from everybody who has it, permanently.
- Deleting a conversation and letting it diverge.
- Clearing media older than a set, configurable date.
- Getting a history out: there is no export, no transcript and no backup but the member's own
  iCloud.

### Cryptography

- A passphrase over the recovery key file. It holds your keys as text, and anybody who opens it is
  you, permanently. Everything protecting it today is editorial: where it is shown, and what it says.
- Forward secrecy within a conversation. A room's key turns when its membership changes and at no
  other time, so a key taken off a device opens that room as far back as that device could read it.
- Post-quantum anything. Agreement and signatures are X25519 and Ed25519.

### Other

- An in-app lock separate from Face ID and the device passcode.
- Calls and voice notes, of any kind.
- Typing indicators!
