---
# COPY BEGIN beb62329 [NEEDS HUMAN REVIEW]
title: The crypto, written down
layout: default
nav_order: 13
---

# The crypto, written down

{: .no_toc }

`RULED` — Griff, 2026-09-14: **the brief, and no outside reviewer.** The reasoning is that the source
will be open, so problems surface by being read rather than by being commissioned.

This document is the thing a reader needs in order to do that reading. It is written twice over:
**In plain words** is for somebody deciding whether to trust the app, and **What actually happens**
is for somebody trying to break it. Neither is a summary of the other — the plain version leaves
things out, the technical version is where the claims are checkable.

1. TOC
{:toc}

---

<!-- COPY END beb62329 -->

<!-- COPY BEGIN 0fbbbfe6 [NEEDS HUMAN REVIEW] -->

## The honest limit, stated first

Nobody outside this project has reviewed this protocol. Being **open to inspection is not the same
as having been inspected**, and no sentence in the app, on the site, or in this document may imply
otherwise. What is true is narrower and is the whole claim: the primitives are Apple's, the
composition is this project's, the source is open, and this page describes the composition so that
the next flaw in it is findable by somebody who did not write it.

Three cryptographic failures have already happened here. **None was in a primitive. All three were
in the composition**, and all three are described in [What has already gone
wrong](#what-has-already-gone-wrong) with what each one teaches about where to look next.

---

<!-- COPY END 0fbbbfe6 -->

<!-- COPY BEGIN 7a37938b [NEEDS HUMAN REVIEW] -->

## What is Apple's, and what is ours

**In plain words.** Nothing about the mathematics is homemade. Every lock, key and signature in this
app is one Apple ships and maintains. What *is* homemade is the arrangement — which key opens what,
who is handed which one, and when. That arrangement is about a thousand lines, and it is the part
worth attacking.

**What actually happens.** Everything cryptographic goes through **CryptoKit**. Counted across
`CarpenterKit/Crypto`, the primitives used are:

| Primitive | Where | Used for |
|---|---|---|
| `Curve25519.Signing` (Ed25519) | `Identity`, `DeviceKeys` | every signature in the system |
| `Curve25519.KeyAgreement` (X25519) | `Identity.sharedSecret` | the one secret each pair of people share |
| `ChaChaPoly` (RFC 8439 AEAD) | `Pairwise`, `DeviceSeal`, `EpochChain`, `SealedPayload`, `SealedAttachment`, `Deathmark`, `SyncEngine`, `SiblingFeed` | every piece of ciphertext in the system |
| `HKDF<SHA256>` | `EpochChain`, `Pairwise`, `SealedSiblingFeed` | turning one secret into several unrelated keys |
| `HMAC<SHA256>` | `Pairwise`, `PhotoCopy` | the rotating addresses, which space is whose, and the names of photo copies |
| `SHA256` | `Identity`, `Entry`, `SealedAttachment`, `ShortAuthenticationString` | identifiers, content hashes, fingerprints |
| `SymmetricKey(size: .bits256)` | `EpochSecret.random`, `SealedAttachment.seal`, `SyncEngine.pack` | all random key material |

There is **no hand-rolled cipher, curve, hash, MAC or KDF, and no custom padding or encoding of
plaintext before sealing**. Packets and the records a member's devices write for each other are
compressed with Apple's LZFSE before they are sealed ([ruled 2026-09-27](decisions.md#what-goes-to-icloud-is-compressed-before-it-is-sealed));
this sentence said otherwise until 2026-09-28. In a packet, the words people wrote were already
sealed before compression, so what compresses is structure. There is also no injectable random-number seam in the
shipping path: `RandomSource` exists as a protocol but nothing in `Sources` outside its own file and
the test fakes refers to it, so every byte of key material comes from CryptoKit's own generator and
there is no place to substitute a weak one.

The files that are *ours* are every file in `CarpenterKit/Crypto`, plus the way `Entry`, `SyncEngine`
and `SiblingFeed` use them. (This used to name twelve files; by 2026-09-28 there were eighteen, so it
names the folder instead.)

**One thing done right that is usually done wrong.** The signing key and the key-agreement key are
**two independent seeds**, not one seed used for both. Reusing a single Curve25519 private key as
both an Ed25519 signing key and an X25519 agreement key is a common and genuinely dangerous
shortcut; this code does not take it. `Identity` carries `signingSeed` and `agreementSeed`
separately, and each is validated as its own key type at construction.

---

<!-- COPY END 7a37938b -->

<!-- COPY BEGIN 907fc48f [NEEDS HUMAN REVIEW] -->

## Who you are

**In plain words.** There is no account. When the app first runs it makes one random secret, the
recovery key, and every key that is you comes from it — there is nothing else to be. Nobody can look
you up, because there is no directory and no name to look up; the only way anyone reaches you is if
you hand them a code yourself.

**What actually happens** (since 2026-09-27). `RecoverySecret.generate()` makes 32 random bytes.
HKDF-SHA256 turns them into three seeds under separate labels: an Ed25519 identity signing key, an
X25519 agreement key, and an Ed25519 **recovery signing key**. Devices are given the first two and
the recovery key's public half; the recovery secret itself is shown to the member once and kept on no
device. Your public name commits to all three public keys:

```
ParticipantID = SHA256( "carpenter.participant-id.v2" ‖ len(signing) ‖ signing
                                                     ‖ len(agreement) ‖ agreement
                                                     ‖ len(recovery) ‖ recovery )
```

So a different recovery key is a different person: nobody holding the identity can swap in a recovery
key of their own (`TheRecoveryKeyIsItsOwnKeyTests`).

A device gets its own Ed25519 keypair, entirely separate, and its own derived name:

```
DeviceID = SHA256( "carpenter.device-id.v1" ‖ len(devicePublicKey) ‖ devicePublicKey )
```

So a `ParticipantID` is a commitment to both of your public keys, and a `DeviceID` is a commitment
to one device's signing key. Neither can be claimed by anyone who does not hold the matching private
key, because everything they appear in is signed.

**The split matters.** *You* sign only two things: a device's certificate and a membership
attestation. Everything else — every message, every post, every acknowledgment — is signed by a
*device*. That is what makes losing a phone survivable: the device's authority can be revoked
without the person's identity changing.

---

<!-- COPY END 907fc48f -->

<!-- COPY BEGIN aed4d113 [NEEDS HUMAN REVIEW] -->

## Your devices, and how one is disowned

**In plain words.** Each of your phones gets its own key, and you sign a small certificate saying
"this one is mine". If you lose it, you sign a second note saying "not any more, as of this moment".
Anything it signed before that moment still counts; anything after it does not.

**What actually happens.** `DeviceCertificate` binds `(participant, device, devicePublicKey,
issuedAt)` and is signed by the identity key. `DeviceRevocation` binds `(participant, device,
revokedAt)` the same way. `DeviceRegistry` holds them and answers one question:

```swift
public func isAuthorized(_ device: DeviceID, at instant: Date) -> Bool {
    guard let enrolment = devices[device] else { return false }
    guard instant >= enrolment.issuedAt else { return false }
    guard let revokedAt = enrolment.revokedAt else { return true }
    return instant < revokedAt
}
```

Three properties are worth naming because each is a decision:

- **Authority is an interval, not a flag.** An entry is checked against the registry *at the entry's
  own `wallTime`*, in `Replica.integrate`. Revoking a device does not retroactively invalidate what
  it said before the revocation, which is what stops a lost phone from erasing a year of
  conversation.
- **Revocation only ever moves earlier.** `revoke` takes `min(existing, new)`, so a second
  revocation cannot be used to *widen* a device's window.
- **A certificate cannot be swapped.** `admit` refuses a certificate for a `DeviceID` already known
  under a different public key (`CryptoError.deviceMismatch`), so re-enrolling the same name with
  new keys is rejected rather than silently accepted.

**Known weakness, named.** Authority is judged against a timestamp *the signing device itself wrote*.
A malicious device that is about to be revoked can date its entries before its own revocation and
they will verify. The mitigation in the product is that the sibling feed and the log make the
back-dating visible rather than preventing it, and that removing the device rotates the room keys and seals the new ones only to the member's
remaining devices, so it stops reading anything *new* regardless of what it claims to have written. This is the classic distributed-clock problem and it is not solved here; it is
bounded.

**Each device also has a key for receiving** (since 2026-09-26). `DeviceKeys.agreementKey` is an
X25519 key derived from the device's signing seed with HKDF, so it lives only where the signing key
does. Its public half is in the certificate as `agreementKey`, appended to the signed fields only
when present, so every older certificate signs exactly the bytes it always did
(`PerDeviceKeysTests` pins it). A device's certificate from before this is re-issued with the same
`issuedAt`, and `DeviceRegistry` accepts the replacement only when the date matches.

**A device other than the first is approved by another device** (since 2026-09-26). Its certificate
names `approvedBy` and carries `approval`, a signature by that device's key over the same bytes the
identity signs. `DeviceRegistry` replays certificates and removals in time order: a certificate
counts if it has no approver (the first device, or one restored with the recovery key) or if its
approver counted at the certificate's date. A removal names `revokedBy` and is signed by that device
too, and counts only if that device counted at the removal's date. Order of arrival doesn't matter
(`DeviceApprovalTests`).

**Only the recovery key or an approval makes a device count** (since 2026-09-27). A certificate
signed by the identity alone never counts, so holding the identity, which every approved device has,
lets nobody in. The first device's certificate is signed by the recovery key when the identity is
made. A certificate signed by the recovery key is a new root: the root is the recovery-signed
certificate with the latest date *it* carries (the member's recovery key signed that date, so nobody
else can move it), and only devices whose approvals lead back to the newest root count. Every device
from an older root stops counting at the new root's date, including anything a thief added. Replaying
an old recovery certificate, or one published late, changes nothing, because its date is older
(`DeviceApprovalTests`, `WhatTheRegistryCountsTests`).

**Approvals and removals count in the order iCloud first stored them** (since 2026-09-27). Until then
the registry ordered them by the dates their authors wrote, and a removed device that keeps the
identity key could date an approval, or removals of the member's other devices, before its own
removal (measured 2026-09-26). Now every approval and removal is also written to the member's zone as
its own record, named `authority-<writer>-<digest>`, where the digest is SHA-256 over the event's
signed fields and signatures. CloudKit stamps `creationDate` when a record ID is first saved and keeps
it when the record is rewritten; a record deleted and saved again gets a new, later one. That is
Apple's documentation for `CKRecord.creationDate`, and `iCloudKeepsTheFirstStoredTime` measures it
on the rig. Because the name is the digest, a record rewritten with other contents keeps its old time
but is refused when opened.

`DeviceRegistry` replays events in stored-time order. An approval counts only if its approver counted
at that stored time; a removal counts only if it names a device, never the identity key alone, that
counted at that stored time. Learning an earlier stored time moves an event earlier; a later
sighting never moves it later. A device times its own new approval or removal after everything it has
already seen, then takes iCloud's time once its record is stored; a new device starts from its
approver's times. Other members order a member's approvals and removals by when the packet carrying
them was last stored (`modificationDate`, which a rewrite can only move later), and keep them across
a relaunch. The claimed dates still bound which entries a device may sign. Tested in
`WhatTheRegistryCountsTests`, `WritingOldDatesIntoICloudTests` and `RemembersRemovalsTests`, and live
in `LiveSiblingFeedTests`.

**What a removed device wrote** (since 2026-09-28). A removal names the last entry of that device's
feed that the removing device held, by number and hash (`cutoff` and `head`, signed only when
present). Nothing past it counts, whatever date it carries. A second entry under a number already
filled is refused, and one that reached a device before the removal did is taken back when the
removal arrives (`ARemovedDeviceStopsAtTheCutoffTests`). An entry under a number that only another
room used cannot be checked yet. The room chain Griff ruled for on 2026-09-28
([Decisions](decisions.md#a-removed-persons-words-stop-where-the-removal-saw-them)) closes it for a
person removed from a room, not yet for a removed device
([an open question](open-questions.md#what-is-left-of-a-removed-persons-reach-into-a-rooms-past)).

What it does not stop: anything a device does before its removal reaches iCloud; and a device still
signed in to the Apple Account deleting records, which delays the member's other devices hearing of a
removal (erasing it with Find My signs it out). A removed device can no longer add a device of its
own: the identity alone lets nobody in.

**How a new device gets in.** It writes a `request` record holding only its two public keys, the one
record in the zone that isn't sealed, because the device doesn't have the identity yet. The approving
device answers with an `approval` record: the identity seeds, the certificates and the removals,
sealed to the new device's receiving key with `DeviceSeal`. The six-character code both devices show
is derived from the request's public keys (`DeviceRequest.code`).

---

<!-- COPY END aed4d113 -->

<!-- COPY BEGIN 307b3aab [NEEDS HUMAN REVIEW] -->

## The one secret each pair of people share

**In plain words.** For every person you talk to, your two phones work out a shared secret between
them, without ever sending it. Nobody else can compute it — not the relay, not Apple, not another
member of the same room. Almost everything else in the app hangs off that secret.

**What actually happens.** `PairwiseSecret.derive(mine:theirs:)` is X25519 followed by HKDF:

```swift
let shared = try mine.sharedSecret(with: theirs)
let ids = [mine.id.rawValue, theirs.participantID.rawValue]
    .sorted { $0.lexicographicallyPrecedes($1) }
let key = shared.hkdfDerivedSymmetricKey(
    using: SHA256.self,
    salt: Data(Domain.pairwiseSecret.utf8),
    sharedInfo: CanonicalBytes.payload(domain: Domain.pairwiseSecret, fields: ids),
    outputByteCount: 32)
```

The two `ParticipantID`s are **sorted** before going into the `sharedInfo`, which is what makes both
sides derive the same value without either being "first". The raw ECDH output is never used
directly — it goes through HKDF with a domain-separated salt, which is correct and is the step most
often skipped.

From that one 32-byte secret, these are derived, each under its own domain string so that none of
them can be used to attack another (checked against `Pairwise.swift` and `PhotoCopy.swift`,
2026-09-28):

| Derived thing | Construction | Purpose |
|---|---|---|
| `recipientTag(window:for:)` | `HMAC-SHA256(key, "…recipient-tag.v1" ‖ window ‖ recipient)` | the rotating address a packet is left under |
| `pairHint` | `HMAC-SHA256(key, "…pair-space.v1")` | which of your spaces is for which person |
| `PhotoCopyName(of:between:)` | `HMAC-SHA256(key, "…photo-copy-name.v1" ‖ photo)`, first 16 bytes hex | the name of that person's copy of a photo, and of their receipt for it |
| `wrap` / `unwrap` | `ChaChaPoly` with the key directly, caller-supplied associated data | epoch grants, packet keys, receipts, room-entry links, photo copies and their labels |

**The hidden address changes when a device is removed** (since 2026-09-27). Every device you approve
holds your `agreementSeed`, and a device you later remove keeps it, so the secret above can be worked
out by it for good. Removing a device now also gives you a new **address salt**: 32 random bytes kept
in this device's own keychain (never the synchronized one, which reaches every device on the Apple
Account) and handed to your other devices only sealed to each of them (`SiblingMail`). The secret
every packet travels under becomes `PairwiseSecret.derive(mine:theirs:mySalt:theirSalt:)`: the same
X25519 output, through HKDF under its own domain (`carpenter.pairwise-address.v1`), with both people's
current salts in the `sharedInfo`, sorted by participant. Nobody with a salt means the old derivation,
byte for byte (`AnAddressOnlyYourDevicesKnowTests`).

Your contacts hear of it from an `AddressAnnouncement`: the salt sealed to each of *their* devices
that counts (`DeviceSeal`), signed by one of yours, and adopted only if that device counted when
iCloud stored the announcement, and only if it was stored after the one they already hold. So a
removed device can't announce an address of its own, even one it signed before it was removed, and
an old announcement delivered again can't take the address back. The announcement travels under the
old secret, with your device certificates and removals in the same packet, and is sent again until
the contact signs for it. For nine days after a change both sides still listen at the old addresses,
so nothing written in between is lost, and everyone always listens at the original one, so a contact
meeting you for the first time, or a device restored from the recovery key (which starts a new salt),
can always reach you (`ChangingYourHiddenAddressTests`, every guard mutation-checked).

**What a removed device can still do.** It can't work out the new addresses or open anything written
under them. It can see, once per change per contact, that an announcement was left (it goes under the
old address), read what was written under the old addresses during the nine days, and write junk under
the original address that your devices collect and refuse. If it is still signed into your Apple
Account it can also see how much you write, in your own outbox, without knowing to whom. A comment
sealed for a wall's owner stays under the original secret, because it is kept in the log for good.
This is stated again under [the recovery key](#the-recovery-key-is-a-skeleton-key-shown-once).

---

<!-- COPY END 307b3aab -->

<!-- COPY BEGIN 754a4244 [NEEDS HUMAN REVIEW] -->

## The room key, and the chain behind it

This is the least conventional part of the design and the part most worth attacking.

**In plain words.** Every room has a key. When somebody leaves or a phone is lost, the room's key
is rotated, and from that moment the old key opens nothing new. But old conversations must still be
readable — that is the entire point of an app where history lives on your own phone — so each new
key carries a sealed copy of the one before it. Hold today's key and you can walk backwards through
the whole conversation. That is a feature. It is also the biggest trade-off in the app, and it is
described honestly below.

**What actually happens.** A room has an ordered series of `EpochSecret`s, each a fresh 256-bit
random value. `EpochChain.advance` creates the next one and, crucially, wraps the **previous**
secret under a key derived from the **new** one:

```swift
let epoch = previousEpoch.next
let secret = EpochSecret.random()
let sealed = try ChaChaPoly.seal(
    previous.material,
    using: wrappingKey(for: secret, room: room, epoch: epoch),   // derived from the NEW secret
    authenticating: link.context)                                 // domain ‖ room ‖ epoch
```

That sealed blob is an `EpochLink`. Recovering an older secret is a walk *down* the links:

```swift
var current = try requireSecret(at: start)   // the lowest known epoch ABOVE the target
var cursor = start
while cursor > epoch {
    guard let link = links[cursor] else { throw CryptoError.unknownEpoch }
    let key = Self.wrappingKey(for: current, room: room, epoch: cursor)
    // …open link.wrapped…
    current = EpochSecret(material: opened)
    cursor = cursor.previous!
}
```

Two separate keys come off each epoch secret, each with its own HKDF domain — `…epoch-wrapping.v1`
for unwrapping the link, `…epoch-sealing.v1` for opening messages — with `(room, epoch)` bound into
the `info`. So an epoch's message key cannot be used as its link key, and an epoch's keys are useless
in another room even if the secret somehow escaped.

<!-- COPY END 754a4244 -->

<!-- COPY BEGIN 4684735d [NEEDS HUMAN REVIEW] -->

### Three properties this shape gives you

- **Post-compromise security: yes.** Knowing epoch *N* tells you nothing about epoch *N+1*. The link
  at *N+1* is sealed **under** *N+1*'s key, not *N*'s, and *N+1* is a fresh random value distributed
  only through pairwise-wrapped grants. Rotating the key after a loss genuinely shuts the old holder
  out of everything said afterwards.
- **Forward secrecy: no, deliberately.** Whoever holds the current secret and the links holds the
  entire history of the room. There is no point in time before which a compromise is harmless. This
  is not an oversight — an app whose promise is that your history lives on your friends' phones
  cannot also promise the keys to it are destroyed.
- **Bounded history is a real mechanism, not a policy.** Because the walk stops the moment a link is
  missing, handing somebody epoch *N*'s secret plus only the links down to *K* lets them read *K…N*
  and **nothing below K, cryptographically**. That is how "a period you close can be opened again,
  and what falls between stays sealed to them" is implemented. The app is not filtering what it
  shows; the reader genuinely cannot derive the key. Sharpest single idea in the codebase.

<!-- COPY END 4684735d -->

<!-- COPY BEGIN 5aa0f0f6 [NEEDS HUMAN REVIEW] -->

### Handing somebody a key

`EpochGrant.issue` wraps an epoch secret under a **pairwise** secret, with `(room, epoch)` as the
associated data, and carries the links alongside:

```swift
links: links.filter { $0.room == room && $0.epoch != link?.epoch },
wrapped: try peer.wrap(secret.material, context: Self.context(room: room, epoch: epoch))
```

`adopt` refuses a grant for the wrong room before opening it. The filter on `links` is the access
boundary in code form — whatever is left out of that array is history the recipient cannot reach.

The pairwise-wrapped secret is sealed again to each of the recipient's devices that counts and has a
receiving key (`DeviceSeal`: a fresh X25519 key, HKDF-SHA256, ChaChaPoly, with the room, epoch and
device bound in), and the plain pairwise copy is left empty. Opening needs the pairwise secret and the
device key, so a removed device, which still has the identity, gets nothing. A grant with no device
seals is never sent and is refused if one arrives (since 2026-09-27; until then a recipient with one
device lacking a receiving key got a copy anybody with the identity could open). A device that finds
a grant sealed only for its siblings passes it on to them (`ForwardedGrant`).

**A grant is signed by the device that sent it** (since 2026-09-27). Until then nothing in a grant
said which device sent it: it was only wrapped under the pairwise secret, which comes from the
identity, so a removed device, which keeps the identity and the old room keys, could write a newer
room key "from" its member to any friend, or "from" a friend to its member, into any zone its Apple
Account can write to. The friend took it as the room's newest key and everything written afterwards
was readable by the removed device. Now the sending device signs the grant over both people, itself,
the room, the epoch and every sealed copy (`EpochGrant.signed`), and the recipient takes it only if
that device counted in the sender's registry when iCloud stored the packet
(`EpochGrant.isSigned`, `ARemovedDeviceCannotHandOutKeysTests`). What it does not stop: a friend who
has not yet heard of the removal still takes a key the removed device signs; a removed device still
signed in to the Apple Account can delay the news by deleting records.

Grants also travel sealed to their recipient under the pairwise secret now; before, each grant sat
in the packet record as JSON with its room and epoch in the clear.

**Known weakness, named.** A grant's `links` array is the *only* thing standing between a reader and
the whole room. It is a list somebody has to get right, in a filter, in one place. There is no
second check downstream asking "should this person be able to read that far back?" — by the time the
links are in their chain, the answer is yes and cannot be withdrawn. **This is the single highest-value
line in the codebase to audit**, and the failure mode is silent: too many links is not an error
anywhere, it is a reader who can see more than intended and no log line anywhere says so.

**Known weakness, named.** Two members advancing the same room's epoch at the same moment is
untested and genuinely needs three real accounts to exercise — it is on
[Proofs a rig cannot run](proofs-a-rig-cannot-run.md). If rival advances resolved differently on
different devices, members would hold different secrets for the same epoch number and messages would
stop opening for somebody, with no error that names the cause.

---

<!-- COPY END 5aa0f0f6 -->

<!-- COPY BEGIN 8c1d2503 [NEEDS HUMAN REVIEW] -->

## Sealing what somebody actually wrote

**In plain words.** A message is locked with the room's current key before it leaves your phone, and
what it is locked *to* is baked into the lock: this room, this key, this author's device. Move it
anywhere else and it will not open — not "opens to nonsense", but refuses.

**What actually happens.** `Payload.sealed(at:using:by:alsoFor:)` is JSON with sorted keys, sealed
with `ChaChaPoly` under the epoch's sealing key, with this as associated data:

```
context = "carpenter.sealed-payload.v1" ‖ room ‖ epoch ‖ [author ‖ device]
```

The AEAD binding is the part to check. The `epoch` number travels in the clear inside
`SealedPayload`, so a tamperer can change it — but the reader uses that same number both to *choose
the key* and to *build the associated data*, so an altered epoch yields the wrong key and an
authentication failure rather than a decryption. Likewise the author and device are bound in, so a
ciphertext cannot be replayed as if written by somebody else.

**Two readers, two ciphertexts.** `alsoFor` seals the *same plaintext a second time* under a
pairwise secret. It is used for one case in the app: commenting on somebody's Outpost when you are
not inside that wall's epoch. Your own devices read the room-key copy, the wall's owner reads the
pairwise copy, and the two ciphertexts share no key. This is the safe way to do it — no key is used
twice, no nonce is reused — and the small cost is that the message travels twice.

**Assumption named.** Every message in an epoch is sealed under **the same key** with a **random
96-bit nonce**, which CryptoKit generates per seal. Random nonces under a fixed key are safe up to
the birthday bound; at 2³² messages in a single epoch the probability of a repeat is on the order of
2⁻³³. A room would have to send four billion messages without a single key rotation to approach it. Not
a concern, but it is an assumption rather than a guarantee, and it would stop being safe if epochs
were ever made long-lived and high-volume at once.

---

<!-- COPY END 8c1d2503 -->

<!-- COPY BEGIN 3be1484d [NEEDS HUMAN REVIEW] -->

## Signing what was written, and why the order matters

**In plain words.** Every entry carries a signature from the device that wrote it. Change one byte —
the time, the room, a single character of the sealed text — and the signature stops matching. There
is no way to put words in somebody's mouth.

**What actually happens.** `Entry.signingPayload` is canonical bytes over
`(author, device, seq, previous?, clock, wallTime, room?, payload)`, signed with the **device's**
Ed25519 key. Since 2026-09-28 an entry in a room also signs a **room link**, appended last and only when
present (`"room-link" ‖ hash of this device's last entry in the room`, empty for its first), so an older
entry signs exactly the bytes it always did. A removal or a departure names the last entry of each of
the person's devices, and only the chains those reach count (`RoomChains`, `TheRoomChainTests`). Written
in a session without a compiler; not yet built. Two things about this are worth stating precisely because they are the questions a
reviewer asks:

- **It signs the ciphertext, not the plaintext** — encrypt-then-sign. On its own that would leave a
  gap, because a signature over ciphertext does not by itself say the signer knew the plaintext. The
  gap is closed from the other side: the AEAD's associated data *already* binds the ciphertext to
  `(room, epoch, author, device)`. So the ciphertext names its author, and the signature names the
  same author, and neither can be moved to the other's position. The binding is mutual, and it is
  worth understanding that it is mutual — remove either half and it breaks.
- **`hash` covers the signature too**: `SHA256("…entry-hash.v1" ‖ signingPayload ‖ signature)`. So
  `previous` chains over a specific *signed* entry, and an entry cannot be re-signed into the same
  position. Forks at the same `(feed, seq)` are detected in `Replica.integrate` rather than
  silently resolved.

Verification happens in exactly one place, and it is worth reading in full because everything
downstream trusts it:

```swift
guard let registry = registries[entry.author] else { throw LogError.unknownParticipant }
guard registry.isAuthorized(entry.device, at: entry.wallTime),
    let deviceKey = registry.signingKey(for: entry.device)
else { throw LogError.unauthorizedDevice }
guard try entry.hasValidSignature(from: deviceKey) else { throw LogError.badSignature }
```

**A property worth stating plainly, because people assume the opposite.** This app is
**non-repudiable by design**. Every entry carries a signature that cryptographically proves which
device wrote it, and those entries sit on other people's phones. Signal deliberately provides
deniability; this does not, and it cannot, because the same signatures are what make a
serverless log safe to merge. Anybody in a room can prove what you said in it. That is the correct
trade for this architecture and it should never be described as if it were not.

---

<!-- COPY END 3be1484d -->

<!-- COPY BEGIN 2523f808 [NEEDS HUMAN REVIEW] -->

## The bytes everything is signed and sealed over

This file is forty lines long and has caused more damage than any other in the project.

**In plain words.** Before anything is signed or locked, its parts are laid out in a fixed order with
their lengths written down first, so that "AB" + "C" can never be mistaken for "A" + "BC". Get that
layout wrong by one byte and every message ever written stops opening.

**What actually happens.**

```swift
public static func payload(domain: String, fields: [Data]) -> Data {
    var out = Data()
    let tag = Data(domain.utf8)
    out.append(bigEndian(UInt32(tag.count)))
    out.append(tag)
    for field in fields {
        out.append(bigEndian(UInt32(field.count)))
        out.append(field)
    }
    return out
}
```

Every field is length-prefixed, big-endian, and every structure begins with its own domain string —
there are **twenty-four** distinct domains in `Domain`, one per construction. That is the right
shape and it is applied consistently.

**The trap, which has already been sprung.** `CanonicalBytes.optional` emits a **presence byte**:

<!-- COPY END 2523f808 -->

<!-- COPY BEGIN 0d446b56 [NEEDS HUMAN REVIEW] -->

```swift
public static func optional(_ value: Data?) -> [Data] {
    guard let value else { return [Data([0])] }
    return [Data([1]), value]
}
```

That is correct for a field that has *always* been there and catastrophic for one being *added*,
because `optional(nil)` is one field rather than none — so adding an optional field silently changes
the encoding of every existing value. Two were added to `SealedPayload` and every entry on every
device stopped opening and stopped verifying at once. `SealedPayload.canonicalBytes` now appends
only when present:

```swift
var fields = [epoch.canonicalBytes, ciphertext]
if let alsoFor { fields.append(alsoFor) }
```

**The rule that follows, and it binds anything added later:** in a canonical form that already has
values in the wild, an optional field is **absent**, never marked-absent. A round-trip test proves
nothing here, because it seals and opens with the same build — `SealBindingTests` pins the old
layout by writing it out by hand, and that is the only kind of test that can catch this.

**Closed 2026-09-15, and worth reading for how rather than that.** `FeedKey.canonicalBytes` is a bare
concatenation with **no length prefixes**:

```swift
var canonicalBytes: Data { author.rawValue + device.rawValue }
```

<!-- COPY END 0d446b56 -->

<!-- COPY BEGIN b714b1c4 [NEEDS HUMAN REVIEW] -->

This is currently unambiguous only because both are SHA256 digests and therefore always 32 bytes.
But `ParticipantID(rawValue:)` and `DeviceID(rawValue:)` are **public initializers taking arbitrary
`Data`**, so the fixed width is a convention rather than an invariant. Nothing in the shipping path
constructs one at another length; nothing prevents it either. Since `FeedKey.canonicalBytes` feeds
the vector clock's canonical bytes and the sealed payload's associated data, a variable-length
`ParticipantID` would open an encoding-ambiguity gap. Closed by **validating on decode** rather than by changing the encoding. Decoding is where bytes this
process did not write arrive, and it costs nothing — whereas length-prefixing `FeedKey` would
invalidate every signature and every seal in existence for no additional guarantee, which is exactly
the class of change that broke the whole app once before. `ParticipantID` and `DeviceID` now refuse
anything other than 32 bytes at the boundary, the container shape is unchanged, and a test pins that
shape so the encoding side cannot drift away from it silently (`IdentifierWidthTests`).

---

<!-- COPY END b714b1c4 -->

<!-- COPY BEGIN 91adb9e0 [NEEDS HUMAN REVIEW] -->

## Addressing somebody without naming them

**In plain words.** A message is left in a numbered pigeonhole rather than one with a name on it, and
the number changes every day. Whoever runs the pigeonholes cannot tell who any of them belongs to, or
that today's number and yesterday's are the same person.

**What actually happens.** A packet is addressed by a `RecipientTag`, which is a full 32-byte
HMAC-SHA256 under the pairwise secret over `(window, recipient)`. The window is the day:

```swift
public static let tagWindow: TimeInterval = 86_400
public static func window(at instant: Date) -> UInt64 {
    UInt64(max(instant.timeIntervalSince1970, 0) / tagWindow)
}
public static let windowLookback: UInt64 = 7
```

A device looks under its last eight windows plus one ahead, so a packet left while a phone was off
for a week is still found, and clock skew in either direction is tolerated.

**This is the single most consequential structural fact in the app.** Because a packet is addressed
by a tag and never by an Apple Account, two whole `AppSession`s pointed at one zone in **one**
account exercise a complete round over real CloudKit. That is what made 29 live integration tests
possible and retired thirteen rows that had been marked unprovable for a month.

**Known weakness, named.** The window is a **day**. Within one day, every packet addressed to a
given person carries the same tag, so the relay — and anybody who can see the zone — can group a
day's traffic to one unnamed recipient and count it. It cannot say *who*, and it cannot link across
days, but the daily grouping is real and is the price of the eight-window lookback that makes
delivery reliable.

---

<!-- COPY END 91adb9e0 -->

<!-- COPY BEGIN 1d459d56 [NEEDS HUMAN REVIEW] -->

## What the relay is actually handed

**In plain words.** The mailbox in the middle holds sealed envelopes with numbers on them. It can
count them, see how big they are, and see when they arrive. It cannot open one, and there is nothing
readable in it to open.

**What actually happens.** `SyncEngine.pack` generates a fresh 256-bit content key per packet, seals
the body under it, and wraps *that key* separately for each recipient under their pairwise secret —
with the packet's own UUID as associated data, so a wrap cannot be lifted into another packet:

```swift
let contentKey = SymmetricKey(size: .bits256)
let context = wrapContext(id: id)                         // domain ‖ packet UUID
let sealed = try ChaChaPoly.seal(try JSONEncoder().encode(body), using: contentKey,
                                 authenticating: context)
for peer in peers {
    wraps[peer.outgoingTag(window: window)] = try peer.secret.wrap(
        contentKey.withUnsafeBytes { Data($0) }, context: context)
}
```

Note `grants` is `[RecipientTag: [Data]]` — a **list** per address, not a single value. It was a
plain dictionary once, so a round owing one person keys to two rooms delivered the last and dropped
the rest, and then marked every owed grant issued because *a* packet had been written. Anything else
addressed per peer has to be a list too.

**Where a packet is written** (since 2026-09-27). Into the sender's own space for one recipient: a
zone in the sender's iCloud, shared read-only with that recipient's account alone. The record
(`PacketWire.fields`) carries exactly: the packet UUID, the recipient's tag, the wrapped key, the
sealed body, and the grant tags and values. **What that leaks, stated plainly:**

- That this sender writes to this reader. The share names the reader's account, and Apple holds
  every share list.
- Roughly how much was said (the ciphertext's size), when it was written, and when the reader
  collected it, because the reader's receipt appears in the reader's own space for the sender.
- That one photo probably went to several people: the copies are written in one operation, at the
  same moment, and are the same size. Since 2026-09-28 they share nothing else: each copy is sealed
  again for its pair and named from the pair's secret, and no field names the photo
  ([Photos and clips](#photos-and-clips)). Written in a session without a compiler; not yet built.
- The pair's `hint`, a keyed hash of the pair's secret, which is the same in the two people's spaces
  for each other. Apple can already match those two spaces from their share lists, so it adds
  nothing.
- The ring, sixteen random bytes rewritten when a round leaves something that should ring. It tells
  Apple a message was left, which the packet's own time already does.

**Receipts, in the reader's own space.** A reader never writes into the sender's space; iCloud refuses
it (measured on the rig 2026-09-27: adding, changing and deleting a record and changing the share
were all refused). The reader's device signs a receipt and seals it to the sender under the pairwise
secret (`PacketReceipt`), and writes it into the reader's own space for the sender. The sender keeps
its own record of who each packet was for, and a digest of what it wrote, and takes a packet back
only once a device of the reader that still counts has signed for it, or the packet has outlived the
address lookback (`TamperedPacketTests`, `NothingIsSnatchedTests`).

**Photos the same way.** A photo's copy for each recipient sits in the sender's space for them. The
reader signs for it with an `AttachmentReceipt`, the same shape as a packet receipt under its own
domain (`carpenter.attachment-receipt.v1`). A receipt counts only if it was written after the copy it
answers, so a copy sent again is not cleared by an old receipt (`NobodyButTheSenderClearsAPhotoTests`).

**Who may say where a person is read.** A link to a space counts only if a device of that person that
still counts sent it; a contact is read only from accounts such links name, and a space names the
account in the newest one. A stolen device can move that name to its own account while it still
counts, and removing it moves it back
([accepted by Griff](decisions.md#a-stolen-device-can-redirect-your-contacts-until-you-remove-it),
`WhoCanTellYouWhereToReadSomebodyTests`).

It does not leak any participant identifier, any room identifier, any device identifier, or any
plaintext. **Nothing readable is written with `record[key]`**: every field is sealed except the pair
hint, which is a keyed hash, and the ring, which is random bytes. The rule in `CLAUDE.md` exists
because it was broken once, and that is the next section.

---

<!-- COPY END 1d459d56 -->

<!-- COPY BEGIN 109ba01f [NEEDS HUMAN REVIEW] -->

## Photos and clips

**In plain words.** A photo is sealed with a key of its own before it leaves, and that key travels
inside the sealed message. The relay sees a blob of a certain size. Before the photo is opened, its
fingerprint is checked, so a substituted file is refused rather than decoded.

**What actually happens.** `SealedAttachment.seal` generates a fresh 256-bit key per attachment,
seals under `ChaChaPoly` with the attachment's UUID as associated data, and returns an
`AttachmentReference` holding the key, a **SHA256 of the ciphertext**, and the byte count. That
reference travels inside the sealed message body; the ciphertext travels separately. Opening checks
the digest before it touches the ciphertext:

```swift
guard matches(ciphertext, reference) else { throw AttachmentError.digestMismatch }
```

Size caps are enforced before sealing: 12 MB for an image, 287 MB for a video, which is sealed in 16 MB pieces.

**Each person's copy is sealed apart** (since 2026-09-28, [ruled by Griff](decisions.md#a-photo-is-copied-for-each-person-it-goes-to-and-each-copy-is-sealed-apart)).
The sealed photo is copied into the sender's space for each person it is for, and each copy is
sealed again under the pair's original secret (`PhotoCopy.seal`: `ChaChaPoly`, with the photo's
number bound in under `carpenter.photo-copy.v1`). The copy's record is named from the same secret
(`PhotoCopyName`), and the only other field that says which photo it is, the label, is the photo's
number sealed under that secret with the copy's name bound in (`carpenter.photo-copy-label.v1`), so a
label moved onto another copy does not open. The reader's receipt for the copy is named after the
copy, not the photo. So two people's copies of one photo share no bytes and no name, and nothing
written to iCloud carries the photo's number (`PhotoCopiesAreSealedApartTests`). The pair's original
secret is used, not the address secret that changes when a device is removed, because the copy
needs only to be unlinkable, not secret: the photo's own key travels inside the room.

Opening checks the digest first: bytes that already match it are taken as they are, which is how a
photo from the old shared outbox is still read; anything else must open under the pair's secret and
then match (`PhotoCopy.open`). **What this does not hide:** the copies are the same size and are
written at the same moment, so whoever can see several spaces can still guess that one photo went to
several people. Written in a session without a compiler; not yet built or run.

Separately, `CarpenterMedia.ImagePreparer.redrawn` draws every image into a fresh context before
encoding, because ImageIO carries a source's Exif block — lens, original time, location — into a
thumbnail made from it. That is not cryptography but it is in the same threat: it is the metadata
that would have leaked past the seal.

---

<!-- COPY END 109ba01f -->

<!-- COPY BEGIN 3f67ec76 [NEEDS HUMAN REVIEW] -->

## Your own devices talking to each other

**In plain words.** Your phones keep each other up to date through your own iCloud. What they send
each other is sealed with a key only your identity can derive, so iCloud holds an unreadable blob.

**What actually happens.** `SealedSiblingFeed` derives its key from the identity's own private
material:

```swift
HKDF<SHA256>.deriveKey(
    inputKeyMaterial: SymmetricKey(data: identity.signingSeed + identity.agreementSeed),
    salt: Data(Domain.siblingFeed.utf8),
    info: CanonicalBytes.payload(domain: Domain.siblingFeed, fields: [identity.id.rawValue]),
    outputByteCount: 32)
```

with `(member, device)` as the AEAD's associated data. Only the holder of both seeds can derive it,
which is exactly right — a device restored from the recovery key can reopen its own feed, and
nothing else can.

Mail and catch-ups, which carry room keys, are sealed a second time around that: a random content
key, sealed to each of the member's devices that is not removed with `DeviceSeal`. The small state
record, which carries certificates, revocations and the member's people, is sealed under the identity
only, so a new device can be read before anybody knows its receiving key.

**Every one of these records is signed by the device that wrote it** (since 2026-09-27). The record's
name says which device wrote it, and until then nothing proved it: anybody with the identity,
including a removed device, could write a record in another device's name carrying room keys,
forwarded keys or settings ("rooms deleted" among them), and the member's other devices took it.
Now the writer signs the record over its name and sealed bytes, and carries its certificates. A
record counts in full only if its writer counted when iCloud stored it. From a device that no longer
counts, a record gives people and entries, which verify on their own, and nothing else; the one
exception is a device the recovery key removed handing its writing and room keys to the restored
device, which then gives each room a new key before writing
(`ARemovedDeviceCannotWriteToSiblingsTests`).

**Named because a reviewer will ask:** this uses an Ed25519 *seed* as HKDF input keying material, and
key separation orthodoxy says do not use a signing key for anything but signing. It is safe here —
Ed25519's scalar comes from SHA-512 over the seed, and this derivation uses a different function with
a distinct salt and info, so the outputs are independent under standard assumptions. It is named
anyway because it is a pattern that is fine exactly once and should not spread.

**This is where the worst failure in the project's history happened.** The feed is what carries
`HeldEpoch` — every room key the member holds. For four weeks it was written to CloudKit as plain
JSON. See below.

---

<!-- COPY END 3f67ec76 -->

<!-- COPY BEGIN 346c1b82 [NEEDS HUMAN REVIEW] -->

## The characters two people read to each other

**In plain words.** When somebody invites you, you each see ten characters and read them aloud. If
they match, nobody put themselves in the middle of the invitation.

**What actually happens.**

```swift
public func verificationPhrase(opening nonce: Data?) -> String? {
    guard let nonce, JoinCommitment.opens(nonce, joinerCommitment) else { return nil }
    return ShortAuthenticationString.derive(
        fromTranscript: signingPayload + nonce, length: phraseLength)
}
```

Ten characters by default, twenty if either person asks, from a 30-symbol alphabet. The transcript is
the signed attestation's payload (the room, the joiner's two public keys, the inviter's two public
keys and both timestamps) plus the nonce the joiner committed to in their code. There is no phrase
until that nonce arrives. Characters come from SHA-256 blocks over `(transcript, block number)`, with
bytes of 240 and above discarded so every symbol is equally likely.

The rest of this section is the finding that produced this shape. The six-character version it
describes is the one that shipped before 2026-09-15.

<!-- COPY END 346c1b82 -->

<!-- COPY BEGIN 8beef492 [NEEDS HUMAN REVIEW] -->

### Finding: the phrase can be ground out offline

**This was the most substantive finding in this brief. It is fixed — built and tested 2026-09-15**,
after Griff ruled: lengthen to ten characters *and* add a commitment. The reasoning below is why
both, rather than either, and what the built shape is.

It is not that six characters is too few in the abstract. It is that this protocol has **no
commitment step**, and without one the length is the only thing pricing the attack.

Six characters from 30 symbols is **30⁶ ≈ 7.29 × 10⁸, about 29.4 bits.**

A short authentication string is normally safe at *far fewer* bits than that, because the protocol
**commits** the attacker before either side learns the value — so the attacker gets exactly one
guess, and twenty bits is plenty. Here there is no commitment, and the two sides of a
man-in-the-middle are not symmetric:

- **Toward the inviter**, the attacker cannot grind. They substitute their own keys for the joiner's,
  but the *inviter* signs, so testing a candidate costs a round trip to a human. Infeasible.
- **Toward the joiner**, the attacker signs as the inviter using their own keys, having already
  learned the real phrase from the other side. Everything they contribute is chosen **after** they
  see the joiner's keys, so they grind entirely offline.

**There is no shortage of grinding material.** The attacker chooses the room UUID, both timestamps
and their own keypair — and, less obviously, **the signature itself**. RFC 8032 verification does not
check that Ed25519's nonce was derived deterministically, so an attacker signing with their own code
can emit unlimited distinct valid signatures over one unchanged payload. Each attempt therefore costs
one fixed-base scalar multiplication, which is the most GPU-friendly operation in the whole
primitive set.

<!-- COPY END 8beef492 -->

<!-- COPY BEGIN e9c10dad [NEEDS HUMAN REVIEW] -->

### What the length actually buys

Expected work is half the space. Rates below are one signature-and-hash per attempt: a tuned CPU core
at 5 × 10⁴/s, a sixteen-core desktop at 8 × 10⁵/s, one high-end GPU at 5 × 10⁶/s, and a hundred
rented GPUs at 5 × 10⁸/s.

| Length | Space | 16-core desktop | One GPU | 100 GPUs |
|---|---|---|---|---|
| **6** (before the fix) | 2²⁹·⁴ | **7.6 minutes** | **1 minute** | **0.7 seconds** |
| 8 | 2³⁹·³ | 4.7 days | 18 hours | 11 minutes |
| **10** (ruled) | 2⁴⁹·¹ | 11.7 years | 1.9 years | **6.8 days** |
| 12 | 2⁵⁸·⁹ | — | — | 17 years |
| 20 | 2⁹⁸·¹ | — | — | ~10²⁰ years |

Two things fall out of that table, and they answer the question directly.

**Ten characters is not a marginal gain.** Each character multiplies the work by thirty, so six to
ten multiplies it by **810,000**. That is what moves the attack from *inside the phone call* to
*outside anybody's patience* — and the social window is the real constraint here, because the two
people are waiting to read the phrase to each other. A one-minute grind fits in a pause; a
seven-day grind does not fit in an invitation.

**Twenty characters would genuinely close it by length alone** — 2⁹⁸ is past brute force
permanently, not "days at most". But twenty characters read aloud will be misread, and a check people
get wrong or skip is worse than a short one they actually perform. That is the reason to stop at ten
and fix the structure instead.

<!-- COPY END e9c10dad -->

<!-- COPY BEGIN faf0512d [NEEDS HUMAN REVIEW] -->

### What was built

- **Ten characters** by default, twenty if either side asks. `PhraseLength` travels **inside the
  signed attestation** for both parties, so neither requirement can be stripped in transit, and the
  stricter of the two wins.
- **The joiner commits.** Their code carries `SHA256` of a fresh 32-byte nonce. The inviter signs the
  attestation over that commitment. The joiner reveals the nonce afterwards, riding the
  `JoinConfirmedBody` they already send back. The phrase is derived over the signing payload **plus
  the nonce**, so by the time the inviter knows what the phrase is, everything they contributed is
  already signed and public.
- **The signature is out of the transcript**, as the finding below required.
- **The code is single use.** A commitment is worth nothing once its nonce is known, so a code shown
  to two people would let the first grind the second. `identityCode()` is a function rather than a
  property because it mints, and the device keeps outstanding nonces.
- **The inviter waits.** There is genuinely nothing to show until the other person opens the
  invitation, so the invite screen says that rather than spinning over work already done.

`PhraseCommitmentTests`, eleven of them: the inviter is blind until the joiner opens, both sides
agree afterwards, a substituted nonce is refused, the nonce cannot be swapped in transit, twenty
codes carry twenty commitments, and every combination of the two length settings.

<!-- COPY END faf0512d -->

<!-- COPY BEGIN 25ab60d8 [NEEDS HUMAN REVIEW] -->

### What a commitment does, and what it costs

A commitment makes the attacker choose everything they control **before** they can see the value they
have to match, which reduces them to one blind guess — 1 in 5.9 × 10¹⁴ at ten characters — and takes
compute out of the picture permanently, whatever hardware arrives later.

**The structural fact: somebody has to be committed before they can see what they must match.** The
first design inverted the flow so the inviter spoke first. The built one does not need to: the
**joiner** commits in their code, which they already publish first, and reveals afterwards. The
inviter still signs last — but the phrase now depends on a value they do not have, so signing last
buys them nothing.

The cost is that the inviter cannot see the phrase the moment they issue an invitation. That is not
a delay to be engineered away; it is the property.

**The cheap form is not even a hash commitment.** If the inviter's whole contribution — their keys,
the room, the lifetime, and a fresh nonce — is *transmitted first*, that transmission **is** the
commitment. Which leaves one loose end, and it is a finding of its own:

> **The signature does not belong in the transcript.** `verificationPhrase` derives over
> `signingPayload + signature`. Two different valid signatures over one payload mean the same thing —
> `verify(against:at:)` checks the signature separately — so including it adds nothing to what the
> phrase attests, while adding unlimited post-hoc grinding freedom. Deriving over the signing payload
> alone is a strict improvement and is required for the commitment to bind anything.

**One tempting alternative is worse, and worth recording so nobody reaches for it.** Deriving the
phrase from the *pairwise secret* — a fingerprint of the pair rather than of the invitation — looks
like it removes the grinding surface. It does the opposite: the attacker can compute
ECDH(their candidate, Alice) and ECDH(their candidate, Bob) entirely offline against public keys they
already hold, so matching the two sides becomes a **birthday** search at 2^(n/2) instead of a
preimage search at 2ⁿ. At ten characters that is ~2²⁴·⁵, about 24 million — trivial. A pair
fingerprint must never be the phrase.

<!-- COPY END 25ab60d8 -->

<!-- COPY BEGIN d70f9397 [NEEDS HUMAN REVIEW] -->

### Twenty characters, for somebody who wants them

Off by default, under Privacy & Safety. It is **not** a claim that ten is insufficient — with a
correct commitment both are unreachable. It is defense in depth, and the honest reason to offer it is
narrow: **it is the line that still holds if the commitment itself turns out to be wrong.** All three
of this project's crypto failures were in composition rather than in primitives, so "the new
composition might be wrong" is not a hypothetical worry here.

The two lengths are not alternatives. A phrase comes off one deterministic stream, so **the first ten
characters of a twenty-character phrase are exactly the ten-character phrase** — which is what makes
a mixed pair work without negotiation, and what makes the copy able to say honestly that the extra
ten are added rather than that the whole thing changes.

<!-- COPY END d70f9397 -->

<!-- COPY BEGIN 7606009f [NEEDS HUMAN REVIEW] -->

### The modulo bias, fixed 2026-09-15

`Int(byte) % 30` over a 256-value byte made sixteen of the thirty symbols reachable from nine byte
values and fourteen from eight — 12.5% more likely, worth well under half a bit, and **not** what
made the attack above work.

Fixed by **rejection**, not by changing the alphabet. The 32-symbol set `RecoveryKey.checksum` uses
divides 256 exactly and has no bias, but it contains L and U; this phrase is read aloud, and
excluding I, L, O and U is precisely why the alphabet has thirty symbols. So bytes at or above **240**
— the largest multiple of thirty that fits — are discarded, giving every symbol exactly eight byte
values, and the derivation takes SHA256 blocks over `(transcript, block-number)` until it has enough
characters rather than returning a short phrase.

`VerificationPhraseTests` pins it two ways: the arithmetic directly, and a 30,000-transcript
frequency check. Worth knowing that **only the arithmetic test would have caught the original** — a
12.5% skew on sixteen of thirty symbols moves the observed frequency of the favored group from
53.3% to 53.1%, which no realistic frequency test distinguishes from noise.

---

<!-- COPY END 7606009f -->

<!-- COPY BEGIN f75c8b46 [NEEDS HUMAN REVIEW] -->

## The code two people compare later

**In plain words.** The characters read at an invitation exist only between the person inviting and
the person invited. Anybody else in the room — Alice and Carol, when Bob invited Carol — has nothing
to compare. So any two people can open each other in *Who you are talking to* and compare a code made
of two halves, one for each of them. Both phones show the same two halves. If somebody had slipped
their own keys in between, one of the halves would not match what the other person reads out.

**What actually happens.** Added 2026-09-16, after Griff chose a shared code over each person's own
short code or nothing.

```
half(keys) = SAS( H⁴⁰⁹⁶( SHA256( "carpenter.comparison-code.v1" ‖ len ‖ signing ‖ len ‖ agreement ) ) )
  where H(d) = SHA256( d ‖ signing ‖ agreement )
  and SAS    = ten characters from the phrase alphabet, by the same rejection-sampled stream
               the verification phrase uses, under the comparison domain

code(A, B) = [ half(A), half(B) ] ordered by ParticipantID
```

**Why two halves and not one hash of both keys.** A single ten-character code derived from *both*
people's keys is cheap to fake. Somebody in the middle chooses the keys Alice sees for Carol *and*
the keys Carol sees for Alice, so they need any two codes that collide — a birthday search, about
2²⁵ attempts for 49 bits, which is seconds. With one half per person, fooling Alice means finding
keys whose half equals **Carol's real half**, which is a full second-preimage search of 2⁴⁹, and it
has to be done again for Carol's side.

<!-- COPY END f75c8b46 -->

<!-- COPY BEGIN d5b61974 [NEEDS HUMAN REVIEW] -->

**Why 4,096 rounds.** A half is static — the same every time these two people look — so there is no
commitment to take the grinding away, the way the invitation now has. The rounds make every attempt
cost 4,096 hashes on top of a key generation, about 2¹² more work: roughly 2⁶¹ per side. On the
brief's own rates that is decades on a hundred rented GPUs, against 6.8 days for an unhardened
ten-character code. On a phone a half costs a few milliseconds once, and is cached per person — safe
for the same reason pairwise secrets are, because a `ParticipantID` is the hash of the keys a half is
derived from.

**Ten characters each, fixed.** The *Use a twenty-character code* setting governs invitations,
where both sides' requirements travel in the signed attestation and the stricter wins. There is no
such exchange for a later comparison, and two phones showing halves of different lengths would read
as a mismatch, so a half is always ten.

**Pinned.** `ComparisonCodeTests` checks a half against a value computed independently in Python
from the layout above, so a later build cannot quietly show different codes to the same two people.

**What it does not do.** It says nothing about whether the person holding those keys is who they
say. It says the keys your phone holds for them are the keys their phone holds for itself. Marking a
comparison as matching is a note to yourself; it is not sent to anybody.

---

<!-- COPY END d5b61974 -->

<!-- COPY BEGIN 1470b595 [NEEDS HUMAN REVIEW] -->

## The recovery key is a skeleton key, shown once

**In plain words.** The recovery key is one random secret that every key that is you comes from, plus
one key nothing else has: the one that can make a device count without an approval. It is shown once,
when you set up, until you say you've saved it, and then no device keeps it. Using it on a device
brings your identity back there and removes every other device. There is no way to change it and no
way to make another one, because a device that could make a new one could lock you out of your own
identity. Anybody who has it can take your identity over.

**What actually happens.** `RecoveryKey.text` writes the 32-byte secret and a 3-byte check, in
Crockford base32, grouped in fours (56 characters), under a header and the paragraph the member reads.
Reading it accepts the whole file or the key alone, ignores dashes, spaces and case, reads O as 0 and
I or L as 1, and refuses a key of the wrong length or a failed check as damaged. A file from the old
format, which held the identity's two seeds, is refused as earlier (`ARecoveryKeyTests`,
`RestoringFromAKeyTests`).

From the secret come the identity signing seed, the agreement seed and the recovery signing seed, by
HKDF-SHA256 under `carpenter.recovery-secret.v2` with a label each. A device holds the first two and
the recovery key's public half. The creating device signs the first certificate with the recovery key,
keeps the secret in its Keychain only until the member confirms it is saved
(`IdentityStore.unsavedRecoveryKey`), then deletes it.

Restoring derives the identity from the key, makes a new device key, and signs that device's
certificate with the recovery key. That certificate is the newest root, so every other device stops
counting at its date. A device that learns the recovery key removed it hands its own writing and room
keys to the restored device, sealed to it alone, and erases itself. The restored device gives every
room it gets a key for, from anybody, a new key before it writes anything there, because a removed
device holds the old ones (`rekeyBeforeWriting`). Partners hand the member's room keys again whenever
the member's set of devices changes. A restore also starts a new address salt, since the old one
lived only on devices that are gone, and announces it the way a removal does.

**The largest key-management risk in the product is still this file.** Whoever holds it is you. The
mitigations are editorial — where it is shown, what it says, and that it is shown once — plus one
structural one: no device holds it, so losing a phone never loses the recovery key.

**Worth considering after TestFlight:** an optional passphrase over the file (a password-based KDF →
`ChaChaPoly`) would turn a stolen file from a total compromise into a slow one.

---

<!-- COPY END 1470b595 -->

<!-- COPY BEGIN 4b91a7f5 [NEEDS HUMAN REVIEW] -->

## Where keys actually live

**In plain words.** Your identity lives only on your devices; a new phone gets it when one of yours
approves it (since 2026-09-27; before that it was in iCloud Keychain, where any device signed in to
the Apple Account got it). Every key, room keys included, stays on the device, not even in a backup.
Everything on disk is encrypted by iOS, unreadable until you have unlocked the phone once after it
boots, and left out of iCloud and computer backups.

**What actually happens.**

| Item | Keychain scope | Accessibility |
|---|---|---|
| `identity.keys` (both seeds and the recovery key's public half) | `.device` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| `device.signing`, `device.certificate`, every `epoch.*` room key | `.device` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| `recovery.unsaved` (only until the member saves the key) | `.device` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |

With [Advanced On Device Security](#advanced-on-device-security) on, every one of them is
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` instead.

Everything uses `kSecUseDataProtectionKeychain: true`, and the log, media and document stores are
written with `FileProtectionType.completeUntilFirstUserAuthentication`, or `.complete` with Advanced
On Device Security on, in a directory marked `isExcludedFromBackup`.

**Fixed 2026-09-27: the device's keys went into backups.** Until then every `.device` item was saved
`kSecAttrAccessibleAfterFirstUnlock`, which Apple's documentation says migrates "to a new device when
using encrypted backups", and the store was backed up. Under standard data protection Apple holds the
keys to iCloud Backup, so a default iCloud Backup held the room keys and the sealed log together: the
whole history, openable by whoever can open the backup. Items are now `ThisDeviceOnly`, an item saved
the old way is moved when the app protects what it keeps (the first launch of a build that has not
done it yet, since 2026-09-28; before that, the first time the item was read), and the store, the
Focus room list and the diagnostics files are out of backups (`SystemKeychainTests`,
`StoreLeftOutOfBackupsTests`). From
Apple's documentation, not measured on a device. The cost: restoring a phone from a backup no longer
brings this app back with it; the recovery key or another device's approval does.

**Two consequences, named.** `afterFirstUnlock` means that on a phone which has been unlocked once
since boot, the keys are available to the operating system even while the screen is locked. That is
required — the app has to sync in the background and the notification extension has to decrypt a
message to draw a banner — and it is a real reduction from `WhenUnlocked`. A member who would rather
give up both can turn on [Advanced On Device Security](#advanced-on-device-security).

---

<!-- COPY END 4b91a7f5 -->

<!-- COPY BEGIN 9c27f287 [NEEDS HUMAN REVIEW] -->

## The app lock

**In plain words.** The app can ask for its own code, or Face ID, before it shows anything. The code
is not stored; something only the right code can match is. It is a door on the app's screens, not a
second layer of encryption on what the app stores.

**What actually happens.** `AppLock` keeps a 32-byte random salt and PBKDF2-HMAC-SHA256 of the code
over it, 300,000 rounds, compared in constant time. It sits in the keychain as `app.lock`, `.device`
scope (`AfterFirstUnlockThisDeviceOnly`), so it never leaves the phone, never reaches a backup, and
survives deleting the app. Every try is written down as a failure before the code is checked and
cleared only if the code was right. After five failures each further try waits: 1, 5, 15 minutes, then
an hour. The wait is timed by `CLOCK_MONOTONIC` together with the kernel's boot session id, so setting
the date does nothing, and a restart starts the wait over rather than ending it
(`AppLockTests`, `AppLockControllerTests`).

Face ID is asked for with `deviceOwnerAuthenticationWithBiometrics` and no passcode fallback, and it
counts only when `LAContext.domainState.biometry.stateHash` matches the one taken when Face ID was
turned on or the code was last entered, so a face enrolled since, by somebody who knows the phone's
passcode, does not open it.

**What it does not do.** Somebody who can read the phone's storage directly, with a forensic tool or
a modified app, is not stopped by it: the store is protected by iOS's file protection and the
keychain, as it is without the lock. A 4-digit code's verifier could be tried against all 10,000
codes in minutes by anybody who already had the keychain item; the counted tries only bind somebody
using the app. Griff ruled on 2026-09-28 for an opt-in that does stop a copy being read,
[Advanced On Device Security](#advanced-on-device-security).

<!-- COPY END 9c27f287 -->

<!-- COPY BEGIN eb2e47b3 [NEEDS HUMAN REVIEW] -->

## Advanced On Device Security

**In plain words.** Off unless you turn it on. With it on, what the app keeps on your iPhone (the
history, names, photos and every key) can be read only while the iPhone is unlocked. Somebody who
takes it while it is locked and copies its storage gets files they cannot open without the iPhone's
passcode, and the passcode can only be tried on that iPhone. While it is locked the app fetches
nothing: messages wait, sealed, in the sender's iCloud and arrive when you unlock it, and a
notification says only that something arrived.

> **Written 2026-09-28 in a session with no compiler.** Not built, and not run on a phone. The package
> tests model a locked phone with a fake keychain; nothing here has been measured on hardware.

**What actually happens.** No new cryptography: the app asks iOS for its strongest protection, which
iOS already ties to the passcode and to the phone's own hardware key.

- **Files.** The log, the state, photos and clips, every avatar, the Focus room list, the old copies of
  the log and state left in Application Support, and the app's temporary folder are written and kept
  as `FileProtectionType.complete`, which Apple describes as "stored in an encrypted format on disk
  and cannot be read from or written to while the device is locked or booting"
  ([Apple](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)). Apple's
  security guide says the key for that class is discarded shortly after the phone locks, ten seconds
  when it asks for the passcode immediately
  ([Apple Platform Security](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web)).
  Every store reads the setting at the moment it writes (`ProtectionDial`, `ProtectedFiles`).
- **Keys.** Every keychain item is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: "can be accessed
  only while the device is unlocked by the user"
  ([Apple](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)).
- **The choice** is a keychain item, `storage.protection`, holding what was chosen and what has been
  applied. A choice that cannot be read counts as on (`ProtectionChoice.read`).
- **Changing it** records the choice, then re-protects every key and every file already kept, then
  marks it applied. Interrupted, it finishes the next time the app opens. Changes run one at a time,
  so the choice, its record and every key end up agreeing (`SealedWhileLockedTests`).
- **Reading a key never changes how it is protected**, since 2026-09-28. A read used to move a key to
  the ordinary protection, and the notification extension reads the same keys, so every push would
  have undone the setting (`SystemKeychainTests.readingChangesNothing`).
- **While the phone is locked** (`UIApplication.isProtectedDataAvailable` is false), the app runs no
  round and no device sync, loads nothing and signs for nothing, and it loads when iOS says protected
  data is available again. A write refused because the phone locked during a round is not signed for,
  so the sender offers it again, and it is not counted as damage in the history check. The
  notification extension cannot open the keychain, so it shows the plain banner at once and leaves
  the number on the icon alone.

**What it does not do.**

- **Nothing without a passcode.** "Data protection is enabled automatically when the user sets an
  active passcode for the device"
  ([Apple](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)). The switch
  cannot be turned on while the iPhone has none.
- **Nothing against somebody who knows the passcode.** Outpost's own lock as the seal is the choice
  that would; it is not built
  ([Open questions](open-questions.md#how-should-outposts-own-lock-seal-what-this-phone-keeps)).
- **Not everything the app keeps.** Its preferences (theme, favourite emoji, which rooms a Focus lets
  through and which photos you chose to show, each by a random identifier) and the device-sync
  engine's bookkeeping stay readable once the phone has been unlocked after it starts. None of them is
  a message, a name, a photo or a key
  ([Open questions](open-questions.md#should-the-apps-preferences-be-sealed-too)).

**What it costs.** Nothing arrives in the background while the phone is locked, and every banner in
that time says only "New message". A phone left locked for longer than a packet waits is like one that
was off that long
([Open questions](open-questions.md#what-reaches-a-phone-that-stays-locked-longer-than-a-packet-waits)).

<!-- COPY END eb2e47b3 -->

<!-- COPY BEGIN 6442968d [NEEDS HUMAN REVIEW] -->

## What has already gone wrong

Every one of these was in the composition. Each is here for the pattern, not the anecdote.

<!-- COPY END 6442968d -->

<!-- COPY BEGIN 4df34683 [NEEDS HUMAN REVIEW] -->

### 1. The sibling feed went to CloudKit in the clear, for four weeks

Every epoch secret the member held, as plain JSON, in a CloudKit record. ChaChaPoly worked perfectly;
**nothing called it**.

Why no test caught it: `InMemoryEntrySync` stored `[UUID: SiblingFeed]` — the *struct*, never
serialized. The real one encoded to JSON and wrote it. No test in 118 suites could see the
difference, because the fake never produced bytes.

**The pattern: a fake that is easier than the real thing proves less than nothing.** Every seam's
fake was audited against that rule on 2026-09-14, and the relay holds encoded `Data` now.

<!-- COPY END 4df34683 -->

<!-- COPY BEGIN e904e0e2 [NEEDS HUMAN REVIEW] -->

### 2. Two optional fields changed every signature ever taken

Described in full under [canonical bytes](#the-bytes-everything-is-signed-and-sealed-over). Every
entry on every device stopped opening and stopped verifying at once, and the app offered onboarding
to accounts with months of history.

**The pattern: a round-trip test cannot catch a wire-format change, because it seals and opens with
the same build.** Pin the old layout by hand.

<!-- COPY END e904e0e2 -->

<!-- COPY BEGIN 00c78bcc [NEEDS HUMAN REVIEW] -->

### 3. A map keyed on the person, not the thing

`confirmations` was `[ParticipantID: Date]`, so "has this joiner confirmed" outlived every
membership and the phrase gate stood open for anybody ever removed. `admissions` and `refusals` had
the same shape. They key on the invitation being answered now.

**The pattern: a key that is a person answers a question about a person, forever.** If the question
is really about *this invitation*, the key has to be the invitation.

---

<!-- COPY END 00c78bcc -->

<!-- COPY BEGIN b88342c5 [NEEDS HUMAN REVIEW] -->

## What this brief does not cover

Stated so that nobody mistakes its silence for a clean bill.

- **No formal analysis.** No proof, no model checker, no symbolic execution of the handshake. The
  arguments here are careful reading, not machine-checked.
- **No side-channel analysis.** Timing, power and memory behavior are whatever CryptoKit does.
  CryptoKit's primitives are constant-time; the *composition* has not been examined for timing
  leaks — for example whether a failed open is distinguishable in duration from a refused one.
- **No adversarial testing of the membership state machine.** Roster, invitation and removal logic
  is heavily unit-tested against intended behavior, and has not been fuzzed or attacked.
- **Three-party cryptographic cases are unproven over the real transport**, and genuinely need a
  third Apple Account — see [Proofs a rig cannot run](proofs-a-rig-cannot-run.md).
- **No post-quantum anything.** X25519 and Ed25519 are classical. Harvest-now-decrypt-later applies
  to everything this app has ever sealed. Apple's own protocols are moving to PQ3-style hybrids; this
  is not, and nothing in the product should imply otherwise.

---

<!-- COPY END b88342c5 -->

<!-- COPY BEGIN 2bd43643 [NEEDS HUMAN REVIEW] -->

## Where to start reading, if you want to break it

In the order a person is most likely to find something:

1. **`EpochGrant.issue`** — the `links` filter. Too many links is a reader seeing history they were
   never granted, and it is an error nowhere.
2. **`MembershipAttestation.verificationPhrase`** — the finding above is there; check whether the
   reasoning holds and whether there is a cheaper grind.
3. **`CanonicalBytes` and every `signingPayload`** — anywhere a field was appended, reordered, or
   made optional.
4. **`Replica.integrate`** — the only place a signature is checked. Anything reaching state without
   passing through it is a bug by construction.
5. **`SyncEngine.pack`** — anything addressed per peer that is not a list.
6. **Every fake in `CarpenterKitTesting`** — if one does not produce the bytes the real seam
   produces, it cannot fail the way the real one fails.

The tests worth reading alongside: `SealBindingTests` (pins the wire format by hand),
`SiblingFeedIsSealedTests`, `EpochDistributionTests`, `DeviceTrustTests`, `CanonicalBytesTests`, and
`App/CarpenterTests/LiveSiblingFeedTests.swift`, which fetches a record back off real CloudKit and
asserts it contains no epoch secret.

<!-- COPY END 2bd43643 -->
