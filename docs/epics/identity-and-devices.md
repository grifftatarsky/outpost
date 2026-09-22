---
title: Identity and devices
layout: default
parent: Roadmap
nav_order: 4
---

# Your identity across your devices

{: .no_toc }

One identity across a member's devices, and what happens when they lose them.

1. TOC
{:toc}

## Where this stands

An identity generated on first run and filed in the synchronizable Keychain; a second device adopting
it through iCloud Keychain with no setup step; a device list that says when each device arrived, with
names and revocation; sealed records between a member's own devices; erasing everything; a recovery
key that restores who you are while the people you talk to are asked for what was said; and a
reinstall that carries on as the same device. What a
simulator cannot show is two real devices on one account, which needs two phones.

Every ticket on this page, with its status and what was actually observed, is on the
[Roadmap](../roadmap.md#where-everything-stands).

## Tickets

<details markdown="1" id="one-identity-across-a-members-devices">
<summary><b>One identity across a member's devices</b> — Complete (hardware proof owed)</summary>

**Story.** As a member with two devices, I want the second to already be me, so that there is no
setup step and no second identity.

**Acceptance criteria**

- **Done.** An identity generated on first run and filed in the synchronizable Keychain.
- **Done.** A second device on the same Apple Account waits for the identity rather than offering to make
  another, then adopts it and says so once (board 70).
- **Done.** The checking screen (board 69) says what it is waiting for, what makes it finish, and after a
  minute what to check, and backs off rather than stopping.
- **Done.** A device list, and revocation that later devices honor.
- **Done.** The Mac uses the data-protection keychain, not the legacy file-based one, so a Mac and an
  iPhone are one member rather than two claiming to be.

**Testing**

- Suite: the registration ladder and revocation suites; the account check's error handling is a
  pure function with its own tests.
- Hardware only: a simulator cannot join the Keychain trust circle, so the hand-off has not been
  seen since the keychain-group fix. The waiting case has been seen on the rig; the resolving case
  has not.

**Design.** Boards 69, 70, 80.

<details markdown="1">
<summary>Record — a device trapped before recovery exists, and the signal it waits on</summary>

A device whose Apple Account has a member but whose Keychain has no key waits, correctly, because
falling through to the welcome screen is what puts two members on one account, and that failure is
silent. But the recheck ladder that was supposed to end the wait read `where state ==
.needsIdentity`, which is the one state such a device cannot be in. Nothing ever looked again. Fixed
2026-08-19.

**The signal it waits on is unreliable, which is the deeper problem.** `hasExistingMember()` asks
CloudKit whether any device ever published a feed, and a feed outlives the device that wrote it, so
an account carrying feeds from uninstalled simulators answers *yes* long after the identity's key
has ceased to exist anywhere. A DEBUG launch argument clears such an account; a member has no
equivalent, and that is what Recovery is for. A destructive escape was briefly added to the checking
screen and removed again: the only choices it can offer are "make a second member" and "erase this
one", and neither belongs in front of somebody who is merely waiting. A network error read as "this
account has nobody in it" was fixed 2026-09-01.

</details>

</details>

<details markdown="1" id="erase-everything">
<summary><b>Erase everything</b> — Complete (tested)</summary>

**Story.** As a member, I want to erase my member and everything this Apple Account holds, from
inside the app, so that leaving is mine to do.

**Acceptance criteria**

- **Done.** The last section of You in every build, red, with the nuke mark. Guideline 5.1.1(v).
- **Done.** A sheet stating what is erased and what is not, then one red button. The facts match the wipe:
  identity and every room key from this device and iCloud Keychain; every feed, packet and photo in
  flight this account holds in iCloud; history on this device, photos and clips included; other
  devices lose the identity too. Nothing from anybody else's device; rooms are not told; no undo.
- **Done.** The cloud half gates the local half: if iCloud cannot be reached, nothing local is touched,
  because a device that erases itself and leaves the account standing is the dirty account the
  whole ladder exists to survive.

**Testing**

- Device: the sheet opened and canceled 2026-09-04, and run from the sheet on alpha 2026-09-15: the
  app came back to onboarding on an empty account.

**Detail.** [Before TestFlight](../pre-testflight.md).

</details>

<details markdown="1" id="the-sibling-feed-is-written-in-the-clear">
<summary><b>The sibling feed is sealed before it is written</b> — Complete (tested)</summary>

**Story.** As a member, I want the thing the app puts in my iCloud to be unreadable by anybody who is
not me, because that is the whole claim the product makes.

**Fixed 2026-09-13.** What follows is what was wrong, because the way it survived matters more than
the fix.

**What was wrong.** `CloudKitEntrySync.send` JSON-encoded a `SiblingFeed` and wrote it to an ordinary
record field:

```swift
pending = try encoder.encode(feed)
record[Self.payloadKey] = feed as NSData
```

`record[key]` is the unencrypted subscript. `record.encryptedValues` appears nowhere in the
repository. So what protects that record is CloudKit's standard protection, which Apple holds the
keys to, and nothing of ours. With Advanced Data Protection on, PCS covers it; ADP is opt-in, and
the rig doc tells you to use accounts with it **off**.

**What is in that record.** Message bodies are safe — entries carry a `SealedPayload` sealed under a
room epoch key. What is not:

- `epochs: [HeldEpoch]` — `heldEpochs()` writes `chain.secret(for: epoch).material`, the **actual
  epoch secrets**, for every room this member is in. These are the keys that open the sealed payloads
  sitting beside them.
- `preferences: MemberPreferences` — the block list, hidden entry hashes, nicknames chosen for
  people, the display name, the Focus message, every notification setting.
- Entry envelopes — author, device, room, sequence, wall time. Already outside the seal by design, but
  here they are outside CloudKit's app-layer protection too.

**The packet path is not affected.** `PacketWire` carries `ciphertext`, `wrapValues` and
`grantValues`, all sealed by the app before they reach CloudKit. So does the share offer. This record
is the only one that hands over anything readable.

**Acceptance criteria**

- **Done.** The feed is sealed before it leaves the device: HKDF-SHA256 from the identity's two seeds with
  its own domain, ChaChaPoly over the encoded feed, and the member and the writing device as
  associated data so a record cannot be replayed into another device's slot.
- **Done.** **`EntrySync` carries `SealedSiblingFeed` and a `DeviceID`, and nothing else.** The unsealed type
  cannot reach a transport, which is a stronger guarantee than a rule somebody has to remember. The
  type change is what found both call sites in `AppSession`.
- **Done.** `InMemoryEntrySync` stores bytes rather than the struct, so a test can finally see what a
  transport would carry.
- **Done.** A test that fails on the old code. `SiblingFeedIsSealedTests.everyFieldOfAFeedIsInsideTheSeal`
  walks `SiblingFeed` with a `Mirror` and fails if any field's value is readable in the sealed bytes,
  plus named checks for an epoch secret, a nickname, the display name, a blocked person and the
  member's own id. Mutation-proven: it fails when the seal is replaced with the encoder.
- **Done.** A companion pin, `theWireFormIsCiphertextAndNothingElse`, mirrors `SealedSiblingFeed` and fails
  the moment somebody adds a second property to it — because every property of that type is written
  to a record in the clear.
- **Done.** `theFixtureActuallyFillsEveryField` fails if a field is added to `SiblingFeed` and left at its
  default in the fixture, so the leak check cannot pass vacuously for a new field.

**Why the app seals it rather than using `CKRecord.encryptedValues`.** Two reasons, both checked
against Apple's documentation on 2026-09-13.

- **Encrypted fields are end-to-end only with Advanced Data Protection on.** Apple: "When you turn on
  Advanced Data Protection, third-party app data stored in iCloud Backup and CloudKit encrypted
  fields and assets are end-to-end encrypted." Under standard protection, which is the default and
  what nearly everybody has, Apple holds the keys.
- **The CloudKit service key lives in iCloud Keychain**, and Apple is explicit that "if key material
  is lost, for example by a customer resetting their iCloud Keychain, CloudKit is unable to decrypt
  previously encrypted data." A reset keychain is precisely the case a recovery key exists for, so a
  member restoring from their key could not read their own record. The app's seal is under the
  identity, and the recovery key **is** the identity.

Nothing here is non-standard crypto. ChaChaPoly and HKDF-SHA256 are the same primitives Apple names
in its own HPKE cipher suites and the same ones the rest of this app already uses, so the export
answer does not change.

**Proved over real CloudKit, 2026-09-14:** the raw record fetched back holds no epoch secret, the
payload is exactly the ciphertext, the member's identity reopens it, a stranger's is refused, and a
second device opens it (`LiveSiblingFeedTests`).

**How it happened, because it is instructive.** The file landed on 2026-08-16 at 12:04 carrying a doc
comment: *"**What is stored is already sealed.** Entries arrive here encrypted under room epoch keys,
so this is the same opaque payload the mailbox carries."* That was **true when written** — the feed
held entries and certificates and nothing else. Seven and a half hours later, at 19:32 the same day,
`HeldEpoch` was added to `SiblingFeed`. The comment was not touched. On 2026-08-21 `MemberPreferences`
was added, and `architecture.md` was written the same day claiming the record was "sealed under a key
derived from the identity" — a **stronger** claim than the comment, and one that was never true of
any version of this code.

Nothing caught it in between: `CarpenterCloudKit` is not covered by `swift test`, and the fake at the
seam stores the struct rather than its written form, so no test could have seen it. This is the
project's characteristic defect — a green suite over an untested seam — with the added twist that a
comment which went stale the same day it was written was then promoted into a document.

</details>

<details markdown="1" id="recovery-from-a-lost-device">
<summary><b>Recovery from a lost device</b> — Complete (tested)</summary>

**Story.** As a member, I want a way back when my devices are gone, so that losing a phone is not
the same as losing everybody I have talked to.

**Acceptance criteria**

- **Done.** The key is a text file the member downloads, offered at account creation and again from You. It
  carries a header, a version, the signing and agreement seeds, and a six-character fingerprint
  printed on the file so one key can be told from another.
- **Done.** It refuses the three ways a file can be wrong, each with its own answer: not a recovery key, from
  a newer version, damaged.
- **Done.** The screen says what the key restores and what it does not. It makes you you again; it does not
  bring conversations back.
- **Done.** Social recovery is not offered. Refused on 2026-09-09 — see
  [Decisions](../decisions.md#recovery-is-a-key-you-download-and-it-is-the-only-thing-that-opens-a-backup).
- **Done.** **A key is read back.** *I have a recovery key* on the welcome screen, understated, under the
  keychain sentence — Griff's call 2026-09-13, because it is the unusual case. It opens a paste
  screen; `AppSession.restore(fromRecoveryKey:)` reads the file, puts the identity back in the
  keychain, mints a **fresh device key**, and issues this device its own certificate.
- **Done.** **History comes back from peers rather than from a backup.** The restored device holds an empty
  replica, so every `heads` entry is zero and the existing repair path asks for each feed from
  position one. Nothing new on the wire. Griff's call: identity alone "kind of defeats the point —
  you might as well have a new account, same diff".
- **Done.** A device that already has a member refuses a key rather than replacing who it is.
- **Done.** The checksum on the file is **required**, not honored when present. Cutting the CHECK line off
  used to be accepted, which defeated the one thing that catches a file mangled by copy and paste.
  Found by writing the test for it.
- **Done.** A screen for the case where an identity cannot be found and the account has one, distinguishing
  "still arriving" from "gone". 2026-09-17: nothing on the device can tell the two apart — a key that
  is still syncing and a key that will never come look the same from here — so *This Apple Account
  already has a member* says both: check that Keychain sync is on and the app will notice if the key
  arrives; if iCloud Keychain was reset or sync was never on, it will not, and a recovery key is the
  way back, with *I have a recovery key* beneath.
- **Done.** The keychain-reset case — a member who wiped their own Keychain — explained on its own. The same
  sentence, 2026-09-17.
- **Done.** **What a restore does about the member's other devices** — decided, Griff, 2026-09-13: the restore
  screen asks whether a device was lost or stolen, and a yes turns every room's key; nothing is
  revoked automatically, and an old device is revoked from the device list
  ([Decisions](../decisions.md#turning-every-rooms-key-on-a-restore-is-a-question-not-a-default)). This
  line read *undecided* until 2026-09-17.
- **Changed.** *Require verification after recovery* — replaced by Griff's ruling of 2026-09-13 that the
  **person asked** decides: *hold until I check* keeps history back until the solo check passes with
  the restored device ([Decisions](../decisions.md#recovery-is-announced-and-both-sides-of-it-have-settings)).

**When a recovery key is actually needed — confirmed by reading the code, 2026-09-13.**

The identity seeds are stored `scope: .synchronized`, which is iCloud Keychain. The device signing key
is `scope: .device`, local only. `IdentityStore.enrol()` writes an identity **only** when
`loadIdentity()` returns nil, and that is the one and only place an identity is ever written — nothing
else calls `save(_ identity:)`.

| Scenario | What happens | Key needed? |
|---|---|---|
| New phone, same Apple Account, iCloud Keychain on | The item syncs down, `enrol()` finds it, mints a fresh device key, returns `deviceIsNew: true` | **No.** This is the ordinary path and the app already relies on it. |
| One device lost, another still owned and working | Nothing to recover — the surviving device holds the identity and the keychain still has it | **No.** |
| iCloud Keychain reset, or never on and the only device gone | The item is gone from the circle; a fresh install finds nothing | **Yes.** This is the case the key exists for. |
| Signed into a different Apple Account | Different keychain, different CloudKit | **Yes**, and the rooms will not come back until peers can address this identity again. |

**A still-installed device does not put the identity back.** The app never re-writes an identity it
already loaded, so a device that is running, signed in, and holding the identity in memory will not
repopulate a reset keychain from our side. Whether **Apple** re-publishes a synchronizable item that
still exists locally into a newly created keychain circle is CKKS behavior, not ours, and it is
**not confirmed** — a simulator cannot join the Octagon trust circle, so the rig cannot test it. It
needs two real devices. Until somebody runs it, treat "the other device will fix it" as unknown.

**Testing.** `ARecoveryKeyTests` holds the file format: the round trip, the fingerprint, and each way
a key can be wrong. `RestoringFromAKeyTests` holds the restore: the same member comes back, the
device key is a **new** one, a room and what was said in it arrive from a peer that still holds them,
a device that already has a member refuses, and each of the four refusals names itself.

None of the four scenarios above is covered, because all four turn on keychain and CloudKit behavior
the suite cannot reach — and the rig cannot stage a reset keychain either.

</details>

<details markdown="1" id="recovery-settings-and-the-backfill-notice">
<summary><b>Recovery settings, and telling people a restore asked them</b> — Complete (tested)</summary>

**Story.** As somebody whose friend has just restored a lost account, I want to know they asked me for
our history, so that a device signing as them does not quietly collect everything we ever said.

Ruled by Griff on 2026-09-13 — see
[Decisions](../decisions.md#recovery-is-announced-and-both-sides-of-it-have-settings). His words: "you're
requesting to fill history you've lost which means you're asking for it — I feel like that being
silent is not great."

**Acceptance criteria**

- **Done.** **The recoverer** can choose not to ask peers for history at all. On by default; off restores the
  identity and leaves the rooms empty. `RestoreFromKeyView` asks, `restore(_:askingPeers:afterALoss:)`
  records it, and `askEverybodyForWhatWasSaid()` is gated on `wantsWhatWasSaid`.
- **Done.** **The person asked** is told: a notification naming who restored and which conversation was asked
  for. Not a setting — everybody gets it. `RestoreNotification.ofAsk`, raised from the notification
  service extension off `latestRestoreAsk()`. **It defaulted to off until 2026-09-14**, and the
  *Familiar and open* preset turned it off explicitly, so the people least likely to go looking were
  the ones not told — see
  [Decisions](../decisions.md#being-told-a-restore-asked-for-your-history-is-on-unless-you-turn-it-off).
  Twenty-three tests covered this feature and none could see it, because every fixture set the
  preference itself.
- **Done.** **The person asked** can hold: nothing crosses until the solo check passes with the restored
  device. A setting, and the default comes from the privacy check-up — *Familiar and open* leaves it
  off, *Locked down* turns it on, the walkthrough asks. `isHoldingHistoryForRestores`, and the
  check-up's `restoreAsks` / `restoreHold` pages.
- **Done.** History goes by default and waits **only** for somebody who has said to wait. The round stamps
  `RestoreAskRecord(hold: .held)` only when this member holds; everybody else gets `.allowed`.
- **Done.** The restore screen asks once whether a device was lost or stolen, and a yes turns every room's
  key. See
  [the decision](../decisions.md#turning-every-rooms-key-on-a-restore-is-a-question-not-a-default).

**No setting is needed for key exchange, and this is why.** Everything re-derives from the identity
the key restores: pairwise secrets come from this member's seeds and the other person's public keys;
rotating tags come from those; `RoomRoster.rewrapTargets` is keyed by **participant**, so peers hand
the current epoch key to a restored device on the next round without being asked; and the new device
issues its own certificate under the identity. The only thing that is a choice is the *refresh* above.

**Note the asymmetry with read receipts**, which are off whatever the preset says. Receipts are a
thing a member does to other people; this is a thing other people do to them, which is why the
check-up sets it.

**Testing.** `BeingToldAboutARestoreTests` for the notice and its default, `RestoringFromAKeyTests` for
the backfill and the recoverer's choice, and the restore that asks nobody proved over real CloudKit
(`LiveRecoveryTests`). The rig measured the ask, the notice and the hold on two accounts on
2026-09-13.

</details>

<details markdown="1" id="an-in-app-lock">
<summary><b>An in-app lock</b> — Canceled</summary>

**Story.** As a member, I want the app itself to lock, so that an unlocked phone is not an open
conversation. A stolen unlocked phone currently gives up every room in full.

**Acceptance criteria**

- **Canceled.** Canceled 2026-09-14 — iOS locks apps behind Face ID already, and does it better than this
  could: Settings › Face ID & Passcode › Require Face ID for individual apps. See
  [the roadmap](../roadmap.md#an-in-app-lock). The honesty half of the third criterion
  survives as a copy change on the Safety pages.
- **Canceled.** Locks behind the device's own biometric or passcode, on a timeout the member chooses.
- **Canceled.** Notification content respects the lock and interacts correctly with notification previews.
- **Canceled.** The lock is a lock, not a curtain: the limit stated rather than implying protection at rest
  beyond the platform's.

**Design.** Board 30, not built.

</details>

<details markdown="1" id="the-device-list-tells-the-truth">
<summary><b>The device list tells the truth</b> — Complete (hardware proof owed)</summary>

**Story.** As a member, I want the device list to say something accurate about each device, so that
it is an audit trail rather than a decoration.

**Acceptance criteria**

- **Done.** Every device says when it actually arrived. All three certified at `.distantPast`, which the
  screen drew as *here since you made this identity* — true of the founding device and claimed by
  every later one.
- **Done.** A relaunch no longer rewrites that date. `restoreLog` minted a fresh certificate on every
  launch, so *added* really meant *last launched*; it now admits the stored one and issues a new
  certificate only for a device that has none.
- **Done.** The device a member is holding is never described as never used. On a fresh install with name
  sharing off — the default — the founding device has written no entries, so the list told somebody
  *it has never been used, setup may not have finished* about the device in their hand. Found while
  writing the test above.
- **Done.** Revoking states its consequence for other people too: they stop accepting that device as the
  next time each of them syncs.
- **Done.** 2026-09-16. A device that has written nothing reaches the other device's list, reads as not
  having sent anything, and can be revoked. It used to reach nobody: it published no sibling feed
  until it wrote, and the receiver kept a lone certificate only in memory. Both fixed;
  `aSilentSiblingReachesTheList` replaces the test that pinned the asymmetry, ten runs clean.
  **Unproven across CloudKit** — the sibling feed on two real devices needs the same account on two
  phones, which a simulator cannot join.
- **Done.** The policy on one identity per Apple Account is decided, recorded, and enforced. One identity
  per account: a device whose account already holds a member stops rather than making a second, and
  since 2026-09-16 a device that cannot reach iCloud to ask waits too, on Griff's ruling
  ([Decisions](../decisions.md#a-first-launch-that-cannot-reach-icloud-waits)). A recovery key still
  restores. `ExistingRegistrationTests`.

**Testing.** `TheDeviceListTellsTheTruthTests`: the founding device's date, a second device's date
five days later, a relaunch not rewriting it, the current device never reading as unused, and the
silent sibling reaching the list and its certificate being written down. **Design.** Board 80, which is board 12 with its pairing half removed: no
six-character comparison, no setup step, a record rather than a control.

</details>

<details markdown="1" id="names-and-faces-shared-by-choice">
<summary><b>Names and faces shared by choice</b> — Complete (tested)</summary>

**Story.** As a member, I want to decide what of me other people see and what of them I see, so
that nothing about me leaves this device because I forgot to say no.

**Acceptance criteria**

- **Done.** Four switches on Privacy & Safety, in a Send group and a Receive group: *Share my name*,
  *Share my photo*, *Show others' names*, *Show others' photos*. All four start off.
- **Done.** With *Share my name* off, the name a member types stays on this device — the You screen and
  Your identity show it, nothing else does — and every room sees their short code. Turning it on
  writes the name into every room they are in, at once; turning it off again takes nothing back
  from a room that has it, and the footer says so.
- **Done.** With *Show others' names* off, every other person is their code and initials from it, wherever
  they appear — rows, transcripts, the solo picker, the greeting — even where they shared a name.
  Turning it on draws the names this device already holds; nothing is fetched.
- **Done.** A photo of your own: picked from the library through the pencil on the avatar, cropped to a
  centered square, re-encoded with every tag stripped, stored in the app's container on this device
  only; drawn on You, on Your identity and as the You tab's icon. *Remove photo* takes it away.
  Erase everything removes it.
- **Done.** *Share my photo* puts that photo where the people this member shares rooms with can collect
  it: sealed like a message photo, standing in the member's own outbox with nobody acknowledging
  it, and named by a pointer in every room — including a room joined later. A new photo replaces
  it; there is one photo and no history. Off, or the photo removed, takes it down: the pointer is
  withdrawn and the attachment deleted.
- **Done.** *Show others' photos* collects a photo somebody shares, checks it against its pointer, and
  draws it wherever they appear, under any photo this member chose for them; on their page it
  sits beside *Their name*. A withdrawn photo is let go on the next round. Off, nothing is
  collected and nothing held is drawn.

**What everybody sees with all four off**

| Who is looking at | Sees |
|---|---|
| You, at yourself | Your name and your photo, or your initials on the accent disc without one. |
| You, at anybody else | Their short code as their name, and its first two characters on a neutral disc. |
| Anybody else, at you | Your short code, the same way. |
| A solo's title | The other person's code. |

Turning on *Share my name* or *Share my photo* changes only what others *could* see; they see it
when they turn on the matching *Show others'* switch. A photo this member chose for somebody sits
over that person's shared one on every disc; the person's page shows both.

**Testing**

- Suite: `SharingTests` — name stays home until shared; receiving off hides a shared name; sharing
  off takes nothing back; a rename while not sharing writes nothing. `PhotoSharingTests` — shared
  and collected without acknowledging; replaced with one attachment and no history; taken down;
  a later room told; the sweep leaves it. `SoloTests` for the picker.
- Device: 2026-09-06 — beta's shared name arrived on alpha and titled the solo; beta turned
  *Share my photo* on, alpha collected it (70 KB, one record fetch) and drew it beside *Their name*
  under alpha's own choice, then on the disc once that choice was removed; beta turned it off and
  alpha let it go on the next round.

**Design.** No board; the layout follows iOS Settings' Privacy page. The rule in
[decisions](../decisions.md#names-and-faces-are-shared-by-choice-both-ways-and-start-off).

</details>

<details markdown="1" id="a-privacy-check-up-at-first-run">
<summary><b>A privacy check-up at first run</b> — Complete (tested)</summary>

**Story.** As a new member, I want to be asked the sharing questions once, at the start, so that the
defaults are my choices rather than my silence.

**Acceptance criteria**

- **Done.** After the name, before the rooms: a page with three doors. *Familiar and open* shares the way
  Messages does — name out, names in, read receipts; *Locked down* shares nothing; *Customize
  privacy settings*, drawn as the different kind of choice it is, goes one switch at a time.
- **Done.** Each preset opens a page showing what it looks like — how you appear to others, how they
  appear to you, what a sender sees under their message — drawn with the app's own row, disc and
  marks at their real sizes, and one button to take it.
- **Done.** The walkthrough gives every switch its own page: the explanation, a live example that flips as
  the switch does, the switch, and *Next* — name, photo and silence out; names, photos and silence
  in; read receipts; blur; the deny list; then the Solo check, the two restore questions and the four
  Outpost questions, up to sixteen pages in all, skipping any that do not apply. Then *Finish*.
- **Done.** Finishing applies the choices whole — the four sharing switches and read receipts to the
  session, blur and the deny list to this device — and the rooms list carries one quiet line for a
  while: privacy set, changeable under You › Privacy & Safety. No alert.
- **Done.** *Decide later* changes nothing and counts as asked. The check-up is asked once per member,
  never on a device that let itself in off the Keychain, and can be run again from Privacy & Safety,
  whose header now says that anything can be changed and that what was sent stays sent.
- **Done.** *Familiar and open* turns on the photo pair and the silence pair as well as the name pair
  and read receipts; *Locked down* leaves all six sharing switches off. The Do Not Disturb words
  are not a check-up question and stay as written.

**Testing**

- Suite: `PrivacyCheckupTests` — asked once and not after a relaunch; the presets' values; a preset
  applied through the session sets every switch it owns.
- Device: 2026-09-06, alpha took *Familiar and open* and its solo with beta was titled by name on
  the next screen with the quiet line under the list; beta went through the walkthrough, the
  read-receipts example flipping with the switch. The re-run row seen on Privacy & Safety.

**Design.** Undesigned. Griff's note, 2026-09-05.

</details>

<details markdown="1" id="a-name-and-a-face-of-your-own-for-somebody">
<summary><b>A name and a face of your own for somebody</b> — Complete (tested)</summary>

**Story.** As a member, I want to call somebody what I call them and see the face I chose for them,
so that a shared name is a default and not a decree.

**Acceptance criteria**

- **Done.** *People*, under the identity row on You: everybody this device shares a room with, in sections
  by initial with an index and a search, a disc where Appearance draws avatars, and the rooms
  together. Nobody can be looked up, and the empty state says so.
- **Done.** A person's page: their disc large, their name, their code; *What you call them*; a photo
  chosen from the library through the pencil on the disc, and *Remove photo*; what they shared as
  *Their name* — or *Not shown* where names are off — and *Rooms together*.
- **Done.** A nickname is drawn everywhere the person appears — rows, transcripts, the solo picker, a solo's
  title, the greeting — whether or not names are shown, and beats a shared name. It rides the
  sibling feed to this member's other devices and is never sent to anybody else.
- **Done.** A photo is drawn on every disc that has a person behind it, including a solo's row, and stays
  on this device.
- **Done.** The *Share my name* footer and the check-up page say what Griff wrote: people you write to get
  your name as the default for you, and can call you something else on their own phone.

**Testing**

- Suite: `NicknameTests` — a nickname beats a code and a shared name whether or not names are shown;
  it writes no packet; a solo is titled by it; it survives a relaunch. `PersonAvatarStoreTests`
  for the files.
- Device: 2026-09-06 on alpha — People, the page, a nickname typed and drawn in the list and on the
  solo, a photo picked and drawn on the row.

**Design.** Undesigned.

</details>

<details markdown="1" id="supporter-the-testflight-year-and-the-badge">
<summary><b>Supporter: the TestFlight year and the badge</b> — Complete (proved above the mailbox)</summary>

**Story.** As somebody testing the app, I want the free year I was promised and a way to show that I
support it, so that the people I talk to can see it if I want them to.

**Acceptance criteria**

- **Done.** On TestFlight, and in Debug builds, the You page shows the Supporter bar below the mark until
  the year is claimed. The App Store build never shows it.
- **Done.** Tapping it grants the year, then shows the thank-you page: the party popper wiggles unless
  Reduce Motion is on.
- **Done.** *Continue* asks whether to show the badge, with the member's own picture wearing it. *Show the
  badge* and *Not now* both close the sheet; neither brings the bar back.
- **Done.** A *Supporter* row under People opens a page with the year's standing, the badge switch, and what
  support pays for.
- **Done.** A shown badge reaches the people in every room the member is in, and is taken back when it is
  turned off or the year ends.
- **Open.** Seen on TestFlight: the bar appears on a TestFlight build and not on an App Store build.
- **Open.** The App Store purchase: $12 a year, $1 a month.

**Testing**

- Suite: `SupporterStandingTests` — when a year starts and ends, and which claim two devices keep.
  `SupporterBadgeTests` — the year offered only off the store, a badge reaching a peer and taken
  back, into a room joined later (mutation-checked), not drawn for a blocked person, withdrawn when
  the year runs out. `MemberPreferenceCoverageTests` covers the three new preferences.
- Rig, 2026-09-17: the whole flow on gamma (`RigChecks.testSupporter`) and the *Not now* path on delta
  (`testSupporterDeclines`). Gamma's badge collected by delta and drawn on its People list. Over the
  directory mailbox, not CloudKit.

</details>

<details markdown="1" id="a-reinstall-is-the-same-device">
<summary><b>A reinstall is the same device</b> — Complete (tested; proved on two Apple Accounts)</summary>

**Story.** As a member who deletes the app and puts it back, I want this device to carry on as
itself, so that nothing I wrote is written twice and the people I talk to see no difference.

**Acceptance criteria**

- **Done.** The device key, the room keys and the draft key are stored so that they never leave this
  device. A reinstall finds them; a new phone restored from a backup does not, and enrolls as a new
  device. An item stored before this was built is moved over in place the first time it is read.
- **Done.** The device key is stored with the member it was made for. A key made for another member,
  or one with no owner found by a member who is new to this device, is dropped.
- **Done.** The log, the state file, both sync engines' saved state and the learned list of other
  members' mailboxes are left out of backups, so a restore comes back as a reinstall does.
- **Done.** A device with its keys and no state is catching up. It writes nothing, publishes nothing,
  turns no key and cleans up no upload until it has read its own records back. The message field
  says so, a relaunch keeps waiting, and a read that fails is tried again every round. It does not
  ask for the member's name, which comes back with the records.
- **Done.** Each device keeps two records: a **summary** that stays small — its position in every
  conversation including deleted ones, room keys, certificates and removals, the people it knows,
  preferences, uploads left for others, departures already answered, and for itself which rooms have
  greeted the member, how the room list is arranged and how far each conversation has been read —
  and an **entries** record with every entry it wrote.
- **Done.** Reading them back restores all of that and the device's own entries. What other people
  wrote comes back through history repair.
- **Done.** A device that reads its own removal in the member's records enrolls as a new device.
- **Done.** A round sends an entry of this device's own only once a saved summary counts it, from
  the first round of a launch, before device sync has attached. A message held this way is drawn as
  not yet gone. A refused entries record holds nothing back.
- **Done.** Every start reads the device's own records and moves forward to anything they hold that
  the device does not. When that happens the History check says so.
- **Done.** Of two certificates for the same device key, the earlier decides, in any order.
- **Done.** Recovering onto a device whose own key survived is that device, and waits the same way.
- **Open.** Photos this device had collected are gone after a reinstall, and cannot be collected
  again once everybody has theirs.

**Testing**

- Suites: `ReinstallTests` (seventeen cases), `EarliestCertificateTests`, `TheDeviceSyncFakeTests`,
  `IdentityStoreTests`, `BackupExclusionTests`, `SiblingFeedIsSealedTests.bothRecordsAreSealed`, and
  in the app-bundle suite `KeychainTests.deviceItemsNeverLeave` and `anOlderItemIsMovedInPlace`,
  against the real Security framework. Each guard was removed in turn and a named test went red —
  twenty of twenty. Ten clean runs in a row.
- The in-memory device sync keeps each device's records across installs, refuses a write over a copy
  it never read by handing the server's copy over first, and refuses a record over the 1 MB Apple
  documents.
- Rig, 2026-09-22, on two Apple Accounts: the app deleted and reinstalled on alpha (account A). It
  found its keys and nothing else, read back both records, knew its place in two conversations and
  carried on at the next position. Quad on beta (account B) received it and logged no fork; Quad's
  next message reached it; the room's history came back. Earlier the same night a clone of alpha
  made by `xcodebuild` wrote as the same device, and alpha, launched afterwards, found its record one
  position ahead and moved forward before writing.

</details>

## Test plan

<details markdown="1">
<summary>Two devices on one Apple Account for enrollment; a third account for the rest</summary>

**Enrollment.** Fresh install on device 1; create an identity. Fresh install on device 2, same
account: it waits rather than offering a second identity, then adopts it and says so once. Rooms and
history appear without a setup step. Both send into the same room; neither forks.

**The waiting case.** Install on a device with the Keychain still delivering. The checking screen
holds rather than showing a welcome screen, and resolves without a relaunch when the identity
arrives.

**Revocation.** Revoke device 2 from device 1: device 2's later entries are refused. The revocation
survives a relaunch of device 1; a forgotten revocation leaves a removed device trusted, which is the
one direction this must never fail.

**Recovery.** Wipe device 2's Keychain: it reaches the reset explanation, not the generic wait, and
*I have a recovery key* is on that screen. The key restores the identity; what was said comes back
from the people who were there, if the member asks and if those people have not held it. Recovery
through nominated friends is **refused** — see the ruling in `decisions.md`; this line said the
opposite until 2026-09-13.

</details>

**What would falsify the epic.** Two identities on one account. A device that stays trusted after
revocation. A member who loses everything because iCloud Keychain was slow rather than empty.
