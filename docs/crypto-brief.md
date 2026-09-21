---
title: The crypto, written down
layout: default
nav_order: 3
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
| `ChaChaPoly` (RFC 8439 AEAD) | six files | every piece of ciphertext in the system |
| `HKDF<SHA256>` | `EpochChain`, `Pairwise`, `SealedSiblingFeed` | turning one secret into several unrelated keys |
| `HMAC<SHA256>` | `Pairwise` | the rotating addresses and the bell names |
| `SHA256` | `Identity`, `Entry`, `SealedAttachment`, `ShortAuthenticationString` | identifiers, content hashes, fingerprints |
| `SymmetricKey(size: .bits256)` | `EpochSecret.random`, `SealedAttachment.seal`, `SyncEngine.pack` | all random key material |

There is **no hand-rolled cipher, curve, hash, MAC or KDF, and no custom padding, compression or
encoding of plaintext before sealing**. There is also no injectable random-number seam in the
shipping path: `RandomSource` exists as a protocol but nothing in `Sources` outside its own file and
the test fakes refers to it, so every byte of key material comes from CryptoKit's own generator and
there is no place to substitute a weak one.

The twelve files that are *ours* are `CanonicalBytes`, `Identity`, `IdentityStore`,
`DeviceCertificate`, `DeviceRegistry`, `Pairwise`, `EpochChain`, `EpochGrant`, `SealedPayload`,
`SealedAttachment`, `RecoveryKey` and `ShortAuthenticationString`, plus the way `Entry`, `SyncEngine`
and `SiblingFeed` use them.

**One thing done right that is usually done wrong.** The signing key and the key-agreement key are
**two independent seeds**, not one seed used for both. Reusing a single Curve25519 private key as
both an Ed25519 signing key and an X25519 agreement key is a common and genuinely dangerous
shortcut; this code does not take it. `Identity` carries `signingSeed` and `agreementSeed`
separately, and each is validated as its own key type at construction.

---

## Who you are

**In plain words.** There is no account. When the app first runs it makes two keys and those keys
*are* you — there is nothing else to be. Nobody can look you up, because there is no directory and
no name to look up; the only way anyone reaches you is if you hand them a code yourself.

**What actually happens.** `Identity.generate()` produces an Ed25519 signing keypair and an X25519
agreement keypair. Your public name is derived, not chosen:

```
ParticipantID = SHA256( "carpenter.participant-id.v1" ‖ len(signing) ‖ signing
                                                     ‖ len(agreement) ‖ agreement )
```

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
back-dating visible rather than preventing it, and that turning the room key after a loss
(`turnEveryKeyAfterALoss`) stops the device reading anything *new* regardless of what it claims to
have written. This is the classic distributed-clock problem and it is not solved here; it is
bounded.

---

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

From that one 32-byte secret, five unrelated things are derived, each under its own domain string so
that none of them can be used to attack another:

| Derived thing | Construction | Purpose |
|---|---|---|
| `recipientTag(window:for:)` | `HMAC-SHA256(key, "…recipient-tag.v1" ‖ window ‖ recipient)` | the rotating address a packet is left under |
| `bellName(for:)` | `HMAC-SHA256(key, "…message-bell.v1" ‖ recipient)`, first 16 bytes hex | the push subscription name |
| `shareOfferName(for:)` | `HMAC-SHA256(key, "…share-offer.v1" ‖ recipient)`, first 16 bytes hex | the rendezvous record name |
| `shareOfferDigest(of:)` | `HMAC-SHA256(key, "…share-offer-digest.v1" ‖ url)`, first 16 bytes hex | detecting a substituted share URL |
| `wrap` / `unwrap` | `ChaChaPoly` with the key directly, caller-supplied associated data | epoch grants, packet keys |

**Known weakness, named.** The pairwise secret is **static for the life of the two identities**.
There is no ratchet. If somebody obtains your `agreementSeed`, they can derive every pairwise secret
you have ever had or will ever have, with everyone, forever — and from those, unwrap every epoch
grant they can collect. Identity compromise is total and permanent, and the only remedy is a new
identity. This is stated again, deliberately, under [the recovery
key](#the-recovery-key-is-the-whole-of-you-in-a-text-file).

---

## The room key, and the chain behind it

This is the least conventional part of the design and the part most worth attacking.

**In plain words.** Every room has a key. When somebody leaves or a phone is lost, the room turns
its key, and from that moment the old key opens nothing new. But old conversations must still be
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

### Three properties this shape gives you

- **Post-compromise security: yes.** Knowing epoch *N* tells you nothing about epoch *N+1*. The link
  at *N+1* is sealed **under** *N+1*'s key, not *N*'s, and *N+1* is a fresh random value distributed
  only through pairwise-wrapped grants. Turning the key after a loss genuinely shuts the old holder
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

### Handing somebody a key

`EpochGrant.issue` wraps an epoch secret under a **pairwise** secret, with `(room, epoch)` as the
associated data, and carries the links alongside:

```swift
links: links.filter { $0.room == room && $0.epoch != link?.epoch },
wrapped: try peer.wrap(secret.material, context: Self.context(room: room, epoch: epoch))
```

`adopt` refuses a grant for the wrong room before opening it. The filter on `links` is the access
boundary in code form — whatever is left out of that array is history the recipient cannot reach.

**Known weakness, named.** A grant's `links` array is the *only* thing standing between a reader and
the whole room. It is a list somebody has to get right, in a filter, in one place. There is no
second check downstream asking "should this person be able to read that far back?" — by the time the
links are in their chain, the answer is yes and cannot be withdrawn. **This is the single highest-value
line in the codebase to audit**, and the failure mode is silent: too many links is not an error
anywhere, it is a reader who can see more than intended and no log line anywhere says so.

**Known weakness, named.** Two members advancing the same room's epoch at the same moment is
untested and genuinely needs three real accounts to exercise — it is on
[Still to prove](roadmap.md#still-to-prove). If rival advances resolved differently on
different devices, members would hold different secrets for the same epoch number and messages would
stop opening for somebody, with no error that names the cause.

---

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
2⁻³³. A room would have to send four billion messages without a single key turn to approach it. Not
a concern, but it is an assumption rather than a guarantee, and it would stop being safe if epochs
were ever made long-lived and high-volume at once.

---

## Signing what was written, and why the order matters

**In plain words.** Every entry carries a signature from the device that wrote it. Change one byte —
the time, the room, a single character of the sealed text — and the signature stops matching. There
is no way to put words in somebody's mouth.

**What actually happens.** `Entry.signingPayload` is canonical bytes over
`(author, device, seq, previous?, clock, wallTime, conversation, payload)`, signed with the **device's**
Ed25519 key. A device keeps one log per conversation, so `seq` and `previous` count within that
conversation, and no number on an entry says anything about its writer's other conversations. Two things about this are worth stating precisely because they are the questions a
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
nothing here, because it seals and opens with the same build — `SealBindingTests` and
`ConversationIDTests` pin the layout by writing it out by hand, and that is the only kind of test that
can catch this.

**`FeedKey` is three fixed parts, concatenated.**

```swift
var canonicalBytes: Data { author.rawValue + device.rawValue + conversation.canonicalBytes }
```

`author` and `device` are SHA-256 digests, and `ParticipantID` and `DeviceID` refuse anything other
than 32 bytes when they are decoded, which is where bytes this process did not write arrive. A
conversation's bytes open with a tag that fixes their length — a room or a solo is the tag and a
16-byte UUID, an Outpost is the tag and its owner's 32-byte id. So a feed key has exactly one
reading. `FeedKey.canonicalBytes` feeds the vector clock's canonical bytes and the sealed payload's
associated data, and `IdentifierWidthTests` holds all three parts, for every kind of conversation.

---

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

The record written to CloudKit (`PacketWire.fields`) carries exactly: the packet UUID, the
outstanding tag list, the wrap tags, the wrapped keys, the sealed body, and the grant tags and
values. **What that leaks, stated plainly:**

- How many recipients a packet has (the length of the tag list).
- Roughly how much was said (the ciphertext's size).
- When it was written, and when each recipient collected — the tag is removed from `outstanding` as
  each one acknowledges, so the relay watches the fan-out drain.
- That a set of packets share a recipient *within one day*.

**The shape of a round is a trade, stated.** A round writes one packet per audience — the people
owed exactly the same entries — so no record names more people than one conversation holds. The
relay sees several fan-outs rather than one, and their sizes are the sizes of a member's rooms. The
audiences are rotating tags, and two cannot be told apart across a day boundary, but a member who
talks in four rooms writes four records in a round.

Inside the sealed body, beside the entries, a packet can carry the positions it is withholding from
its reader and the newest position of each log in its rooms — attestations. Neither is visible to
the relay, and neither is sent to anybody who could not already read the entry it describes.

It does not leak any participant identifier, any room identifier, any device identifier, or any
plaintext. **Nothing is ever written with `record[key]` unsealed** — the rule in `CLAUDE.md` exists
because it was broken once, and that is the next section.

---

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

Size caps are enforced before sealing — 12 MB for an image, 40 MB for a video.

Separately, `CarpenterMedia.ImagePreparer.redrawn` draws every image into a fresh context before
encoding, because ImageIO carries a source's Exif block — lens, original time, location — into a
thumbnail made from it. That is not cryptography but it is in the same threat: it is the metadata
that would have leaked past the seal.

---

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

**Named because a reviewer will ask:** this uses an Ed25519 *seed* as HKDF input keying material, and
key separation orthodoxy says do not use a signing key for anything but signing. It is safe here —
Ed25519's scalar comes from SHA-512 over the seed, and this derivation uses a different function with
a distinct salt and info, so the outputs are independent under standard assumptions. It is named
anyway because it is a pattern that is fine exactly once and should not spread.

**This is where the worst failure in the project's history happened.** The feed is what carries
`HeldEpoch` — every room key the member holds. For four weeks it was written to CloudKit as plain
JSON. See below.

---

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

## The recovery key is the whole of you, in a text file

**In plain words.** The recovery key file contains your actual keys, in plain text. Anybody who opens
that file *is* you, permanently, and there is no way to change it or cancel it. The file says so, in
its own first paragraph.

**What actually happens.** `RecoveryKey.text` writes both private seeds as **base64, unencrypted**,
with a fingerprint and an eight-character checksum. There is no passphrase, no key-derivation
function, no wrapping. The checksum is integrity only — it catches a mistyped file, not an attacker.

This is a deliberate design, and the file is honest about it:

> Anybody with this file can become you. There is no way to change it and no way to revoke it. Keep
> it where you keep passwords, not where you keep photographs.

**Stated plainly as the largest key-management risk in the product.** Because the pairwise secret is
static and derived from the agreement seed, whoever holds this file can derive every pairwise secret
you will ever have, unwrap every epoch grant addressed to you, and sign as you. It is not a password
that can be changed; it is the identity itself. The mitigations are all editorial — where the file
is shown, what it says, and how it is offered — and they are the right place for the effort, because
no amount of cryptography rescues a file the member emails to themselves.

**Worth considering after TestFlight:** offering an optional passphrase over the file
(`HKDF`/`PBKDF2` → `ChaChaPoly`) would cost one screen and would turn a stolen file from a total
compromise into a slow one. It is not on the roadmap and this brief is not the place to add it —
noting it here so it is on the record as a known, unaddressed cost.

---

## Where keys actually live

**In plain words.** Your identity lives in your iCloud Keychain so a new phone can pick it up. The
key belonging to *this particular phone* never leaves it. Everything on disk is encrypted by iOS and
unreadable until you have unlocked the phone once after it boots.

**What actually happens.**

| Item | Keychain scope | Accessibility |
|---|---|---|
| `identity.keys` (both seeds, concatenated) | `.synchronized` — iCloud Keychain | `kSecAttrAccessibleAfterFirstUnlock` |
| `device.signing` | `.device` — never leaves | `kSecAttrAccessibleAfterFirstUnlock` |
| `draft.sealing` (32 random bytes) | `.device` — never leaves | `kSecAttrAccessibleAfterFirstUnlock` |

Everything uses `kSecUseDataProtectionKeychain: true`, and the log, media and document stores are
written with `FileProtectionType.completeUntilFirstUserAuthentication`.

**Drafts are the one piece of unsent writing on disk, and they are sealed.** `DraftSeal` seals each
conversation's draft with ChaChaPoly under `draft.sealing`, with the room's canonical bytes under
`carpenter.draft.v1` as associated data, so a draft cannot be moved to another room. The key is
random rather than derived: deriving it from an identity seed would be the pattern the sibling feed
section says should not spread. A copy of the state file without this device's keychain holds
ciphertext. The key is not synchronized through iCloud Keychain, so a draft does not follow the member
to their other devices. What a device backup carries of it has not been measured.

**Two consequences, named.** `afterFirstUnlock` means that on a phone which has been unlocked once
since boot, the keys are available to the operating system even while the screen is locked. That is
required — the app has to sync in the background and the notification extension has to decrypt a
message to draw a banner — and it is a real reduction from `WhenUnlocked`. And the identity's
presence in iCloud Keychain means its safety rests on Apple's escrow design (end-to-end, with
hardware-enforced passcode attempt limits) rather than on anything this app does.

---

## What has already gone wrong

Every one of these was in the composition. Each is here for the pattern, not the anecdote.

### 1. The sibling feed went to CloudKit in the clear, for four weeks

Every epoch secret the member held, as plain JSON, in a CloudKit record. ChaChaPoly worked perfectly;
**nothing called it**.

Why no test caught it: `InMemoryEntrySync` stored `[UUID: SiblingFeed]` — the *struct*, never
serialized. The real one encoded to JSON and wrote it. No test in 118 suites could see the
difference, because the fake never produced bytes.

**The pattern: a fake that is easier than the real thing proves less than nothing.** Every seam's
fake was audited against that rule on 2026-09-14, and the relay holds encoded `Data` now.

### 2. Two optional fields changed every signature ever taken

Described in full under [canonical bytes](#the-bytes-everything-is-signed-and-sealed-over). Every
entry on every device stopped opening and stopped verifying at once, and the app offered onboarding
to accounts with months of history.

**The pattern: a round-trip test cannot catch a wire-format change, because it seals and opens with
the same build.** Pin the old layout by hand.

### 3. A map keyed on the person, not the thing

`confirmations` was `[ParticipantID: Date]`, so "has this joiner confirmed" outlived every
membership and the phrase gate stood open for anybody ever removed. `admissions` and `refusals` had
the same shape. They key on the invitation being answered now.

**The pattern: a key that is a person answers a question about a person, forever.** If the question
is really about *this invitation*, the key has to be the invitation.

---

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
  third Apple Account — see [Still to prove](roadmap.md#still-to-prove).
- **No post-quantum anything.** X25519 and Ed25519 are classical. Harvest-now-decrypt-later applies
  to everything this app has ever sealed. Apple's own protocols are moving to PQ3-style hybrids; this
  is not, and nothing in the product should imply otherwise.

---

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
