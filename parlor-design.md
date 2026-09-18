# Project Parlor — Design Document

**Status:** Draft v0.1 — pre-implementation
**Codename:** `parlor` (arbitrary, replace freely — see §3.3)
**Target:** iOS 26+, iPadOS 26+, macOS 26+
**Audience:** Claude Code (implementation), project owner (decisions)

---

## 1. What this is

A group messaging app for friend groups. Rooms for shared conversation, a personal Wall
per member. All content lives on member devices. Sync happens in the foreground when the
app is open and has a connection. Nothing readable is stored anywhere but on the devices
of people in the group.

It is not Discord and not Slack. There is no server-side identity, no directory, no
moderation infrastructure, no voice, no presence. The comparison point is iMessage: a
thing your friends use that happens to be private, not a platform.

### 1.1 The claim, stated precisely

**Not** "there is no server." There is a mailbox (§4.2) and pretending otherwise is
dishonest.

**The claim is:** no operator — not the developer, not Apple — can read any message, any
wall post, any room name, or any member's display name. The mailbox holds opaque
ciphertext addressed to rotating tags and deletes it once delivered. A breach of the
mailbox yields encrypted blobs and a coarse delivery graph. There is no readable content
to steal because none was ever uploaded in readable form.

Every piece of UI copy must respect this distinction. Overclaiming here is the fastest
way to lose the only thing the product has.

### 1.2 Explicit non-goals for v1

Voice and video. Screen sharing. Public/discoverable rooms. Moderation tooling.
Third-party plugins. Web client. Android. Server-side search.

---

## 3. Platform and structure

### 3.1 Targets

| Platform | Minimum | Notes |
|---|---|---|
| iOS | 26.0 | Primary. |
| iPadOS | 26.0 | Full parity. |
| macOS | 26.0 | Full parity. Also the most likely "always-on peer" in a friend group, which matters a lot for §5. |

No watchOS in v1. A watch app that can't sync independently is a notification mirror,
and there is no background sync to mirror.

### 3.2 Why foreground-only sync is the unlock

Every prior peer-to-peer messenger that died on iOS died on background execution. Apple
DTS is explicit that a suspended app cannot be repeatedly woken, that background pushes
wake an app one to two times an hour for about ten seconds, and that persistent
background sockets are restricted to app categories this is not. Briar — funded, in
development since 2017 — concluded an iOS version does not appear realistic for exactly
this reason.

D1 sidesteps all of it. Sync when the user opens the app, in the foreground, where a
normal networking stack works normally. This is a real constraint on the product (you
learn about messages when you look), not a workaround, and the UI should present it as
intentional.

**Consequence:** a user-visible push telling you *that* something happened is still
desirable and is available via `CKSubscription` without running an APNs server. The push
carries no content. Opening the app triggers the sync.

### 3.2.1 Opportunistic background refresh

Register a `BGAppRefreshTask`. The system schedules it against observed usage patterns —
it may fire in minutes or in hours, and it is never guaranteed. Budget roughly 30 seconds
of execution.

**This is a freshness optimisation, not a correctness mechanism.** Rules:

- A background refresh fetches and decrypts pending mailbox packets only. It never
  initiates backfill, never serves a backfill request, never starts a direct-channel
  session. Thirty seconds is not enough and being killed mid-transfer costs more than it
  saves.
- Every failure mode of background refresh must be invisible. If it never runs, the app
  behaves exactly as designed: it syncs when opened.
- Do not surface "last synced" times that make a missed refresh look like a bug.

Net effect: when it works, the user opens the app and content is already there. When it
doesn't, they wait two seconds. That is the whole benefit and it is worth having.

### 3.3 Codename placeholder

Identical mechanism to the location project: `Config/Branding.xcconfig` defines
`APP_DISPLAY_NAME`, `APP_BUNDLE_ID_PREFIX`, `APP_ICLOUD_CONTAINER`; `Info.plist` uses
`$(VARIABLE)` with no literals; a single `Branding.swift` reads the display name; all
user-facing strings live in a String Catalog with `%@` substitution. CI lint fails the
build if the literal `parlor` appears outside `Config/` and directory paths.

---

## 4. Architecture

### 4.1 Data model: append-only logs

Every member has one **feed** per device. A feed is an append-only, hash-linked,
signed log of entries.

```
Entry {
  author:      ParticipantID          // stable across the member's devices
  device:      DeviceID               // which device appended this
  seq:         UInt64                 // monotonic within (author, device)
  prev:        Hash                   // hash of the previous entry in this feed
  clock:       [ParticipantID+DeviceID : UInt64]   // causal context observed at append
  wallTime:    Date                   // display only, never trusted for ordering
  roomID:      RoomID?                // nil = this member's Wall
  payload:     Ciphertext             // sealed to the room epoch key
  signature:   Signature              // over everything above, by the device key
}
```

- **A Wall is just a feed filtered to `roomID == nil`.** No separate concept.
- **A Room is a set of feeds** whose members have agreed to replicate one another.
- Entries are immutable. Edits and deletes are tombstone entries that reference a prior
  entry hash. Reactions likewise. Clients render the fold, not the raw log.

**Per-device feeds internally, one author identity externally.**

The owner's proposal — one feed per author, with a "sync to new device" flow gated by a
second factor — is the right *user-facing* model and should be built exactly as described.
It should not be the storage model, for one reason: two devices appending to a single
linear feed while offline will eventually produce two entries with the same sequence
number and different content. That is a fork. Avoiding it requires the devices to
coordinate before each append, which requires them to be online together, which defeats
offline-first entirely. In Scuttlebutt a fork is treated as feed compromise; here it would
be a silent correctness failure.

So: keep per-device feeds as the internal representation, merged at read time. The user
never encounters the concept. They see one identity, one history, and a device list.

**Adding a device: there is no flow, and that is the design.**

A device certificate is signed by the *identity* key, and the identity key lives in the
synchronizable Keychain — so iCloud Keychain has already put it on every device of the
member's Apple Account. A second device therefore:

1. Finds the identity already present.
2. Generates its own signing subkey and issues its own certificate with the identity key.
3. Starts syncing. Room keys and the other devices' certificates arrive in the sibling
   feed, on the ordinary sync path.

Nothing is displayed, nothing is typed, nothing is confirmed. Opening the app on a new
device shows the member their rooms.

**Why this replaced a pairing ceremony.** An earlier build had one: ephemeral X25519 keys,
a spoken six-character string, a sealed transfer, a rendezvous record in CloudKit and a
prompt on the other device. It was designed for a channel nobody trusted — and on one
Apple Account there is no such channel, because iCloud Keychain is end-to-end encrypted
and already carries the only secret that matters. The ceremony moved two things that both
travel by themselves, and it was the single largest source of defects in the project. It
is gone; §9.2 row 120 records the move.

**One Apple Account is one member.** `createIdentity` refuses to start a second member when
an identity is already present, and `IdentityStore.enrol()` reuses what the Keychain holds.
There is no supported way to have two identities on one Apple Account, which is what makes
account deletion meaningful.

**Device revocation.** Removing a device revokes its certificate and triggers an epoch
advance. Entries it signed before revocation remain valid, which is correct — they really
were authored by you.

**Ordering.** Causal order from `clock`, with `wallTime` used only as a display-level
tiebreak between concurrent entries. Never sort by `wallTime` alone; clocks on phones
are wrong and a malicious or confused device could reorder history.

### 4.2 Transport: mailbox, not connection

Two channels, used for different things.

**Mailbox (CloudKit).** The default path. A member's outgoing entries are batched into a
**sync packet**, sealed, and written as one record addressed to a rotating recipient tag
derived from the pairwise secret. Recipients fetch, decrypt, and acknowledge; fully
acknowledged packets are deleted. `CKSubscription` fires a contentless push so members
know to open the app.

**Direct (Network framework / MultipeerConnectivity).** Opportunistic. When two members
are on the same local network with both apps in the foreground, sync directly. Free,
fast, and the right path for large backfills and media. Foreground-only is fine here —
local peer-to-peer on iOS requires at least one device in the foreground regardless, and
D1 already guarantees that.

**Batching is the cost control.** One sync writes one packet containing everything since
the last sync, not one record per message. This is what makes CloudKit's request quota
survivable for a chat-shaped workload. Enforce a write budget in the transport layer and
instrument it from the first build. See Open Question 2.

### 4.3 Cryptography

```
Identity:    Ed25519 signing key + X25519 agreement key per member.
             Stored in synchronizable Keychain (E2E encrypted by default,
             independent of Advanced Data Protection).
Device:      Ed25519 signing subkey per device, certified by the identity key.
             Device certificates are published in-band.
Pairwise:    X25519 ECDH -> HKDF-SHA256 -> per-pair secret. Used to address
             mailbox packets and wrap epoch keys.
Room epoch:  Symmetric key per room per epoch. Payloads sealed with
             ChaChaPoly under the current epoch key.
Wall:        Same mechanism; the wall is a room whose membership is
             "people I've allowed."
```

**Epochs and membership.** A new epoch begins whenever membership changes. Every existing
member wraps the new epoch secret to every current member's pairwise secret on their next
sync (D4).

#### Key consolidation: a reverse hash chain

> **Superseded by Design Decision P6.** The construction below cannot advance an epoch without retaining
> forward material, and whoever retains it can derive every future epoch — losing the forward-only
> removal it was chosen to guarantee. Implemented as historical chain wrapping instead. Left here
> as written, per §8.1.2.

The naive form of D2 requires handing a joiner every historical epoch key — a bundle that
grows forever. The owner's instinct that there should be one key at a time is correct, and
there is a standard construction that gets it.

Generate the chain **backwards** at room creation. Pick a random terminal secret `S_N` for
some large `N`, then define:

```
S_n = H(S_{n+1})        for n from N-1 down to 0
```

Epoch `n` uses a key derived from `S_n` via HKDF with the room ID and epoch number as
context. Never use `S_n` directly as an encryption key.

The properties fall out of the one-wayness of `H`:

- **Holding `S_k` yields every earlier secret.** `S_{k-1} = H(S_k)`, and so on down to
  `S_0`. A joiner at epoch `k` receives exactly one secret and derives every key needed to
  read all history. This is D2, satisfied with a single wrapped value.
- **Holding `S_k` yields nothing later.** Computing `S_{k+1}` requires inverting `H`.
  A removed member cannot derive future epochs. This is the forward-only removal semantics
  from §4.3, enforced cryptographically rather than by convention.

So membership change is: advance to epoch `k+1`, and every remaining member wraps `S_{k+1}`
to every other remaining member. One value, not a bundle. New joiners get the same single
value everyone else just received.

**Practical notes:**

- `N` is a hard ceiling on membership changes for the life of a room. `N = 65536` is
  cheap and generous; a friend group will not exhaust it. Handle exhaustion by chaining a
  fresh root, which is a one-line case that must exist rather than a scenario to plan for.
- Generating the chain is `N` hash operations at room creation. Trivial.
- Derivation cost at read time is `k` hashes to walk back to an old epoch. Cache derived
  epoch keys in the Keychain rather than re-walking on every message render.
- The chain root `S_N` must be destroyed after generation, or whoever holds it can derive
  every future epoch forever. Generate, retain only `S_0` through the current epoch as
  needed, discard the rest of the forward material immediately.
- This makes the "anyone who joins gets everything up to now" property structural. That
  is the accepted consequence of D2, not a leak.

**Fallback if this proves awkward in implementation:** wrap the historical key set as one
opaque bundle blob. Functionally equivalent, less elegant, grows linearly. Do not reach
for it before trying the chain.

**Two consequences that must be surfaced in the UI, not buried:**

1. **Adding someone gives them everything.** There is no partial history. The invite
   confirmation screen must say so in plain language.
2. **Removal is forward-only.** A removed member keeps every message they already
   received, because it is on their disk and always was. Starting a new epoch stops
   future messages and nothing else. Any UI implying otherwise is a lie that could get
   someone hurt.

### 4.4 Module layout

```
parlor/
  Config/                  xcconfig, entitlements
  Sources/
    ParlorKit/             pure logic, platform-free where possible
      Crypto/              identity, device certs, epochs, sealing
      Log/                 feed append, verification, causal merge, fold
      Sync/                packet assembly, mailbox I/O, budget, reconciliation
      Backfill/            candidate race, assignment, chunked transfer (§5)
      Direct/              local peer discovery and transfer
      Model/               Room, Wall, Member, Entry, Extension registry
    ParlorUI/              shared SwiftUI
    App-iOS/  App-macOS/
  Tests/
```

### 4.5 The private organisation layer

Tags, pins and mute are how a member arranges *their own* list. They are not room state, not
membership state, and not part of anyone's history. This is a third category of data alongside key
material and log entries, and it needs saying explicitly because it is the first thing in the design
that is neither.

**The list sorts by most recent, always, with pinned rooms held above it.** Pins carry a manual
order; everything else is recency and nothing else. A pin is a badge on the room's avatar, not a
separate grid or section — a pinned room still reads as a row.

**Tags are private to the member.** They are created on a member's own device, never wrapped into a
sync packet, and never visible to anyone else in the room. Two people in the same room can file it
under entirely different tags, or none, and neither can tell.

See Design Decision P5 for where this state lives and how it merges. The properties that matter above that
decision:

- **Nothing here is ever sealed to a room epoch key or appended to a feed.** Organisation is not
  history. It carries no signature, is never served in a backfill, and a peer requesting your log
  receives none of it.
- **Deleting a tag removes it from your rooms and does nothing else.** It does not leave a room,
  mute it, or change anyone's access. The confirmation copy must say so.
- **Leaving a room drops your organisation of it.** No dangling tag assignments, for the same
  reason Design Decision P2 dissolves group grants into per-member overrides: state that references something
  you have left is state that will be wrong later.
- **Tag names never reach a notification.** See Design Decision P5; this extends the Design Decision P3 ladder.

**Search is local and always will be.** §1.2 rules out server-side search, and there is nowhere
else it could run — the mailbox holds ciphertext. A consequence worth stating now: search can only
find what this device has already fetched, which interacts directly with Design Decision P2's recommendation
that Wall media and older Wall text be fetch-on-view. Deciding to shrink revocation residue is also
deciding that search does not reach the material that was not fetched.

---

Swift 6 language mode, strict concurrency. `ParlorKit` is actor-isolated or `Sendable`
throughout. CloudKit, Network framework, and the clock are all behind protocols with
fakes — a distributed sync engine that can only be tested on two physical devices will
not get tested.

**On structured concurrency:** Swift has it. `withThrowingTaskGroup` plus cancellation on
first acceptable result is the direct analogue of a Java `StructuredTaskScope`
`ShutdownOnSuccess` policy, and it is exactly the right tool for §5's candidate race.
Group children are cancelled when the group exits scope, so the losing candidate requests
tear down without manual bookkeeping.

---

## 5. Backfill protocol (D2, D3)

The distinctive piece. A new member must receive full history, served by whichever peer
is furthest ahead and answers fastest.

### 5.1 Sequence

1. **Request.** Joiner writes `BackfillRequest{roomID, joinerID, requestID, nonce}` to
   the mailbox, addressed to the room.
2. **Offer.** Each member, on their next foreground sync, verifies the joiner is
   legitimately admitted (§6), then writes
   `BackfillOffer{requestID, offererID, headSeqPerFeed, earliestAvailable, sentAt}`.
3. **Race.** The joiner opens a bounded collection window and evaluates offers as they
   arrive. Score by completeness first — how much of the room's known history the offerer
   actually holds — then by observed round-trip latency. First offer that is *complete*
   wins immediately and the window closes early; otherwise take the best at window close.
4. **Assign.** Joiner writes `BackfillAssign{requestID, chosenOffererID}`. All other
   offerers see it and stand down.
5. **Transfer.** Assigned peer sends chunked, sealed bundles. Each chunk is independently
   verifiable and acknowledged. Prefer the direct channel if both peers are reachable on
   a local network; otherwise mailbox.
6. **Resume or reassign.** Chunks are resumable by index. If the assigned peer goes quiet
   past a timeout, the joiner reassigns to the next-best offer and resumes from the last
   acknowledged chunk. The protocol must assume the serving phone gets put in a pocket
   mid-transfer, because it will.

### 5.2 Properties this must have

- **Bounded window, not "wait for everyone."** In a friend group most members are asleep.
  Waiting for a quorum means the joiner sees nothing for a day.
- **Deterministic tiebreak.** Equal completeness and equal latency resolve by lowest
  offerer ID hash. Avoids two joiners flapping between the same two servers.
- **No thundering herd.** Offers are cheap; transfers are not. Only the assigned peer
  uploads.
- **Verification is independent of the source.** Every entry is hash-linked and signed,
  so a malicious or buggy server cannot forge history — it can only withhold. Withholding
  is detectable: the joiner knows the head sequence each feed claimed in the offers and
  can see gaps.
- **Graceful zero-peer state.** If nobody comes online, the joiner sits in an explicit
  "waiting for someone to come online" state with a clear explanation. Not a spinner.

### 5.3 Cost shape

Full history transfer is the single largest data event in the product. Text is
negligible; media is not. Backfill transfers text and metadata eagerly and media lazily
by reference — a joiner gets every message immediately and fetches images on demand.

---

## 6. Joining and the security check (D4)

1. An existing member creates an invite: a one-time, expiring token carrying the room ID,
   the inviter's signature over the joiner's public identity key, and a short verification
   phrase.
2. Invite travels out of band — QR in person, or any channel the two already trust.
3. The joiner presents the inviter's attestation on their first sync.
4. **Each existing member independently verifies** the attestation chain before rewrapping
   epoch keys to the joiner. One member's compromised device cannot silently add someone,
   because every other member checks the signature themselves.
5. Members see the join in-app with the verification phrase and the inviter's name, and
   can refuse. A refusal blocks the rewrap from that member, which is visible to everyone
   — a disagreement about membership should be loud, not silent.

**Fingerprint comparison** (comparing a short hash out of band) is available but not
mandatory. Requiring it kills onboarding; omitting it entirely leaves a hole. Offer it,
prompt for it once, don't block on it.

---

## 7. Extensions (D5)

First-party features, toggleable per room. Architecturally this is a registry of payload
types, each with a renderer and an optional composer.

```swift
protocol ParlorExtension {
    static var typeID: ExtensionTypeID { get }     // stable, never reused
    static var minimumClientVersion: Int { get }
    func render(_ payload: DecodedPayload) -> AnyView
    var composer: AnyView? { get }
}
```

**Versioning strategy is the owner's call and the owner's position is workable.** Shipping
data migrations and versioned payload APIs, with a minimum-supported-version gate that
forces an update, is a normal and effective pattern. Store the minimum supported version
as a single record in the CloudKit public database — it is tiny, it is the one legitimate
public-DB use in this design, and it gives a kill switch for genuinely breaking changes.

Two things remain non-negotiable regardless of update gating, because they are about the
hash chain rather than about rendering:

- **Unknown entries are stored and forwarded verbatim.** An entry a client cannot parse is
  still part of the hash-linked chain. Dropping it breaks verification for every member
  downstream, including members who *can* parse it. This is cheap to implement and
  catastrophic to omit.
- **`typeID` values are permanent and never reused.** Retiring a feature means the decoder
  stays forever; old entries must still render years later. Reuse of a retired ID silently
  misinterprets history.

Softened by the update gate, and therefore recommended rather than required:

- A plain-text fallback string generated at send time, so a lagging client renders "Nora
  posted a poll" instead of a gap. Worth having for the window between a new feature
  shipping and everyone updating, which is hours to days if you gate aggressively.

Every payload still carries `typeID` and a version integer. That is not optional either.

Candidate v1 extensions, all off by default: polls, images, link previews rendered
locally, scheduled events, a shared list.

---

## 8. Epics

**Epic 0 — Skeleton.** Multiplatform project, branding placeholder, CI lint, Swift 6 strict
concurrency, fakes for CloudKit/network/clock. *Exit:* codename absent from source; tests
run in CI.

**Epic 1 — Identity and device certificates.** Ed25519 + X25519, synchronizable Keychain,
per-device subkeys certified by identity. *Exit:* a second device joins the same identity
and both feeds verify.

**Epic 2 — Feed engine.** Append, hash-link, sign, verify, causal merge, fold of
edits/tombstones/reactions. Pure, fully unit-tested, no network. *Exit:* property tests
over random concurrent interleavings converge to identical state on all replicas.

**Epic 3 — Crypto and epochs.** Pairwise secrets, epoch keys, historical chain wrapping.
*Exit:* joiner with the epoch chain decrypts all history; removed member decrypts nothing
after their removal epoch.

**Epic 4 — Mailbox sync.** Packet batching, rotating tags, fetch/ack/delete, write budget with
instrumentation, `CKSubscription` contentless push. *Exit:* two devices converge over
CloudKit; budget ceiling enforced and measurable.

**Epic 5 — Rooms and Wall UI.** The minimum usable product. *Exit:* three people hold a
conversation for a week without data loss.

**Epic 5a — Wall permissions.** Design Decision P2 in full: segmented chains, group grants, global
per-member overrides, the mandatory picker, locked grant points, the upgrade warning, and
the leave-group dissolution flow. *Exit:* a property test asserts that for every sequence
of joins, grants, overrides, and departures, each viewer's derivable segment set exactly
matches their intended entitlement — and never exceeds it. Denied viewers must be
unable to derive any segment root, verified cryptographically rather than by UI state.

**Epic 6 — Invite and join.** Out-of-band invite, independent verification, rewrap on sync.
*Exit:* a fourth member joins and every existing member verified independently.

**Epic 7 — Backfill.** §5 in full: race, assign, chunk, resume, reassign. *Exit:* joiner
receives complete history with the serving peer backgrounded twice mid-transfer.

**Epic 8 — Direct sync.** Local network discovery and transfer, with mailbox fallback.
*Exit:* two devices on the same Wi-Fi sync without touching CloudKit.

**Epic 9 — Media.** Lazy fetch, local thumbnails, per-room retention. *Exit:* a room with
500 images does not blow up storage on a 128GB phone.

**Epic 10 — Extensions.** Registry, fallback strings, per-room toggles, forward-compat tests
against a synthetic "future" client. *Exit:* a client that predates an extension renders
its fallback and re-renders correctly after update.

**Epic 11 — Purchase.** StoreKit 2, one non-consumable, `Transaction.currentEntitlements`, no
receipt server.

**Epic 12 — Notifications and previews.** NSE per Design Decision P3, preview ladder, warning sheets,
opaque thread identifiers, App Group settings store. *Exit:* previews off by default; the
NSE syncs correctly at every ladder level; no room or member name reaches a notification
body at level 0.

**Epic 13 — Recovery.** Design Decision P4: self-signed device revocation and Wall wipe, in-app biometric
lock, threshold social recovery with the 7-day delay and cancel-from-any-device path.
*Exit:* a wipe cannot be authorised by fewer than the threshold; a user holding their
identity is never routed to the social path; every pending recovery is cancellable.

**Epic 14 — Rooms list organisation.** Design Decision P5 in full: private tags and the filter rail, pinned rooms
with manual fractional ordering, mute, the list menu, and edit mode with drag and swipe-to-leave.
*Exit:* two devices of one member converge on the same tags, pins and pin order after concurrent
offline edits; no tag, pin or mute value appears in any packet written to the mailbox, asserted by
a test over the serialised packet rather than by inspection.

**Build order:** Epic 0, Epic 1, Epic 2, Epic 3 (no UI). Then Epic 4, Epic 12, Epic 5 — usable by three people. Then
Epic 6, Epic 7. Then Epic 5a, Epic 13. Then Epic 8, Epic 9, Epic 10, Epic 11. Epic 14's UI can land with Epic 5; its sync half needs Epic 4.

---

## 8.1 Handoff to Claude Code

### Start here

Build Epic 0 first and completely. Do not begin Epic 1 until the codename lint passes in CI and
`ParlorKit` has a test target that runs with no device and no network.

### Working agreements

1. **Do not start an epic whose blocking open questions are unresolved.** §9 marks them.
   If an unresolved question surfaces mid-epic, stop and write it into §9 rather than
   picking an answer silently.
2. **Do not relitigate §2 or the ADRs.** They are decided. If implementation reveals one
   is wrong, write a new ADR recording what changed and what invalidated the old one —
   never edit a decision in place.
3. **`ParlorKit` takes no UI dependency and no direct framework dependency.** CloudKit,
   the Network framework, the Keychain, the clock, and the random source all sit behind
   protocols with fakes. A sync engine testable only on two physical devices will not get
   tested, and the bugs this project fears most live exactly there.
4. **Swift 6 language mode, strict concurrency, no exceptions and no `@unchecked
   Sendable` escape hatches.** Actor-isolate state rather than reaching for locks.
5. **Never commit a `TODO` in crypto, key wrapping, or permission-resolution code.** If it
   is not finished, it does not merge. Incomplete code in those three areas fails silently
   and looks fine.

### Correctness before interface

Epic 1 through Epic 3 have no UI at all. That is deliberate. The feed engine, the epoch chains,
and the permission resolver are pure functions over data and are the only parts of this
system where a bug is both invisible and unrecoverable. Property tests come with the code,
not after it.

Minimum property tests before any UI work begins:

- **Feed convergence.** Any random interleaving of concurrent appends, edits, tombstones,
  and reactions converges to identical rendered state on every replica.
- **Room chain.** A joiner at epoch `k` derives every epoch `≤ k` and no epoch `> k`.
- **Wall segments.** For every sequence of grants, overrides, joins, and departures, each
  viewer's derivable segment set exactly equals their intended entitlement. Denied viewers
  derive nothing — verified against the key material, never against UI state.
- **Replay.** Stale ciphertext replayed under a new session fails to open.

### Two failure modes that would sink this project

**Silent divergence.** Two members' devices disagree about history and neither knows. This
presents to users as "I definitely sent that" and destroys trust faster than any crash.
Every entry is hash-linked and signed precisely so divergence is detectable — surface it
in a debug view from Epic 2 onward, and never suppress a verification failure.

**Over-promising in copy.** Three places where the implementation guarantees less than
plain language implies: revocation residue (Design Decision P2), Wall wipe (Design Decision P4), and screenshot
blocking. UI strings in those flows are part of the security design. Route any new copy in
them through the owner rather than writing something reasonable-sounding.

### Definition of done, per epic

Code, tests, the exit criterion in §8 demonstrably met, and any new decision recorded as
an ADR. An epic with passing tests and no ADR for a decision it made is not done.


---

## 9. Open questions

| ID | Question | Blocks | Resolution path |
|---|---|---|---|
| Open Question 1 | **Resolved — see Design Decision P1.** Do not use the public database as the mailbox. Each member owns a shared zone acting as their own outbox; storage bills to that member's iCloud quota and costs the developer nothing. | Epic 4 | Implement per Design Decision P1; verify quota attribution on a real account. |
| Open Question 2 | **Resolved by owner.** Volume is expected to be small: aggressively optimised payloads, mostly text with some images, **groups capped at 25 members for v1**. Still instrument the write budget from the first build — the cap makes overrun unlikely, not impossible, and the measurement costs nothing. | Epic 4 | Instrument and confirm in TestFlight. |
| Open Question 3 | **Resolved — see Design Decision P3.** Do not use silent push. Use `CKDatabaseSubscription` with `shouldSendMutableContent` and a generic alert body, and do the fetch and decrypt in a Notification Service Extension, which runs for every visible push. | Epic 4 | Implement per Design Decision P3. Prototype the 30-second budget against a realistic packet. |
| Open Question 4 | **Resolved by owner: backfill includes text and media.** Consequence: a joiner's first sync may be very large. Transfer text first so the room is usable immediately, then media in the background of the same session, resumable. | Epic 7, Epic 9 | Implement staged backfill; cap per-room media retention. |
| Open Question 5 | **Resolved by owner: the Wall inherits from shared rooms**, with global per-member overrides. Old-Twitter shape: thoughts, links, images, songs, comments, emoji reactions. | Epic 5, Epic 5a | See Design Decision P2 for the full permission model. |
| Open Question 6 | **Superseded.** The question was whether Keychain sync makes device pairing redundant on a shared Apple Account. It does: the identity key signs device certificates and iCloud Keychain already carries it, so a new device certifies itself and needs nothing from the old one. The audit trail this asked to preserve is unaffected — every device still publishes a certificate and can still be revoked. The pairing flow is deleted (§9.2 row 120). | Closed | None. |
| Open Question 7 | **Resolved by owner.** Device loss is survivable: identity lives in iCloud Keychain, other members hold the content, group state is replicated. Keychain reset is not survivable, and that is accepted. | Epic 1 | See note below. |

**Note on Open Question 7.** One correction to the recovery picture: after a Keychain reset the user
cannot sign as their old identity, so they return as a **new participant**. Their previous
Wall entries remain readable by whoever already had access — those entries do not vanish —
but the old feed is permanently closed and cannot be appended to. Recovery is: new
identity, re-invited to each group, re-granted Wall access by each member. Handle
`CKError.zoneNotFound` as the trigger and present this clearly rather than as an error
state. It is rare, unrecoverable, and the user deserves a plain explanation of what
survived and what did not.

---

## 9.1 Architecture Decision Records

### Design Decision P1: Per-member shared-zone outbox, not a shared public database

**Context:** who pays for CloudKit. The public database is billed to the developer against
a tight free tier whose pricing page Apple removed and has not replaced. A chat-shaped
workload is exactly the wrong thing to put there.

**Decision:** every member owns a CloudKit **shared zone** in their own private database,
functioning as their outbox. Other members are participants. Storage and transfer bill
against each member's own iCloud quota. Developer cost is zero and stays zero at any user
count.

**On identity disclosure:** `CKShare` participants are exposed as `CKUserIdentity` with
name and lookup info. This is what disqualified `CKShare` for the location project. Among
friends who already know each other's names, it is a non-issue.

**On invite friction:** adding participants by email or phone lookup is friction the
out-of-band invite flow (§6) already avoids. Distribute the share URL inside the invite
instead. A leaked share URL yields ciphertext only — payload encryption is doing the real
access control, and the share is a transport boundary, not a security boundary. Never
describe it as one in code comments or UI.

**Remaining public-database use:** exactly one record holding the minimum supported client
version (§7). Nothing else.

### Design Decision P2: Wall visibility is group-granted with global per-member overrides

The Wall is not a room. It has its own permission system, specified here in full.

#### Permission values

A viewer's access to your Wall is one of:

| Value | Meaning |
|---|---|
| `none` | Cannot see the Wall at all. |
| `new(from: SegmentID)` | Can see posts from a fixed point forward. The point is **locked at grant time** and never moves. |
| `historical` | Can see everything. |

#### Two-layer resolution

1. **Group grant.** When you join a group you set one value for that whole group.
2. **Per-member override.** Before the group grant applies, you are shown every member of
   that group — searchable, paginated — and may set an individual value for anyone.

**Resolution rule: an explicit member override always wins, globally, over every group
grant.** Overrides are keyed by member, not by (member, group). If you deny Dave, Dave is
denied everywhere, including in groups you join later. Where no override exists, the
effective value is the most permissive applicable group grant.

This makes the mental model one sentence: *groups set the default, people set the truth.*

**Overrides are global, and the UI must say so at the moment of change.** When a user
changes an override for someone who currently has access through another group, prompt:
name the other group, state the person's current effective access, and state plainly that
the change applies everywhere. Per-context overrides are explicitly rejected — a Wall is a
single personal surface and "Lisa sees my Wall in group A but not group B" is incoherent
for a thing that is not scoped to a group in the first place.

#### The picker is mandatory, not optional

The member list is presented **before** the grant applies, on every group join, for every
grant value including `none`. Choosing `none` for a group still shows the picker, because
that is where you grant Fred `historical` and Gerry `new` (the owner's second-group case).

Requirements: search by name, paginated list, per-row three-way control, bulk actions for
the whole list, and a running count of who will gain access. Never apply a grant without
the user having seen who it affects.

#### Locked grant points and the upgrade warning

`new(from:)` locks its start point permanently. If you later change a viewer from `new`
to `historical`, the app must warn explicitly — naming that posts before the locked point
were previously hidden from this person and are about to become visible. This is the
Lisa case and it is the single most important confirmation dialog in the product. It must
name the person, show the date, and default to cancel.

#### Leaving a group

On leaving, ask: **revoke group-level Wall access?**

- **Yes.** All group members lose access on next sync, *except* anyone with an explicit
  override. Then immediately show the surviving overrides for review, so the user sees who
  still has access and can change it in place.
- **No.** Ask a second question: keep allowing new posts, or stop at today?
  - *Stop at today* converts each affected member to an override pinned at the current
    segment — they keep what they had, see nothing further.
  - *Keep allowing* converts each to an override at their existing value.

Either way, **the group grant dissolves into per-member overrides.** There is no dangling
grant referencing a group you left. State this in the doc and in the code comments,
because it is the thing that keeps the resolution rule simple forever.

Overrides survive departure unchanged unless the user edits them during the review step.
In that review list, annotate anyone you still share another group with — "also in
Thursday Climbing" — so the user understands why leaving one group did not end the
relationship. Do not block on it or force a decision; most people follow this flow
intuitively and the annotation is there for the ones who don't.

#### Cryptographic consequence — the reverse chain does not work here

§4.3's reverse hash chain gives a joiner one secret from which all *earlier* epochs
derive. That is exactly right for rooms and exactly wrong for the Wall, where
`new(from:)` requires the opposite: access forward from a point, with earlier posts
unreachable. A forward chain inverts the problem but makes revocation impossible, since
holding any link derives every future link forever.

Neither single chain supports a floor *and* a ceiling. **The Wall therefore uses segmented
chains:**

- Wall key material is an ordered list of independent reverse-chain **segments**.
- A new segment begins whenever any `new(from:)` grant is issued or any access is revoked.
- A viewer's entitlement is the set of segment roots they hold. `historical` means all
  segments; `new(from: k)` means segment `k` and every segment created after it; `none`
  means no roots and no further wraps.
- Revocation is: start a new segment and never wrap its root to that member.
- Granting Lisa `historical` later means handing her the earlier segment roots — which is
  precisely the operation the warning dialog above is describing.

Segment count grows with permission changes, not with post volume. Dozens of 32-byte
roots over years is nothing. Do not attempt to reuse the room chain construction here.

#### What revocation actually guarantees

Revocation is enforced by **two independent gates**, neither of which depends on the
revoked person's client cooperating.

**Gate 1 — key wrapping.** Revocation is not a message instructing their client to stop.
It is the absence of an operation: a new segment begins and its root is never wrapped to
them. Everything posted afterwards is sealed under a key they cannot derive. A modified
client, a jailbroken device, and a packet capture all get the same result: ciphertext.
This gate is absolute and requires no trust and no particular sync ordering.

Do **not** implement revocation as sync-order enforcement — "they receive the revocation
before they receive the content." That is defeatable by any client that reorders or
ignores the revocation record, and it is unnecessary given Gate 1.

**Gate 2 — outbox share removal.** Content posted *before* revocation is sealed under
segments they legitimately hold, so keys cannot help. What can: remove them as a
participant from your outbox shared zone (Design Decision P1). They can no longer fetch ciphertext
they have not already downloaded.

The residue is exactly one category: **content they already fetched.** That is bytes on
their disk and nothing can retract it. Lazy fetch shrinks this category directly — the
less a viewer has pulled down in advance, the more Gate 2 covers. Recommend Wall media,
and Wall text beyond a recent window, be fetch-on-view. This is a deliberate divergence
from D2, which governs rooms.

UI copy must not promise more than this. "They will no longer be able to see your Wall" is
accurate. "Your posts will be deleted from their phone" is not.

#### Screenshot blocking — implement it, don't rely on it

Two different mechanisms get conflated here, and the distinction matters for what is
available to this app.

**MDM restriction.** Managed devices can disable screenshots outright via a device-level
restriction. This is why enterprise-secured apps appear to block them. It requires
supervision or MDM enrollment and is not available to a consumer App Store app.

**The `isSecureTextEntry` layer.** Hosting content inside a `UITextField` configured for
secure entry causes it to be omitted from screenshots and screen recordings. Major
consumer apps ship this in production and it works. It is undocumented behaviour, it has
broken across OS releases before, and developers have asked Apple directly whether it
carries App Review risk under guideline 2.5.1 without a clear answer.

**Decision: ship it.** Apply it to Wall content and room message content. Also register
for `UIApplication.userDidTakeScreenshotNotification` so the app can note the attempt, and
apply `.privacySensitive()` for app-switcher redaction.

**Constraint: nothing in the permission model may depend on it.** Treat a break on a
future iOS release as a cosmetic regression, not a security incident. Never describe it in
UI as protection. The honest and sufficient claim is the owner's: the app controls
visibility and revocation, and a viewer with a second camera is out of scope. Put that
sentence in the privacy screen and leave the mechanism undiscussed.

---

### Design Decision P6: Epoch history uses wrapping, not the reverse hash chain in §4.3

**This supersedes the construction in §4.3, "Key consolidation: a reverse hash chain."** §4.3 is
left as written per §8.1.2; this record says what changed and why.

**The flaw.** §4.3 defines `S_n = H(S_{n+1})`, generated backwards from a random terminal secret
`S_N`. Holding `S_k` yields every earlier secret, which is the property D2 needs. But *using* epoch
`k+1` requires possessing `S_{k+1}`, and `S_{k+1}` is by construction underivable from `S_k` — that
one-wayness is the whole point. So `S_{k+1}` can only come from stored forward material, and:

- If every member retains the forward chain, a removed member retains it too, and can derive every
  future epoch. Forward-only removal is not enforced at all — the property the construction was
  chosen for is the one it loses.
- If only some members retain it, advancing the epoch requires one of them to be reachable, which
  contradicts the offline-first design and D4's "every existing member wraps the new epoch secret."
- §4.3's own instruction — "discard the rest of the forward material immediately" — leaves the room
  permanently at epoch zero, because nobody can produce `S_1`.

**Decision: historical chain wrapping**, which is the construction §8's own epic name for Epic 3
describes. Each epoch secret is fresh randomness. Advancing to epoch `k+1` publishes a link:

```
E_{k+1}  = random
link_{k+1} = AEAD(key: KDF(E_{k+1}, room, k+1, "wrapping"), plaintext: E_k)
```

Links are public and live with the room. Payloads seal under a *separate* derivation,
`KDF(E_k, room, k, "sealing")`, so the key protecting the previous secret is never the key
protecting this epoch's messages.

**Every property §4.3 wanted, kept:**

- **A joiner receives one value.** Epoch `k`'s secret plus the public links walks back to epoch
  zero. History costs one wrapped secret, not a bundle that grows forever. D2 satisfied.
- **A removed member gets nothing later.** `E_{k+1}` is fresh randomness wrapped under itself.
  Holding every earlier secret *and* every link reveals nothing about it — this is asserted
  directly, including the case where the removed member has the new link in hand.
- **Forward-only removal is now genuinely cryptographic**, which under §4.3 it was not.

**And three problems that simply stop existing:**

- No ceiling `N`, so no exhaustion case to handle.
- No chain root, so nothing that must be destroyed and nothing that leaks by being retained.
- No forward material in existence at any moment.

**Cost.** One small public record per epoch, stored with the room — a few dozen bytes, fetched only
when a joiner backfills. §4.3's "fallback" of an opaque growing bundle is not needed; this is
strictly better than both options it considered.

**Consequence for the UI, unchanged from §4.3:** adding someone still gives them everything, and
removal still stops only what comes next. Both must be said in plain language where the decision is
made.

### Design Decision P5: Tags, pins and mute are member-scoped and sync through the member's own private database

**Context:** the wireframes introduce a private organisation layer — user-defined tags, a filter
rail, manually ordered pins, and mute. The board's own copy says tags live "on this device only".

**The problem with that reading.** §4.1 goes to considerable trouble to make a member experience one
identity and one history across their devices; per-device feeds exist precisely so the user never
meets the seam. Device-local tags reintroduce it in the most visible place in the app: your phone
and your Mac would show a different filter rail, different pins, and a differently ordered list.
That is the same class of "which device am I on?" confusion the rest of the design refuses.

**Decision: the organisation layer is scoped to the member, not the device, and syncs through the
member's own CloudKit private database — not the shared outbox zone of Design Decision P1.**

- No other member is ever a participant in that zone, so the privacy property the copy promises is
  unchanged and unweakened: nothing is wrapped into a packet, and nobody in the room can see how you
  have filed it.
- The UI copy changes from "on this device" to "on your devices". That is the only copy change this
  decision forces, and it must be made — the current string would be false.
- Organisation never enters a feed. It is not signed, not sealed to an epoch, and not served in a
  backfill. A peer requesting your history receives none of it.

**Merge rule, because two devices can now disagree.** Each assignment is a last-writer-wins register
keyed by (room, tag) with the member's own device clock as the tiebreak, which is safe because every
writer is the same person and the loser of a race is never someone else's intent. Pin *order* is the
one field where last-writer-wins is unsatisfying — reordering on two devices while offline discards
one arrangement wholesale. Order is therefore stored as a per-room fractional index rather than an
array, so two devices moving different pins commute and only a genuine conflict over the same pin
resolves by device clock.

**Mute is part of this layer** and follows the same rule. It is deliberately *not* the same control
as the Design Decision P3 preview ladder: mute silences delivery of a room's notifications, the ladder governs
how much plaintext a delivered notification is allowed to carry. A muted room still syncs.

**Extension to Design Decision P3: tag names never reach a notification body, at any rung of the ladder,
including level 4.** The ladder's rungs each name a category of plaintext the user has chosen to
expose to iOS's notification cache. Tags are not in any of those categories — they are a private
layer the user has not shared with a single other person, and a tag is exactly as revealing as a
room name and often more so. This is a hard rule, not a default.

**What this does not cover.** Per-tag notification rules — silencing everything tagged `Reading` —
are a reasonable future feature and would live here rather than in the ladder. Not v1.

### Design Decision P3: Sync runs in the Notification Service Extension, not on silent push

**Context:** §3.2 assumed background sync was effectively unavailable, because silent
pushes wake an app one to two times an hour and never after force-quit. The owner's
counter-proposal — ping for changes, pull from the most up-to-date device online — is
correct, and the mechanism that delivers it is a Notification Service Extension.

**Finding.** Apple DTS, answering a team building an end-to-end encrypted workplace app
with exactly this problem: there is no need to send silent notifications and no
entitlement is required; decryption belongs in a `UNNotificationServiceExtension`, and
**the extension is executed for every visible push notification**. The one stated
condition is that the user has not disabled notification visibility, in which case the
whole mechanism is moot.

This is the difference between one or two wakes an hour and one wake per incoming packet.

**Decision.**

1. Each member holds a `CKDatabaseSubscription` on the shared database. One subscription
   covers every member's outbox zone — this does not scale as N², and a 25-member cap is
   comfortably inside it.
2. `CKNotificationInfo` sets `shouldSendMutableContent` and a **static, generic**
   `alertBody` ("New message"). No content, no sender name, nothing derived from the
   record. CloudKit never sees plaintext and neither does APNs.
3. The push arrives. iOS invokes the NSE. The NSE fetches the pending packet, decrypts it
   with keys from the shared Keychain, writes entries into the shared-container store, and
   rewrites the notification body with the real content.
4. Opening the app finds the data already local.

**This is real background sync.** Not a freshness optimisation — an actual pull triggered
by the author's write, with no server of the owner's and no polling.

**Constraints.**

- The NSE gets roughly 30 seconds and a hard memory ceiling. Text packets: fine. Media:
  fetch a thumbnail at most, defer the rest. Never attempt backfill in the NSE.
- On timeout, iOS displays the original generic notification. Degradation is graceful and
  the entry syncs on next foreground open. Design for this rather than fighting it.
- If the user disables notifications for the app, background sync stops entirely and
  behaviour reverts to §3.2 foreground-only. Say so in settings rather than letting them
  conclude the app is broken.
- Keep `BGAppRefreshTask` (§3.2.1) as a secondary catch-up path for missed pushes.

**Privacy cost that must be surfaced to the user.** Decrypting into a notification body
writes that plaintext into iOS's own notification store, which the app does not control.
Forensic examiners have recovered Signal message previews from that cache *after the app
was deleted* — content Signal had encrypted end-to-end and decrypted only locally.

#### Preview ladder

Sync and preview are **independent settings**. The NSE always runs and always syncs; the
preview setting governs only what it writes into the notification body. Implement as a
ladder, because each rung leaks a strictly larger set of plaintext into a store outside
the app's control.

| Level | Body | Plaintext reaching the iOS cache |
|---|---|---|
| 0 — Off (**default**) | "You have new messages" | Nothing. |
| 1 — Groups | "You have new messages in Thursday Climbing" | Room names. |
| 2 — Senders | "You have new messages from Dan" | Member display names. |
| 3 — Both | "You have new messages from Dan in Thursday Climbing" | Both. |
| 4 — Full | Sender, room, and message content, as iMessage does | Everything. |

Levels 1 and 2 are independent toggles; level 3 is simply both enabled. Level 4 is a
separate switch that supersedes them.

**Do not treat levels 1–3 as safe.** A room named for a medical condition, a support
group, or a person leaks as much as a message body would. The warning copy must say this
rather than reserving the caution for level 4.

**Warning presentation.** On enabling any level above 0, present a bottom sheet:

- A one-line statement of what this level exposes, phrased for that specific level.
- A collapsed disclosure — "Why this matters" — expanding to the Signal case: forensic
  examiners recovered decrypted message previews from iOS's notification cache after the
  app had been deleted, because the cache belongs to iOS and the app has no authority over
  it. Keep it short, factual, and unsensational. No fear-mongering; the fact is enough.
- Confirm and Cancel, defaulting to Cancel.

Show the sheet on every increase in level, not only the first. Moving from 1 to 4 is a
different decision from moving from 0 to 1.

**Per-scope settings.** The ladder is set per room and separately for the Wall. Wall
defaults to level 0 and stays there unless explicitly changed — Wall content is personal
by construction and is the worst thing to leak into a cache.

**Implementation notes.** The NSE reads these settings from the shared App Group
container, so they must be written there and not to a store only the main app can reach.
Notification `threadIdentifier` values must be opaque hashes, never room names — a thread
identifier is metadata that persists in the same cache.

### Design Decision P4: No service account. Device loss is self-authorised; identity loss is social.

**Context:** the owner proposed a hyper-secure service account able to wipe a lost user's
Wall, gated on genuine identification.

**Decision: do not build it.** The capability is unnecessary for the common case and
unacceptable for the rare one.

#### Why it is unnecessary

Losing every device does not lose your identity. Signing keys live in synchronizable
Keychain, so a replacement device restores them from the Apple Account. You still hold
your own key, which means **you can sign the wipe instruction yourself.** It is ordinary
revocation from Design Decision P2, self-authorised, no external authority involved.

Requirements:

- An "I no longer have my other devices" flow that revokes every device certificate except
  the current one, advances every epoch, and issues a signed Wall wipe instruction.
- Reachable on first launch of a new device, before any other setup, because that is when
  the user is looking for it.

#### Why the stolen-phone threat is already handled

The thief has *your* device with *your* content. Other members' devices are irrelevant to
that threat. The defences are device-level and already excellent: passcode, iOS Data
Protection, and Find My remote wipe. Add an in-app biometric lock with a short grace
period. Do not reimplement any of this.

#### The only genuinely unrecoverable case, and how peers handle it

If the Keychain is reset, the identity key is gone and nothing can authenticate a wipe
request. A service account would be a permanent authority over every user's device,
social-engineerable, and the single most attractive attack target in the system —
purchased to cover a rare event.

The precedent is unambiguous. Signal states plainly that they do not know your PIN and
cannot reset or recover it for you, and that a PIN cannot recover lost chat history;
beyond that, recovery is a 7-day inactivity timer on the registration lock, not a human
unlocking the door. WhatsApp's human-mediated path deactivates the account — it does not
reach into other people's devices to delete content, and no major messenger offers that.
Across the surveyed field, recovery codes are the standard mechanism, used by 11 of 14
providers; trusted-operator override is not.

**Chosen mechanism: social recovery, which matches this product's trust model exactly.**

- A Wall wipe may also be authorised by a threshold of the user's group members — a
  majority of one shared group, minimum three signers.
- Signers verify identity the way friends actually do: out of band, because they know the
  person.
- The authority is scoped to **delete the requesting member's own content, and nothing
  else.** It cannot read, cannot add a device, cannot post, cannot alter permissions.
  Enforce the scope in the verification code, not by convention.
- Mandatory 7-day delay, matching Signal and WhatsApp practice, during which every device
  still holding the identity is notified and any one of them can cancel. This is what
  makes collusion loud rather than silent.
- If the user still holds their identity, the threshold path is not offered. Self-signing
  is always preferred and always sufficient.

#### What a Wall wipe actually accomplishes

Members who already read the content have already read it. A wipe removes the app's stored
copy on honest clients and nothing more. Present it as hygiene, not as retraction, and
never imply the content becomes unrecoverable. Same honest-actor class as Design Decision P2's
revocation residue, and the UI copy must be consistent with it.

## 9.2 Outstanding work

What has been built, and what each epic still owes. Maintained as slices land; the detail behind
each line is in `docs/PROGRESS.md`.

### Built

**Epic 0 — Skeleton.** Complete. Module layout, `Config/Branding.xcconfig`, branding lint, Swift 6
strict concurrency, protocol seams with fakes, headless test target.

**Epic 1 — Identity and device certificates.** Complete. Ed25519 + X25519, derived participant and
device identifiers, device certificates with forward-only revocation, self-enrolment of a new device
from the identity iCloud Keychain already carries, Keychain persistence at the correct scopes.

**Epic 2 — Feed engine.** Complete. Hash-linked signed entries, verification against the device
registry, causal merge with a deterministic tiebreak, fold of edits, tombstones and reactions,
fork detection.

**Epic 3 — Crypto and epochs.** Complete. Pairwise secrets with rotating recipient tags, epoch secrets
with historical chain wrapping (Design Decision P6), and payloads sealed under the epoch key. `Entry.payload`
is ciphertext; the signature and hash cover it, so a peer verifies and forwards without reading.
What stays in the clear is asserted field-by-field against the serialised entry.

**Epic 6 — Invite and join.** Complete in code, unverified over CloudKit. §6 end to end: an out-of-band attestation, each
member verifying it independently, the inviter advancing the epoch (Build Decision D32), and the
new secret rewrapped to everyone owed one. A joiner receives two values and walks the room's whole
history back from them. Two devices with separate Keychains, log files and replicas converge
through a mailbox neither trusts.

The join loop closes through the UI: a joiner redeems an invite, verifies it against the keys it
carries with the spoken phrase as the check, accepts the inviter's outbox share, and syncs.

**What no test has ever run is CloudKit itself** — `put`, `fetch`, `acknowledge`, `shareURL` and
`accept` are written and unexercised. Epic 4's exit, "converge over CloudKit", is proven against the
in-memory mailbox and the seam above it and nowhere else. The macOS build embeds the entitlements a
simulator strips, so that is where it can finally be tested, with two Apple Accounts.

### Owed, and when

Every deferred item, with the epic that will pick it up. "Now" means the current slice. Nothing on
this list is allowed to be discovered late — if a slice adds a deferral, it adds a row here at the
same time.

| # | Outstanding | Lands in | Severity |
|---|---|---|---|
| 1 | ~~Comments.~~ **Done.** `PayloadType.comment` names the entry it answers, so a thread is a fold rather than a stored tree (Build Decision D26). | Epic 5 | Resolved. |
| 2 | ~~`OutpostPost.id` is not the entry hash.~~ **Done.** `PostID` wraps an `EntryHash` (Build Decision D27). | Epic 5 | Resolved. |
| 3 | ~~No sync from the UI.~~ **Built, unverified.** `CarpenterCloudKit` is linked, `CloudKitMailbox` is constructed in the composition root, and sync runs on open and on pull-to-refresh. Nothing has exercised it against a real account. | Epic 6 | Reduced to row 8. |
| 3a | ~~The joiner has no way in.~~ **Done.** `RedeemInviteView` is wired to onboarding, and the attestation carries the inviter's keys so a joiner can verify an invite with no prior knowledge (trust on first use, with the phrase as the check). Camera scanning is still row 14a. | Epic 6 | Resolved. |
| 4 | ~~Rooms have one member.~~ **Done.** Attestations, per-member admission and refusal all fold from the log; a room's member count is the viewer's own. | Epic 6 | Resolved. |
| 5 | ~~Device certificates are not persisted.~~ **Done.** They travel in the packet body (Build Decision D34) and are written to `PersistedState`. Without that a relaunch rejected every entry a peer had ever sent, because an entry is signed by a device key and the rebuilt replica knew only its own. | Epic 6 | Resolved. |
| 6 | ~~No epoch distribution.~~ **Done.** `EpochGrant` carries two values — the current secret and the current link — and every earlier epoch is recovered from links already published in the room. The inviter advances (Build Decision D32). | Epic 6 | Resolved. |
| 117 | **Resolved — device sync is part of a sync round.** `refreshDeviceSync()` was called only from the scene-phase handler, so pull-to-refresh ran the mailbox and the rendezvous and left this member's own devices unasked — the one gesture everybody expects to fetch new messages fetched everything except those. `SyncRound` now runs three independent halves, and becoming active and pulling to refresh do the same three things (Build Decision D116). | Closed | Fixed and unit-tested; not demonstrated on device, because row 118 stops the gesture being made at all. |
| 118 | **Resolved — pull-to-refresh works on a short rooms list.** `RoomsListView`'s scroll view carried `.scrollBounceBehavior(.basedOnSize)`, so with fewer rooms than fill the screen it did not bounce and the gesture could not start — hiding row 117's fix on exactly the small accounts most likely to need it. Now `.always`, so the list bounces and the gesture is there regardless of how few rooms exist. | Closed | None. |
| 119 | **Sync is not near-real-time, and a device that is already open never learns anything.** Measured across three runs: a write reaches the server in ~0.5s and reaches the other device ~0.97s after it becomes active — but nothing pulls. Two devices sitting open on the same account do not see each other's messages at all; one sat 60 seconds with the app in the foreground and received nothing. This is Owner Decision D1 working as written, and it is worth stating plainly because "syncs when you open it" turns out to mean *becoming* active rather than *being* active. | Epic 4 | Owner's call. Design Decision P3's extension is the route to changing it (§9.2 row 38). |
| 145 | **Resolved — two database subscriptions were competing, one of them silent.** The diagnostic finally ran and settled it: `CKSyncEngineDatabaseSubscription-Private badge=false` alongside `outpost.sibling-feed.v1 badge=true`. Our flags had survived — the engine never overwrote them — but its own subscription from before we supplied an identifier was still live, so CloudKit could satisfy a change with the budgeted one. Saving ours now deletes every other subscription on the database. | Owner to measure | The badge theory is still unproven; this is the first run where it can be. |
| 146 | **Resolved — checking for a registration comes first, and blocks.** It only appeared when CloudKit had already answered, so on a fresh install the welcome screen won the race and a member could start making a second identity while iCloud Keychain was still delivering the first. `load()` now always lands on the checking screen when there is no identity, and `settleRegistration()` resolves it: the key arriving moves on, an empty account offers onboarding, and **an account that already has a member holds the screen indefinitely** rather than ever offering a fresh start. | Closed | None. |
| 147 | **A frozen clock made a wait loop run forever.** `settleRegistration` bounded itself with `clock.now`, which is injected and fixed in tests, so the first version never terminated — two test runs hit the harness timeout. Elapsed real time and domain time are different things and only one of them is safe to inject; the wait is bounded by attempts now. | Closed | Worth remembering: the injected clock is for timestamps, never for measuring duration. |
| 155 | **Resolved — the app could not build in Release, so it could never archive for TestFlight.** Two debug-only symbols were referenced from production code, which Debug tolerated (it compiles the `#if DEBUG` blocks) and Release did not. `Fixtures.editingDevice` — a preview constant — stamped every organisation edit (pin moves, tag creation); besides breaking Release it was a correctness bug, because a *constant fake device* defeats the tie-break that lets two of a member's devices reorder the same list without one silently winning. It is now the real device id, threaded as an `@Entry` environment value (`\.stampDevice`) the composition root supplies from `enrolment.device.id`. And `registrationProbeURL`, read at launch to ask whether the account already has a member (row 148), was trapped inside an `#if DEBUG` block; moved out. Release now builds on both platforms. A privacy manifest was added (UserDefaults, reason CA92.1; nothing collected for the developer), pending an owner review against the App Store Connect questionnaire. | Closed | Found only by actually running a Release build — worth doing in CI so it cannot regress. |
| 154 | **Resolved — the "Tint the bars" switch works.** It did nothing, not even toggle: `YouView` passed the appearance screen `AccentPickerView(accent:)` without forwarding `tintsChrome`, so the `Toggle` bound to the initializer's `.constant(true)` default — a dead binding. `YouView` now forwards `tintsChrome: $tintsChrome`, which is already wired to the `ThemeStore` (persisted to `UserDefaults`, re-themes live), so the switch flips, sticks, and the bars change while you watch — row 144's feature, actually reachable. | Closed | None. |
| 153 | **Built and wired, unverified on device (Phase 4 of layered sync / Design Decision P3) — a decrypting notification service extension.** `CarpenterNotificationService` reuses `AppSession` to load the shared App Group storage, sync the mailbox, and read the newest message from someone else, then renders it through `MessageNotification` (room, author, text; generic on any failure). `StorageLocation` prefers the App Group container and falls back to Application Support, migrating across once, non-destructively (tested). The identity reaches the extension through `SystemKeychainStore.mirror(toAccessGroup:)` — a **copy** into the shared keychain group that never touches the app's own copy, so it cannot lose the identity; the worst case is the extension stays generic. Both targets declare the App Group and the `com.microgpt.carpenter.shared` keychain group; iOS embeds the extension, macOS excludes it by a platform filter (notification service extensions are iOS-only, and the Mac is covered by rows 151–152). Both platforms build and 429 tests pass. **What is unverified:** keychain access groups do not behave on a simulator, so whether the extension actually reads the mirrored identity and decrypts must be confirmed on a device — with a second account, since the inbox push is cross-member (row 151). | Owner to verify on device | Non-destructive by construction; the residual risk is "banner stays generic", not "identity lost". |
| 152 | **Built (Phase 2 of layered sync) — active-usage sync, which reverses the "no polling" rule by owner direction.** "Reasonably realtime" is achieved by fetching at the moments a member is actually looking: on arriving at the rooms list (`RoomsListView.onAppearSync`), on opening a conversation, and every **5 s** while a conversation is on screen (`ConversationView` → `ActiveSyncLoop`). The loop is factored out of the view so its cadence and — the part that matters — its *immediate* stop on cancellation are unit-tested with injected time; SwiftUI cancels the `.task` on disappear, so leaving a conversation ends the polling with no stray tick. All triggers call the existing `onSync`, which self-dedupes (`guard !syncing`), so they never stack. This is the rule the original push work was told twice not to add; the owner has now asked for it, weighed against push (backgrounded) and `willPresent` (foreground push) as the belt-and-suspenders for the case those miss. | **Confirmed on hardware** | Measured on the owner's two devices: with a conversation open, a fetch fired every ~6 s (5 s wait + fetch) and pulled a sibling's entries within ~2–5 s untouched. Deliberate reversal of the no-polling decision; bounded to open conversations, 5 s floor to stay clear of CloudKit rate limits. |
| 151 | **Built (Phase 1 of layered sync) — a message push, on the channel that was missing it.** Two transports carry entries and only one had a push: device sync (own devices, private DB) had a silent subscription, while the mailbox (other members' messages, peers' outboxes in the *shared* DB) had none at all — so a message from another person never pinged the device until the app was opened. `CloudKitMailbox.subscribeForInbox()` now saves a `CKDatabaseSubscription` (`outpost.inbox.v1`) on the shared database, **visible** on purpose (alert + sound + `mutable-content`): a push here is somebody messaging the member, which is what a notification is for — the opposite of device sync, which stays silent (row 150). `PushPresentation` maps the subscription id to foreground options so `willPresent` shows a banner for the inbox and nothing for device sync; both still drive the fetch. Notification authorization (`.alert .sound .badge`) is requested once the account is ready. `simctl` confirmed `willPresent` parses the inbox subscription id and fires; two-device background delivery, and the decrypted banner, are Phase 4 (the service extension) and the owner's hardware. | Subscription confirmed; delivery unmeasured | On the owner's hardware the subscription is created cleanly (`inbox: subscribed for message pushes on the shared database`) and message authorization granted. What is still unmeasured needs a *second Apple account* — the inbox channel is for other members by design, so two devices on one account never exercise it (that run only drove device sync). The banner is a generic "New message"; a decrypted sender/room and background pre-sync are Phase 4 (P3, held). | 
| 150 | **Resolved in code — the badge was the bug: it made every push visual, and a visual push does not wake the app.** On real hardware sync still only arrived on refocus. Apple's CloudKit documentation, read at last against the implementation rather than out of `CKSubscription.h` in isolation, is explicit: *"For background delivery, set only its `shouldSendContentAvailable` property to true. If you set any other property, CloudKit treats the notification as high-priority."* A high-priority notification is visual — the system shows it and hands the app no background time; `shouldSendContentAvailable` is what *"wakes or launches an app that isn't currently running"*. So `shouldBadge` promoted every push to a visual one that badged the icon and never woke a backgrounded or unfocused device — exactly the refocus-only symptom. The subscription carries `content-available` and nothing else now; the badge authorization prompt is removed with it (a silent push needs none). The whole badge thread (rows 132, 133, 149; D122, D124) is reversed by D125. The rate-limit the badge tried to escape *is* the background channel's price — silent pushes are budgeted to roughly three an hour — and there is no visual-priority route that also runs code, so this accepts the budget, with foreground and pull-to-refresh covering a dropped burst. | Owner to measure | The mechanism is finally the one Apple documents; delivery rate on hardware is the owner's to measure. |
| 149 | **Corrected by row 150 — the receiving half was built on a wrong premise.** This added a `UNUserNotificationCenterDelegate` so an *alert-type* badge push would reach the app and sync while showing nothing, and `simctl` confirmed `willPresent` fired. But that only ever exercised the *foreground* case; a badged push cannot wake a *backgrounded* app at all, which is the actual goal — so on hardware sync still only arrived on refocus. The delegate is kept as a harmless foreground fallback, but the real fix was to stop sending a badged (visual) push in the first place (row 150). The lesson row 149 itself named — do not conclude from an absence until you have checked the observer — applies once more: `simctl` in the foreground was not the observer that mattered. | Superseded by 150 | The delegate is fine; the theory it served was not. |
| 143 | **Resolved — the desktop sidebar folds, counts and reorders.** Both sections collapse from their headers and stay collapsed, so a long room list can be folded out of the way — the mockup's behaviour. The count moved to `.badge`, which is what was wrong with its padding: the system owns the inset and a number nudged into place by hand never matched. Dragging a room in the sidebar pins it through the same fractional ordering the rooms list uses, so the two views cannot disagree and a concurrent move on another device still merges. | Closed | None. |
| 144 | **Resolved — bar tinting lives in Appearance.** It was a row in the settings list with an explanatory subtitle; it is a facet of the colour, so it belongs on the screen where the colour is chosen, beside the preview that shows what it does. The subtitle is gone — the switch is named for what it does and the bars change while you watch. | Closed | None. |
| 140 | **Resolved — five panels before the name prompt, and a splash for a device that let itself in.** TestFlight testers arrive knowing nothing, and the thing worth knowing — where messages go and who can read them — is invisible. Five panels, each short enough to read without scrolling. The comparison names no company and claims nothing about anyone's cryptography: it describes an account-based service *at best* and *at worst*, both true of the good ones. A second device that enrols itself now says so once, because rooms appearing on a brand-new machine with no setup step invites "how does it know?". | Closed | Owner to confirm the copy. |
| 141 | **Partial — tutorial mode is a setting, and the `?` it promises is not built.** The tour's last panel points at a switch in You, and the switch exists and persists. What does not exist yet is the `?` on each screen or the animations behind it, so the promise is currently ahead of the app. Either build the affordance or cut the sentence before TestFlight. | Epic 4 | **Real, and it is copy making a claim the app does not meet.** |
| 142 | **Resolved — product updates are an e-mail, not a feed.** The owner's first shape was a scheduled fetch of a feed on outpostmessaging.com; that would have told whoever runs the endpoint which installs are alive and how often, which is a usage record created by accident in an app whose claim is that it keeps none. A button composes a mail the member reads and sends. Nothing runs, nothing polls, nothing is observable. | Closed | None. |
| 137 | **Resolved — the Mac is three columns, not a tall phone.** The desktop mockup is a sidebar of destinations, the thing you picked, and a rail beside it. `RootView` now renders `NavigationSplitView` on macOS and the tab bar on iOS, reusing every screen rather than duplicating them — the You screen is shared outright so the two shells cannot drift. Native rather than a hand-built grid, per the owner's standing preference: column resizing, collapsing and state restoration are already correct in the split view and would all have to be rebuilt to match the mockup pixel for pixel. | Closed | Rooms are listed rather than folded to a count; the mockup's collapsible sections are `Section` headers today. |
| 138 | **Resolved — messages carry delivery marks, and a stable identity to hang them on.** One accent dot under your own message means it left this device; two mean somebody read it, with the time in understated text beside them. Dots rather than ticks, because ticks carry WhatsApp's three states and this app can tell apart two. `read` is never produced yet — nothing reports back that a message was read, which is §9.2 row 12 — so it renders correctly and stays unclaimed rather than being guessed at. `MessageID` now wraps the entry hash: it was a fresh `UUID()` on every projection, so nothing could correlate a message with anything about it, including how far it had got (Build Decision D123). | Closed | The `read` half waits on per-peer acknowledgement. |
| 139 | **Resolved — the accent tint is a setting.** The wash across the bars is a taste, not a default everyone shares, so it is a switch in You beside the colour itself. Local, like the accent — it never enters a feed. | Closed | None. |
| 134 | **The dark ground is no longer pure black, and the bars carry the accent.** `#000000` reads as a hole rather than a surface and makes every edge a hard cut on OLED; the ground is now a very dark neutral with a trace of blue, and the content surface sits above it as it does in the light theme. The tab bar and the hand-drawn bars take a low-opacity wash of the member's chosen accent, so the colour they picked reaches the chrome rather than only the controls. Contrast audit still passes. Owner's request. | Closed | None. |
| 135 | **Notifications are explained where the rest of the app is explained.** Outpost now asks for the badge, and the reason is mechanical rather than cosmetic, so "How this works" says what it is for: a badge and nothing else for a member's own devices, proper notifications later for messages from other people. Owner's wording, tightened. | Closed | Owner to confirm the copy. |
| 136 | **Opt-in updates from outpostmessaging.com.** Owner's proposal: a setting to subscribe to feature and security announcements, checked periodically against a feed on the site. Not built, and worth designing carefully — a client that fetches a URL on a schedule is the one piece of this app that would talk to a server the owner runs, which has consequences for §1.1's claims and for what an observer of that traffic learns. | Epic 6 | Real, and needs its own decision before any code. |
| 132 | **Built, unmeasured — the push now carries a badge, to buy it a priority.** Apple states in `CKSubscription.h` that a notification with none of `alertBody`, `soundName` or `shouldBadge` is sent *at a lower priority* — and that priority is the one budgeted to two or three an hour, measured here as two deliveries in ten during a conversation. The subscription is now ours rather than the engine's, carrying `shouldBadge` for the priority and `shouldSendContentAvailable` for the wake, with no alert and no sound. A service extension was considered and rejected: `mutable-content` alone does not invoke one, it needs an alert, and a banner announcing the member's own message from their own phone is wrong (Build Decision D122). | Owner to measure | Real. It is the first thing tried that addresses delivery rather than latency. |
| 133 | **Resolved — the app owns the badge number.** CloudKit increments the badge and offers no way to set a value, so an untouched badge counts sync events — meaningless on its own, and it would corrupt the count once message notifications start setting it. `BadgeCount` computes what the badge should say and the app writes that over CloudKit's increment on every sync round, which `content-available` guarantees runs within about a second even in the background. Today that number is zero, because nothing tracks unread yet; `hasUnread` is hardcoded false in the projection. | Closed | The one place to change when unread arrives. |
| 130 | **Resolved — coming back to the Mac now syncs.** `scenePhase` is SwiftUI's answer to "the app became active" and on macOS it does not reliably change when you click back into a window, so a Mac left open synced once at launch and never again. Clicking the window did nothing, which read as broken sync and was nothing ever asking. Each platform's own notification — `NSApplication.didBecomeActiveNotification`, `UIApplication.didBecomeActiveNotification` — is what fires. | Closed | None. |
| 131 | **Two copies of the macOS app were running at once.** Both from Xcode, sixteen minutes apart, sharing one container: the same log file, the same Keychain device key and therefore the same CloudKit feed record — so each overwrote the other's writes. Nothing in the app notices or prevents this, and while it was true no measurement of sync meant anything. | Epic 3 | Real for development. A second instance should refuse to run, or at least say so. |
| 129 | **Resolved — a feed with no member is verified, not discarded.** Naming the member made a rejection legible; refusing a feed that could not name one made two devices on different builds stop talking entirely, which during development is the normal case and was the owner's. Nothing was being trusted by relaxing it: every entry still verifies against a device certificate signed by this member's identity, and a stranger's does not. The member field makes a rejection legible; it is not what makes it safe (Build Decision D121). | Closed | None. |
| 128 | **Resolved — "start over" erased iCloud and then immediately put it back.** Clearing the cloud while the session was still live meant the next sync republished everything just deleted, so the account looked untouched — which is exactly what the owner saw on their phone. Two debug controls with overlapping effects made it worse: one cleared the cloud, one cleared the device, and neither on its own does anything lasting, because the identity lives in iCloud Keychain and the feeds live in the account. There is now one control. It stops the engine and clears the cloud *first*, then the whole Keychain service — room keys included, since their names live in the state file it also deletes — then the local files, and only then rebuilds the session (Build Decision D120). | Closed | None. |
| 124 | **Push works on device; how prompt it is has never been measured.** Confirmed on the owner's Mac: `push: a sibling wrote something` → `database says 1 zone(s) changed` → `1 record(s) arrived` → `took 2 entries from another device`, in 615ms. So CloudKit does deliver, our handler does fire, and driving the fetch ourselves does work — none of which a simulator can show, because a simulator receives no push at all. One delivery appeared to lag badly, but that was *inferred* from log timestamps on two machines without knowing when the sending device wrote — not a measurement, and it should not have been reported as one. A feed now carries `writtenAt`, and arrival logs the difference, so the next run on the owner's hardware produces a number. Apple documents silent pushes as low priority and budgeted, so some lag is expected; how much decides whether anything else needs to fetch. | Epic 4 | Open, and now measurable. |
| 125 | **Resolved — a device no longer offers a fresh start on an account that already has a member.** iCloud Keychain delivers an identity asynchronously and announces nothing when it lands, so a device opening before it arrived was shown the welcome screen and made a second member. The two then shared one CloudKit zone, fetched each other's feeds and refused every entry in them, silently — a feed you cannot verify integrates to nothing. The account's own private database is now asked first: any existing feed record means a member exists, and the device waits on *"Checking Keychain for existing registration."* rather than offering to make another. An unreachable account still offers onboarding, because a first run must work with no network (Build Decision D118). | Closed | None. |
| 126 | **Resolved — a foreign feed is refused by name, and counted.** A sibling feed now carries whose it is, so another member's record is rejected as a statement rather than by failing to verify entry by entry. `IntegrityReport.feedsFromOtherMembers` counts them; anything above zero means two members are sharing one Apple Account, which should now be impossible. A feed that cannot say whose it is is treated the same way, which is the safe direction (Build Decision D119). | Closed | None. |
| 127 | **Uninstalling a device leaves its feed on the account forever.** `Scripts/reset-device.sh` says it cannot clear iCloud, and it cannot — so every device ever tested is still publishing a record that the survivors fetch and reject. A debug **Erase iCloud** control now deletes the whole `SiblingFeeds` zone, which the next launch recreates empty. | Closed | Debug-only; a shipping account-deletion path is separate. |
| 120 | **Resolved — device pairing is deleted, and adding a device asks the member for nothing.** A device certificate is signed by the identity key, and iCloud Keychain already carries that key to every device on the Apple Account — so a new device certifies itself, and room keys and sibling certificates arrive on the ordinary sync path. Removed: the ephemeral exchange, the spoken string, the sealed transfer, the CloudKit rendezvous, the waiting-device prompt, the `.needsDevice` state and the "I already use Outpost on another device" button. About 900 lines of source and 300 of tests (Build Decision D117). | Closed | None. |
| 121 | **Resolved — macOS was writing keys to the legacy keychain, where they could never sync.** Without `kSecUseDataProtectionKeychain`, `SecItemAdd` on macOS writes to the file-based login keychain, in which a third-party item takes no part in iCloud Keychain syncing — `kSecAttrSynchronizable` is accepted and means nothing. Observed directly: `security find-generic-password` found the identity in `login.keychain-db`, and the Mac and the iPhone were carrying different identities and different rooms while claiming to be one member. **Fixed, and not yet confirmed end to end** — the check needs a name typed on the Mac (§9.2 row 122). | Owner to confirm | The whole no-setup model rests on this. |
| 122 | **The Keychain half of adding a device is unproven on hardware.** Simulators do not take part in iCloud Keychain, and driving the macOS app from a script needs an accessibility permission this environment does not have — so neither harness can watch an identity travel between devices. The check is small: create an identity on the Mac, then run `security find-generic-password -s com.microgpt.carpenter`. Not found means it went to the data-protection keychain and will sync; found means row 121's fix did not take. | Owner to confirm | Real. It is the last unverified link in "one account, one key, many devices". |
| 123 | **Resolved — a sibling's certificate now reaches disk with its entries.** `take` admitted it to the running replica only, so a relaunch rebuilt the replica from the log, found the signing device a stranger, and refused every entry it had written. History arrived and then vanished when the app was reopened. Found by a test written for the enrolment rewrite, not by hand (Build Decision D117). | Closed | None. |
| 112 | **The two-account half of the mailbox cannot be tested here.** Everything peer-to-peer rests on a `CKShare` of each member's outbox zone, and an Apple Account cannot participate in its own share — so the two simulators, which are on one account, can prove the transport but never the sharing. This needs a second Apple Account on a second device before Epic 6 can close. | Epic 6 | Real, and it blocks the last of Epic 6. |
| 7 | **`CKSubscription` push not built.** The share flow now exists — `CloudKitMailbox.shareURL()` creates the zone share, redeeming accepts it, and the URL travels inside the invite — but it is code no test has run. | Epic 12 (push) | Share built and unverified; push expected later. |
| 8 | **Mostly resolved — `put`, `fetch` and `acknowledge` now work against a real account, and did not before.** The read path was a `CKQuery`, and CloudKit's query index is eventually consistent: a packet written seconds earlier was not returned by `fetch`, and `acknowledge` failed to locate it with `unknownPacket`. Both are now off queries — `fetch` reads the zone's change feed and matches the tag on the device, `locate` asks for the packet by name — and a round trip passes every step against the owner's account (Build Decision D112). **`shareURL` and `accept` remain unverified**: they need two Apple Accounts, and CloudKit does not let an account participate in its own share. | Epic 6 | One member's path proven. The cross-account half needs a second account. |
| 9 | **Synchronizable Keychain behaviour unverified, and now load-bearing.** That the identity item reaches a second device on the same Apple Account cannot be tested on a simulator — simulators do not take part in iCloud Keychain. With pairing deleted this is no longer one route among two: it is *the* route, and adding a device works only if it holds. macOS was writing the item to the legacy login keychain, where it could never sync at all; that is fixed (§9.2 row 121) and needs confirming on the owner's hardware. | Epic 6 | Real, and now the thing the whole no-setup model rests on. |
| 10 | ~~No divergence view.~~ **Done.** "History check" on the You page, in every build rather than behind a debug flag — the failure mode is divergence nobody notices (Build Decision D40). Loading also stopped swallowing verification failures, which §8.1 forbids in so many words. | Epic 6 | Resolved. |
| 11 | ~~No identity or pairing UI.~~ **Done.** The device list is on the You page with revocation, and board 1l's pairing screen exchanges offers and compares the short authentication string (Build Decision D41). | Epic 6 | Resolved. |
| 11a | **Resolved — superseded by row 11b.** The transfer is sealed, carried and adopted end to end; this row described the gap between the mechanism and the flow, which no longer exists (Build Decisions D51, D53, D54). | Closed | None. |
| 12 | **"Seen by N of M" on a post, and dimmed avatars for peers who have not synced.** Both need per-peer delivery state. | Epic 6 | Cosmetic until sync exists, then real. |
| 13 | **The reciprocal line on someone else's wall** ("what they can see of yours", board 4b). | Epic 5a | Expected — needs Design Decision P2's permissions. |
| 14 | **Hold-to-react with recently-used emoji** (board 4c). The picker is reachable from the reaction bar instead. | Epic 5 | Cosmetic. |
| 14a | **No camera scanning.** The invite and the joiner's code are shown as QR and accepted as pasted text; nothing reads a QR yet, so "scan in person" is currently "show and paste". | Epic 7 | Real for the in-person flow §6 step 2 describes. |
| 21 | **Search and composing-from-the-feed are drawn but not built.** Both search buttons and the Outposts compose button are now visibly disabled and declared, rather than looking live and swallowing taps. | Epic 9 | Cosmetic, and no longer misleading. |
| 22 | ~~Room members cannot see each other's names.~~ **Done.** Sharing a room hands the name over; a stranger stays an identifier, like a phone number. One name everywhere, no per-room nicknames (Build Decision D39). | Epic 6 | Resolved. |
| 11b | **Resolved — pairing hands the member over.** The sheet asks which device it is, and after the phrase matches the existing side sends a sealed bundle of the identity seeds and every epoch secret it holds, which the new side pastes to become the same member (Build Decision D54). Proven end to end over two separate keychains. | Closed | None; see row 11c for what pairing still cannot do. |
| 11c | **The handover is copy-and-paste, and large.** The sealed bundle carries every epoch secret this device holds, so it grows with history and is passed by share sheet like the offer before it. Fine for two devices in the same room; poor once a member has years of rooms. A direct channel or a QR sequence would suit it better. | Epic 9 | Cosmetic now, real at scale. |
| 24 | **Resolved — every filled accent button reads its own enabled state.** All seven hand-drawn accent backgrounds are now `primaryAction()`, including onboarding's "Create my identity", which was genuinely gated on a non-empty name and showed no sign of it. Check 8 of the lint fails any new one. | Closed | None. |
| 25 | **Resolved — an empty account is told nothing.** `caughtUpLine` returns `String?` and the footer is omitted when there is nobody to reach. The first fix used "has any rooms", which was the wrong question and put the same false line back the moment a member made a room and was alone in it; the predicate is now `SyncSummary.hasAnyoneToReach(in:)` and is tested (Build Decisions D59, D60). | Closed | None. |
| 26 | **Resolved — the composer is a sheet with room to write.** Full-height editor, a Done that dismisses the keyboard, bold/italic/underline with a live preview of how the post will read, and underline drawn in the accent rather than as a rule (Build Decision D62). Formatting renders in the Outpost, the feed and the thread. | Closed | None; see row 43 for what formatting still does not reach. |
| 27 | **Resolved — the radius is clamped to the bubble's own height.** Two 20pt corners on a 38pt single-line bubble overlapped in the middle and ate the words. The corner is now measured rather than assumed, so the board's shape survives on bubbles tall enough for it and stays correct at accessibility text sizes (Build Decision D66). | Closed | None. |
| 28 | **Resolved — and it was worse than reported.** The receipt was not merely mispositioned: it rendered in a room with no messages at all, announcing that nothing had been delivered when nothing had been said. It is now omitted when there are no message runs. The room header also said "1 members"; it now uses automatic grammar agreement (Build Decision D60). | Closed | None. |
| 29 | **Resolved — every tab root draws its own header.** `YouView` was the only screen using a standard `.navigationTitle`, so its title sat at a different height and the tab read as a different app. It now matches Rooms and Outposts. The debug persona bar also gained the spacing that was missing beneath it, kept on the bar itself so deleting the feature takes nothing else with it (Build Decision D68). | Closed | None. |
| 30 | **Resolved — a pushed Outpost can be left.** Reaching Your Outpost from You or from the feed left the tab bar as the only way out, which is navigating by undo rather than by intent. The header carries a back control when it was pushed, and nothing when it is a root (Build Decision D68). | Closed | None. |
| 31 | **Resolved — at the three moments something commits.** Sending a message, posting, and confirming a pairing phrase. Deliberately not on navigation (Build Decision D67). | Closed | None. |
| 32 | **No edit or delete on posts.** Owner's model: an edit or delete propagates to everyone permitted to see the post, and a peer that refuses to sync keeps the old copy but stops receiving anything new. See Build Decision D57 on how this may and may not be described. | Epic 5a | Real. Tombstones exist in §4.1; the fold and the UI do not. |
| 33 | **Group deletion of a member's own history.** A member can see who holds their data; deletion becomes a request with a settable window, a live accepted/refused list, and a cancel that offers to ask friends to restore. Friends may refuse, because the history is theirs too. | Epic 9 | Real, and the honest version of "delete my account". |
| 34 | **Trusted friends.** Social recovery per Design Decision P4: a chosen peer, a separate high-entropy key exchange, revocable, with both halves destroyed on sync when revoked. Surfaced by a prompt on the profile after some use. | Epic 7 | Real. It is the only answer to total device loss that does not invent a service account. |
| 35 | **Direct messages as their own place** in the tab bar alongside rooms, under a better name than DMs. | Epic 12 | A DM is a two-person room; the cost is the tab bar, not the model. |
| 36 | **Resolved — rooms choose who has to agree, and the false claim is gone.** `RoomAccess` carries six settings — open, the founder, a named member, any member, a minimum count, unanimous — written by the founder as a log entry and ignored from anybody else. A new room is open, per the owner's ruling. `HowItWorksView`'s "everyone in it checks that invitation themselves" said a configuration was the guarantee; it now states the floor that actually holds (signed, named, expiring, visible) and mentions approval as a setting. Two doc comments claiming the same thing were corrected with it (Build Decision D114). | Closed | None. |
| 37 | **Emoji in room names, and local nicknames for people.** Nicknames must stay on the device that sets them. | Epic 12 | Small; the nickname must never be published. |
| 38 | **Near-real-time notification is unproven.** Design Decision P3's Notification Service Extension is the only route that fits D1, and it has never been built or measured. | Epic 4 | The largest open technical risk in the project. |
| 39 | **Age rating and App Store Connect policy** unfilled. | Before submission | Expected. |
| 40 | **Resolved — the empty rooms list says what it is.** A heading, one sentence stating why nothing arrives unprompted, and both actions that were previously buried in the overflow menu (Build Decision D61). | Closed | None. |
| 41 | **Resolved — the new-room field was an alert's, and is now a sheet's.** The owner could not type into the new-room modal on a real device. It was `.alert` with a `TextField`, the least reliable focus target SwiftUI offers, and injected taps hid it completely because a simulator delivers keystrokes to whatever holds focus whether or not a keyboard ever appeared. It is a sheet with `@FocusState` (Build Decision D65). The conversation composer's behaviour under automation was the same artefact and is not a defect. | Closed | None. |
| 42 | **Not a defect — the personas were in the same room.** Each holds its own directory, log and Keychain service, confirmed on disk: four distinct logs of different sizes. Two personas showing one room with the same last message is two members of that room seeing it, which is the debug transport working (Build Decision D69). | Closed | None. |
| 43 | **Resolved — formatting no longer leaks as markers.** A comment read in full is formatted like any other body; the inline comment preview is flattened with `PostFormatting.plainText`, because a two-line preview is the wrong place for emphasis and raw markers are worse than none. Rooms-list previews show messages, which carry no formatting (Build Decision D63). | Closed | None. |
| 44 | **Resolved — emphasis applies to the selection.** The toggle rule lives in `PostFormatting.toggling(_:in:over:)` where it is tested, including the case that decides whether a partly-emphasised selection gains or loses the emphasis. The buttons disable themselves when nothing is selected (Build Decision D64). | Closed | See row 45. |
| 45 | **Resolved — the selection is put back by offset.** The rebuild replaces every index, so the range is restored from character offsets, which are stable because only the attributes moved (Build Decision D67). | Closed | None. |
| 46 | **Reduced — the Mac is a window now.** `defaultSize`, `windowResizability(.contentMinSize)` and a minimum content size, so the window opens sensibly and drags from every corner. Filled buttons cap at a readable width instead of stretching (Build Decision D72). | Epic 12 | Reduced — the chrome is right; the layouts still do not reflow into two columns (§9.2 row 15). |
| 47 | **Resolved — a field looks like a field.** `fieldChrome()` draws an outline over the page rather than a filled slab the same shape as the button beneath it (Build Decision D72). | Closed | None. |
| 48 | **Resolved — a disabled button uses a neutral fill.** Fading the accent to 30% left a muddy slab in a Mac window; neutral fill with quaternary text reads as "not yet" on both platforms (Build Decision D72). | Closed | None. |
| 49 | **"How this works" is rough.** Owner's judgement on the onboarding secondary action. | Next | Needs a design pass, not a patch. |
| 50 | **Resolved — every code field has a Paste button.** Each code arrives via the clipboard, so the app offers it directly. The pairing field had it (Build Decision D72); the redeem-invite and issue-invite fields now use the same `PasteCodeButton` too, so the whole clipboard flow is one tap rather than a long-press-and-choose. | Closed | None. |
| 51 | **Resolved — an identity without a device key asks to be enrolled.** `load()` used to require both, so a Mac holding a synced identity fell through to onboarding. It now recognises the case and shows the joining side of pairing (Build Decision D71). | Closed | None. |
| 52 | **Resolved at the cause, and guarded twice.** Inviting your own key is refused when the invite is issued, and again when one is redeemed. The share acceptance that produced `CKError 12/2006` is no longer reachable, because the flow that led to it was the wrong flow (Build Decision D71). | Closed | See row 55 for surfacing errors. |
| 53 | **Reduced — the QR says what it is for.** Scanning is still unbuilt (§9.2 row 14a), but the screen no longer presents a code nothing can read as though it were a working path (Build Decision D72). | Epic 6 | Reduced — honest, still not functional. |
| 54 | **The macOS icon draws black edges around a white mark — an artwork fix, not a config one.** Diagnosed: the asset catalog is wired correctly — `AppIcon.appiconset` carries the full `mac-16…512` at 1x/2x — so the fault is in the images themselves. macOS does not mask app icons the way iOS does; it expects each `mac-*.png` to already be a rounded-rect with a transparent margin (roughly the `824/1024` "squircle with padding" Apple ships). The current mac images are full-bleed squares, so macOS shows the square's corners as black around the mark. The fix is to regenerate the `mac-*.png` files with that shape baked in — image work, not a code or `Contents.json` change, so it is left for the icon pipeline / a design pass. | Before any Mac build | Real; needs the icon artwork regenerated, which is not a code change. |
| 55 | **Resolved — CloudKit errors reach the member the platform's way.** The two member-facing sites — a failed invite redeem and the "something is wrong with this device's data" screen — used `String(describing: error)`, which prints the raw `CKError 0x…: "Invalid Arguments" (12/2006)` type dump. Both use `error.localizedDescription` now; the raw value still goes to the log. | Closed | None. |
| 56 | **Resolved — creating an identity no longer adopts a synced one.** iCloud Keychain delivers the identity asynchronously, so a second device could show onboarding and have the identity arrive mid-typing; `enrol()` then reused it and applied the new name. Same key, different name, no certificate, nothing syncing — which is exactly what "same key, none of my content" was (Build Decision D74). | Closed | None. |
| 57 | **Resolved — the app looks again for a late identity.** iCloud Keychain gives no notification when it delivers, so `load()`'s answer was final and often taken a second too early. `recheckForSyncedIdentity()` re-runs on a short ladder after launch and whenever the app becomes active, and only ever moves away from onboarding (Build Decision D75). | Closed | None. |
| 58 | **Second-device setup should be a bottom sheet that animates up**, not a full-screen replacement. | Next | Design. |
| 59 | **Policy: one identity per iCloud account.** Recorded as the owner's current position, to be revisited as an open question rather than assumed permanent. | Owner's decision | Settled for now. |
| 60 | **Fixed, pending a look — the message field's border no longer sits on an arc.** The border was a `Capsule`, whose curved top and bottom put the hairline on a sub-pixel arc where anti-aliasing dropped it a frame at a time as the field redrew — the flicker that "lost an edge". It is a `RoundedRectangle` (radius 17, continuous) now: straight top and bottom edges render the hairline crisply. Diagnosed from the symptom rather than observed, so it wants the owner's eyes on desktop to confirm. | Owner to confirm | Should be gone; a visual check closes it. |
| 61 | **Resolved — Return sends.** Both the button and the key go through one `send()`, which also trims and refuses an empty message; the button disables when there is nothing to send. Shift-Return still makes a new line (Build Decision D99). | Closed | None. |
| 62 | **Resolved — a new message eases into place.** The transcript animates on message count with `.snappy`, keyed so the initial load does not animate and dropped entirely under Reduce Motion. | Closed | None. |
| 63 | **The new-post sheet collapses on macOS**, folding onto the text input. The composer was only ever laid out for a phone. | Next | Real; the composer is unusable on desktop. |
| 64 | **Resolved — a waiting device announces itself, and the codes still work.** The device asking to be added publishes a `PairingRequest` to the member's own CloudKit private database and the existing device offers to deal with it on its next sync. The manual code exchange is unchanged and unconditional: the announcement is `try?`, so a CloudKit failure costs the prompt and nothing else (Build Decisions D78, D79). | Closed | None — pairing no longer depends on CloudKit. |
| 65 | **You cannot block somebody already in a room.** Refusing exists and works — `RoomRoster.rewrapTargets` drops anyone a member has refused, so the refused party stops receiving that member's keys and cannot read what they write from then on. It is unilateral, needs nobody else's agreement, and cuts rather than hides. But it can only be issued while admitting somebody. There is no way to turn it on a person who is already in. This is the "who gains it stays in your control" half of the bargain, and it currently only works at the door. | Epic 6 | Real. App Store guideline 1.2 requires a block, and the marketing site's Terms and Support pages already describe one. |
| 113 | **No way to report a message to us.** Guideline 1.2 requires a reporting route, and there is nothing to report *to* — no server, no moderation queue. The pattern that fits: Report on a message opens a composer on the reporter's own device, shows them exactly what will be attached, and sends it to the published address. The reporter is the one who discloses, so no back door is introduced. | Epic 6 | Real. Required for submission, and the Terms and Support pages already describe it. |
| 114 | **A room's key only changes when its membership does.** Epochs advance on join, removal and device revocation, and at no other time. So if a key ever leaks, everything written from the leak until the next membership change is readable, and in a settled friend group that can be months. Other messengers change the key every message, which shrinks that window to one message and also heals: an attacker who stole keys is eventually locked out again on their own. Outpost does not heal — revoking the device fixes it, but only if somebody notices. Worth deciding whether to advance epochs on a schedule as well, or to accept it and say so. | Epic 12 | Real but not urgent. It is a property to choose deliberately rather than a bug. |
| 115 | **A stolen phone gives up the whole room, not just recent messages.** `EpochLink` lets whoever holds the current key recover the one before it, and so on back to the room's first message. That is the same mechanism that lets a new member read the history, so it cannot be removed without giving up D2. The consequence is that one seized or compromised device exposes everything that room ever said, where a per-message design would expose a bounded window. Not a defect — but it is the sharpest edge in the design and nothing currently says so anywhere a member would see it. Decide whether it is disclosed in the app, and where. | Epic 12 | Real as a disclosure question; the mechanism itself is settled. |
| 116 | **Nobody outside the project has reviewed how the crypto fits together.** The pieces are all standard and come from CryptoKit rather than from us, which is the right call and removes the usual class of implementation bugs. What is unreviewed is the assembly: epochs, links, grants, pairwise addressing and the rules about who rewraps to whom. That is where a design like this normally goes wrong. Publishing the source with TestFlight is most of the answer; a paid review of the key-handling paths would be the rest. | Before public launch | Real. The product's whole claim rests on this being right. |
| 66 | **Resolved — the pairing key stopped moving mid-flow.** `beginPairing` minted a fresh ephemeral key on every call, and the `.needsDevice` screen called it twice (its own `.task`, then `publishPairingRequest`). The phrase still matched, because it is derived when shown; the sealed transfer then failed with `authenticationFailure`. It is now idempotent (Build Decision D80). | Closed | None. |
| 67 | **Two causes found, both silent.** The read ran inside the mailbox's `do` block, so any mailbox failure skipped it; and it used a `CKQuery`, which needs an index nobody had created, failing with `invalidArguments` — which was caught and returned as "nothing waiting". Now a fetch by known record ID, read independently of the mailbox, with failures surfaced (Build Decision D81). | Needs a device to confirm | Reduced — the two known causes are gone; unproven until it prompts. |
| 68 | **Folded into row 71.** The same item was written down twice; row 71 is the fuller statement and the one to work from. | — | Duplicate. |
| 69 | **No CloudKit integration test.** CloudKit has no offline simulator; a real test needs a signed-in iCloud account, entitlements and network. Feasible against a simulator signed into a test account, and slow and flaky by nature — but currently the transport has no automated coverage at all. | Epic 4 | Real, and the reason CloudKit defects only appear by hand. |
| 70 | **Reduced — an unused device now says so.** The ordering is unchanged: a certificate is still committed when the phrase matches, because the transfer is useless without it. What has changed is that a device which has never signed anything is drawn as "Added, but it has never been used" instead of identically to a working one, so a failed pairing is visible and removable (Build Decision D84). | Next | Reduced — visible now; the ordering itself is still worth revisiting. |
| 71 | **Resolved — the judgement moved to where tests live.** `AppRootView` is a SwiftUI `View` in the app target, which has no test target, so every decision written inside it was unreachable by the suite — which is why nearly every defect found by hand lived there. `RootScreen`, `DeviceSyncDecision` and `SyncRound` are those decisions as values and pure functions in `CarpenterApp`, and the view now switches on them rather than re-deciding. Reintroducing row 51's defect fails three tests; reintroducing row 67's fails four (Build Decision D115). | Closed | The view's *layout* is still untested; its judgement is not. |
| 72 | **Resolved — a waiting device offers as one from the first draw.** `pairingOffer` is read while the view first renders, before any `.task`, and `currentPairing()` defaulted to the *existing* device — so the device published an offer with an empty subkey and one ephemeral key, then swapped to a joining session underneath it. Whatever had already been sent to the other device was the wrong offer, and the transfer failed with `authenticationFailure`. The role is now set when `load()` decides `.needsDevice` (Build Decision D84). | Closed | None. |
| 73 | **The app said nothing about itself.** Every pairing defect was diagnosed by inference from a symptom, because nothing was written down. `Diagnostics` logs the pairing, sync and identity paths through OSLog — unconditionally, since the failures happen in builds installed from Xcode — with keys reduced to eight-character fingerprints. `Scripts/logs.sh` reads them from this Mac or a connected iPhone (Build Decision D85). | Closed | None. |
| 74 | **Personas removed.** A debug transport that was not the shipping transport, built to avoid needing two Apple Accounts, which the owner never used because they tested on real devices. Every defect it might have caught was found on hardware instead (Build Decision D85). | Closed | None. |
| 75 | **Resolved — the certificate no longer ends the pairing.** `pair(with:)` set `pairing = nil` immediately after issuing the certificate, so the sealed transfer that follows built a *new* session with a new ephemeral key and sealed to a key the other device had never seen. The phrase matched because it was computed while the original session still existed. Certifying is the middle of a pairing; `endPairing()` is the end, and the sheet calls it on dismissal (Build Decision D86). | Closed | None. |
| 76 | **Resolved — a lone device is no longer told one is waiting.** The filter excluded only "mine" and "older than an hour", and a wipe mints a new device key — so a request this same hardware published in an earlier life stopped looking like its own and prompted about a device that no longer existed. Requests are now shown only if they are live, not already certified, and actually admissible; the lifetime is fifteen minutes; and wiping clears the rendezvous (Build Decision D87). | Closed | None. |
| 77 | **Resolved — an adopted device is set up, not half-onboarded.** `adopt` wipes the log, so `load()` found no profile entry and returned `.needsProfile` — the name prompt. The member exists and this device holds their keys; only the history is missing. Answering that prompt wrote a *second* profile for the same member (Build Decision D88). | Closed | None. |
| 78 | **The incoming device crashed just after adopting.** Reported as a flicker of the welcome screen then a crash. §9.2 row 77 explains the flicker; the crash is unexplained and has no trace yet. Needs `Scripts/logs.sh device` running across the moment it happens. | Next | Unknown until reproduced with the console attached. |
| 79 | **No content reaches an adopted device.** The transfer carries identity and epoch secrets, never entries — history is meant to arrive by sync, and sync is not delivering (§9.2 rows 7, 8, 67). Until then an adopted device is correctly set up and permanently empty. | Epic 4 | Real, and it makes device sync look broken even when pairing works. |
| 80 | **Resolved — "Check CloudKit" now tests what matters.** It wrote and read on the same device, which proves the container works and says nothing about data crossing between devices. It now leaves a beacon and reports beacons left by the member's other devices, so "no other device has left one" is stated plainly rather than read as success (Build Decision D89). | Closed | None. |
| 81 | **Express pairing on one account.** The original admits a waiting device from the prompt and leaves its sealed keys in the private database; the incoming device collects them while it waits. No codes to copy. Same account only — across accounts there is no such channel and the phrase remains the whole security (Build Decision D89). | Needs a device to confirm | The codes still work and are untouched. |
| 82 | **Resolved — the original now looks again.** CloudKit was crossing devices all along; the rendezvous was only ever read inside `sync()`, which ran when the rooms list first appeared. A device that started waiting after that was never noticed, and returning to the app rechecked the identity without syncing. Becoming active now syncs, and the rooms screen asks once every fifteen seconds while it is on show (Build Decision D90). | Closed | None. |
| 83 | **Resolved — a delivered transfer carries the sender's offer.** `collectPairing` handed `adopt` the collecting device's *own* offer, so it computed a key agreement with itself: `authenticationFailure`, swallowed by the poll's `try?`, which is why the original showed an added device and the incoming one did nothing. The delivery now carries the sender's offer alongside the sealed bundle (Build Decision D91). | Closed | None. |
| 84 | **Resolved — a failed background sync no longer alerts anybody.** A first launch, with no identity and nothing to sync, greeted a new member with a raw CloudKit error. §3.2.1 requires a failed sync to look like nothing happened; failures go to the log, and the alert is reserved for what the member asked for by pressing Check CloudKit (Build Decision D91). | Closed | None. |
| 85 | **Resolved — a member can say they have another device.** Reaching the second-device flow depended entirely on iCloud Keychain having delivered the identity before launch: asynchronous, unnotified, absent on a simulator, and slow enough on real hardware that the welcome screen wins. Onboarding now offers "I already use Outpost on another device", which reaches `.needsDevice` without waiting for anything (Build Decision D92). | Closed | None. |
| 86 | **Resolved — one unreadable field no longer breaks the rendezvous.** Every field shares one record, and a value written by an older build failed the whole read. Publishing reads before it writes, so a single stale field stopped requests being published *and* seen, in both directions. Fields decode independently now, and one that cannot be understood is discarded rather than fatal (Build Decision D92). | Closed | None. |
| 87 | **Resolved — a waiting device's offer survives a relaunch.** The ephemeral seed was regenerated on every start, so keys delivered while the app was closed could never be opened. It is kept in the device Keychain until the pairing completes (Build Decision D92). | Closed | None. |
| 88 | **Resolved — a member's devices share their history.** Sibling devices exchange their own feeds through the private database, carrying the certificates a freshly paired device needs to believe them. Verified across two simulators: the incoming device took 3 entries and drew the room. | Closed | See row 91 — the feed is published whole. |
| 89 | **A transfer that cannot be opened is retried forever.** A stale delivery from an abandoned attempt failed `authenticationFailure` every two seconds until a fresh one replaced it. It should be discarded once it cannot be opened by the offer this device currently holds. | Next | Small, and it fills the log with alarming errors that are not the real fault. |
| 90 | **Resolved — arriving history clears the name prompt.** `load()` decided `.needsProfile` against an empty log and nothing re-asked, so a device sat on the name prompt holding the history it had just been given — and answering wrote a second profile (Build Decision D94). | Closed | None. |
| 91 | **Reduced — one record per device, and no write when nothing changed.** Feeds moved from one shared record to `feed-<deviceID>`, fetched by known id, so devices no longer clobber each other and the size limit is per device rather than per member. A device also skips the write when its own entry count is unchanged (Build Decision D95). | Epic 9 | Reduced — see row 93, the skip is too eager. |
| 92 | **Resolved — `.needsProfile` offers the second-device path too.** Uninstalling an app does not remove its Keychain items, so a reinstalled device holds its identity and lands on the name prompt rather than the welcome screen — the one onboarding state that did not offer "I already use Outpost on another device" (Build Decision D95). | Closed | None. |
| 93 | **Resolved — writing publishes.** Appending an entry now publishes this device's feed, detached from the write so a message never waits on a network round trip, and retried by the next write or sync if it fails. Verified on a simulator: creating a room logged `published 3 entries for siblings` immediately, where before nothing was published until the next sync (Build Decision D96). | Closed | None. |
| 94 | **Resolved — a device that cannot admit anybody is not prompted.** The welcome screen showed "a device of yours is waiting" to a device with no identity: an action it cannot take, in an alert sitting over the name field it needs. `pendingPairingRequests` now returns nothing before there is an identity (Build Decision D97). | Closed | None. |
| 95 | **Resolved — replacing the session re-wires it.** "Start over" builds a new `AppSession`, and `.task` had already run, so the replacement never received a sibling channel and nothing it wrote was published for the rest of the session. Confirmed by driving it: a room created after a wipe logged no publish at all (Build Decision D98). | Closed | None. |
| 96 | **Resolved — wiping a device forgets its published feed.** Build Decision D95 moved feeds into per-device records and `clear()` kept deleting only the shared rendezvous record, so a wiped device left its whole history in the account and the next device paired to it collected that instead of the current one. Observed directly: the incoming device drew a room from before the wipe (Build Decision D98). | Closed | None. |
| 97 | **Not a defect — the field was fine; the sending was mine.** The owner typed into it without trouble. What failed was pressing Return, which did not send (§9.2 row 61) — so text was entered and never went anywhere, and the automation read that as a field that would not accept input. | Closed | None. |
| 99 | **Resolved — a sibling gets the epochs for rooms made after it was paired.** A new room mints a new epoch chain, so the second device received its entries and could not open them: the room simply did not appear. The feed now carries every epoch secret the sending device holds, and an arriving secret is adopted into the live chain as well as written to disk — without which the entries in that same batch stay unreadable until a relaunch (Build Decision D101). | Closed | None. |
| 100 | **Resolved — device sync runs on `CKSyncEngine`.** The adapter is written, wired and observed starting and staging on a real device: `device sync engine started`, then `staged 7 entries`. The hand-rolled channel, its per-device records, its watermark and its polling are deleted (Build Decisions D102, D103). | Closed | Two-device exchange still unobserved — see row 102. |
| 101 | **Resolved — the engine starts when an identity appears, and publishes what already exists.** It needs a device identifier, so on a fresh account it was being started while there was none and silently did nothing; and the entries written while it came up were never staged, so a first device published nothing at all. The state change now starts it, idempotently, and starting it sends this device's existing history (Build Decision D103). | Closed | None. |
| 102 | **Half done — the first write crosses, later ones do not.** The owner was right that a single room proved too little. Sending is now correct for every write (`staged 5 entries` → `sent 1 record(s), 0 failed`, no failures); the receiving device does not pick up anything after its first fetch. Rows 105 and 106 fixed two causes; a third remains. | Next | **E1 is not done.** Messages and posts written after pairing do not reach the other device. |
| 103 | **Resolved — the sync zone is created before records are staged into it.** `CKSyncEngine` needs the zone added as a pending *database* change; without it a record save fails at the server, and a sibling that wrote nothing looks identical to one whose writes were rejected. Save failures are now logged rather than silent (Build Decision D104). | Closed | None. |
| 104 | **Resolved — the sync engine's delegate is retained.** `CKSyncEngine.Configuration` does not keep its delegate alive, so one created inline was deallocated as soon as `start()` returned. The engine then had nobody to ask for a batch: records staged forever, nothing sent, and no failure — silence rather than an error (Build Decision D105). | Closed | None. |
| 105 | **Resolved — a saved record keeps its change tag.** Every save built a fresh `CKRecord`, which has no tag, so CloudKit refused the second write and all after it: `"record to insert already exists" (14/2004)`. The first write landed and nothing ever updated — exactly "the room synced, the message did not". The server's copy is now kept and saved from, and a conflict adopts the server record and retries (Build Decision D106). | Closed | None. |
| 106 | **Resolved — opening the app fetches.** The engine fetches when CloudKit pushes, and a push never arrives on a simulator and is not guaranteed on a device. the foreground-only sync model already says this app syncs when you open it, so starting and foregrounding now ask (Build Decision D106). | Closed | None. |
| 107 | **Resolved — the app drives sync; the engine no longer waits to be told.** With `automaticallySync` on, `CKSyncEngine` only fetches zones a push has flagged, so a device that missed one asked the server nothing and returned in three milliseconds looking exactly like an account with nothing in it — the same symptom as a broken account, a missing zone and an unsent record, which is why this took so long to pin down. `automaticallySync` is now off and opening the app fetches for real: `database says 1 zone(s) changed` → `record(s) arrived` → `took 9 entries from another device`. Verified on two simulators, both directions, messages **and** posts (Build Decision D111). | Closed | None. |
| 111 | **Resolved — the empty Outpost audience says nothing.** "Visible to no one yet." greeted every member who had not added anybody, stating the obvious and reading as a reproach on a first-run screen. Row 25 had already settled this for the sync line; the same reasoning applies here. `AudienceSummary.line` returns `nil` for an audience of nobody and the line is left off. Owner's ruling. | Closed | None. |
| 110 | **Resolved — a launch's first save is no longer refused, and a send is asked for.** The server's change tag was cached in memory only, so every launch built a tagless record and every launch's first save came back `serverRecordChanged`; the retry re-staged inside the engine's own event handler, where it does not stick, and the batch provider was never asked again. Nine entries sat unsent with nothing logged. The tag is now seeded from the server at start, the retry is staged after the handler returns, and `send` asks the engine to send rather than leaving it to the scheduler (Build Decision D110). | Closed | None. |
| 109 | **Resolved — applying is awaited before the engine records progress.** Fetched records were yielded to an `AsyncStream` and the handler returned immediately, so `CKSyncEngine` persisted "these are delivered" while the app had not yet written them. A relaunch would then fetch nothing while the app was missing everything. `EntrySync` now takes a handler the engine awaits (Build Decision D108). | Closed | None. |
| 108 | **Resolved — the CloudKit check no longer lies.** Beacons were keyed on `UIDevice.current.model`, which is "iPhone" on every iPhone, and leaving one replaced any beacon of the same name — so two simulators each overwrote the other's and each saw only its own. A healthy account reported "no other device has left one", and an hour went into the wrong half of the system on the strength of it. Beacons are keyed on `DeviceID` now (Build Decision D107). | Closed | None. |
| 23 | **macOS cannot have a dark app icon this way.** An app icon set accepts `luminosity` entries for the mac idiom, reports them as "unassigned children", and emits nothing — zero renditions with an appearance reached `Assets.car` when they were declared. Light and dark macOS icons come from an Icon Composer `.icon` file on macOS 26, not from an asset catalogue. macOS currently ships the plain light mark at every size. | Epic 8 | Real but small — the icon is correct, just not appearance-aware. |
| 15 | **Desktop layout** (board 4f): collapsible sidebar sections, feed in the middle, thread in the right rail. | Epic 8 | Expected — desktop is where the direct-sync work already goes. |
| 16 | **Causal ordering is untuned.** O(entries × feeds) per sort, re-sorted on every read. | Epic 9 | Fine for a friend group's first year; needs an incremental index before a room has years of history. |
| 17 | **No media anywhere.** No image payloads, photo avatars, thumbnails or retention. | Epic 9 | Expected. |
| 18 | **Resolved — the wordmark is no longer type.** The brand is now the owner's drawn mark, shipped as artwork, so there is no font to substitute and nothing to bundle. The type-set `Wordmark` component was deleted rather than left unused (Build Decision D47). | Closed | None. |
| 19 | **Accessibility pass.** Dynamic Type works (Build Decision D42), the palette is measured against WCAG AA with the text greys raised to pass (Build Decision D43), and Reduce Motion is audited: the app asks for no motion of its own, and the single animation it does run is a colour cross-fade, which is what that setting asks motion to become. A lint keeps that true (Build Decision D48). VoiceOver rotor navigation is done: section labels are announced as headings so the Headings rotor has something to jump between, and the rooms list carries an Unread rotor (Build Decision D50). | Closed | None. |
| 19a | **Resolved — the foreground is chosen per accent.** White on the accent failed AA on ten of the fourteen accent-and-appearance pairs, every one in dark mode. The owner's colours are untouched; the text on them is now whichever of black and white each accent contrasts with best, which clears 4.5 on all fourteen (Build Decision D49). Both the threshold and the per-accent choice are pinned by tests. | Closed | None. |
| 20 | **Wireframes unbuilt.** Chiefly the consequential screens (2a–2m), Outpost permissions (1k, 1x, 1y), invite and join (1g, 1h), notification ladder (1j), backfill waiting (1i). | Epic 5a, Epic 6, Epic 12, Epic 13 | Expected. |

### Screens the design does not yet have

Named so they are not discovered late. The first four are the wireframes' own note; the rest come
from reading the epics against the boards.

1. Search results, and the empty state behind it.
2. New-room creation.
3. The joiner's own view of joining — every drawn join screen is from the perspective of a member
   who is already in the room.
4. The two per-room settings screens the tag work touches.
5. **The mandatory member picker (Design Decision P2, Epic 5a).** Shown before every group grant applies, with
   search, pagination, per-row three-way control, bulk actions and a running count of who gains
   access. It is required on every join and it is not drawn.
6. **The divergence view** (item 2 above).
7. Empty states for the rooms list: no rooms at all, and no rooms matching the active tag.
8. The minimum-supported-version gate (§7) — what a client that is too old to read the room shows.
9. Purchase (Epic 11).

---

## 10. Risks worth naming

**Availability is the product's weak point, not its crypto.** If your friends open the app
rarely, messages arrive rarely. A friend group where one person has a Mac that's open all
day will feel great; one where everyone checks weekly will feel broken. This is inherent
to D1 and cannot be engineered away — only designed around, by making the app pleasant to
open.

**Apple-only.** CloudKit and synchronizable Keychain foreclose Android. For a friend group
this is likelier to be disqualifying than for a workplace. Confirm the target group is
all-Apple before building.

**Distributed systems bugs are the expensive kind.** Causal merge, epoch transitions, and
backfill reassignment are where correctness failures hide, and they surface as "my friend
says they sent it and I never got it" — unreproducible and trust-destroying. Epic 2 and Epic 3
are pure and fully testable on purpose. Do not skip the property tests to get to UI faster.
