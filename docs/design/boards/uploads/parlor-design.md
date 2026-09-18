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

## 2. Decisions already made by the owner

These are settled. Do not relitigate them in implementation.

| # | Decision |
|---|---|
| D1 | Sync is foreground-only, on app open, over any available connection. |
| D2 | New members receive **full room history** (backfill = true). |
| D3 | Backfill is served by the most up-to-date and fastest available peer, chosen by racing candidates. |
| D4 | Joining triggers a security check; on the next sync, all members rewrap keys to include the new member. |
| D5 | "Extensions" are first-party features the owner writes, toggleable per room. Not a third-party plugin system. |

D5 removes the App Store interpreted-code question entirely. No further analysis needed.

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

**Device pairing flow (build this):**

1. New device generates its own signing subkey.
2. Existing device displays a short authentication string; the user enters it on the new
   device. The pairing channel is authenticated by that string — SAS-style, the same
   pattern Signal and Matrix use for device linking.
3. Existing device signs a device certificate for the new subkey and transfers the
   identity keys and current epoch secrets.
4. The certificate is published in-band. Other members verify it before accepting entries
   from the new device.
5. The new device then syncs both with its own other devices and with the group, exactly
   as the owner described.

**Note this may be largely free.** Identity keys live in synchronizable Keychain, so a
second device on the same Apple Account already has them. The pairing flow is therefore
required only for devices on a different Apple Account, and otherwise serves as an
explicit, verifiable audit trail of which devices can speak as you — which is worth having
regardless. Confirm the Keychain behaviour before deciding whether pairing is mandatory or
a fallback (OQ-6).

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
instrument it from the first build. See OQ-2.

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

**E0 — Skeleton.** Multiplatform project, branding placeholder, CI lint, Swift 6 strict
concurrency, fakes for CloudKit/network/clock. *Exit:* codename absent from source; tests
run in CI.

**E1 — Identity and device certificates.** Ed25519 + X25519, synchronizable Keychain,
per-device subkeys certified by identity. *Exit:* a second device joins the same identity
and both feeds verify.

**E2 — Feed engine.** Append, hash-link, sign, verify, causal merge, fold of
edits/tombstones/reactions. Pure, fully unit-tested, no network. *Exit:* property tests
over random concurrent interleavings converge to identical state on all replicas.

**E3 — Crypto and epochs.** Pairwise secrets, epoch keys, historical chain wrapping.
*Exit:* joiner with the epoch chain decrypts all history; removed member decrypts nothing
after their removal epoch.

**E4 — Mailbox sync.** Packet batching, rotating tags, fetch/ack/delete, write budget with
instrumentation, `CKSubscription` contentless push. *Exit:* two devices converge over
CloudKit; budget ceiling enforced and measurable.

**E5 — Rooms and Wall UI.** The minimum usable product. *Exit:* three people hold a
conversation for a week without data loss.

**E5a — Wall permissions.** ADR-P2 in full: segmented chains, group grants, global
per-member overrides, the mandatory picker, locked grant points, the upgrade warning, and
the leave-group dissolution flow. *Exit:* a property test asserts that for every sequence
of joins, grants, overrides, and departures, each viewer's derivable segment set exactly
matches their intended entitlement — and never exceeds it. Denied viewers must be
unable to derive any segment root, verified cryptographically rather than by UI state.

**E6 — Invite and join.** Out-of-band invite, independent verification, rewrap on sync.
*Exit:* a fourth member joins and every existing member verified independently.

**E7 — Backfill.** §5 in full: race, assign, chunk, resume, reassign. *Exit:* joiner
receives complete history with the serving peer backgrounded twice mid-transfer.

**E8 — Direct sync.** Local network discovery and transfer, with mailbox fallback.
*Exit:* two devices on the same Wi-Fi sync without touching CloudKit.

**E9 — Media.** Lazy fetch, local thumbnails, per-room retention. *Exit:* a room with
500 images does not blow up storage on a 128GB phone.

**E10 — Extensions.** Registry, fallback strings, per-room toggles, forward-compat tests
against a synthetic "future" client. *Exit:* a client that predates an extension renders
its fallback and re-renders correctly after update.

**E11 — Purchase.** StoreKit 2, one non-consumable, `Transaction.currentEntitlements`, no
receipt server.

**E12 — Notifications and previews.** NSE per ADR-P3, preview ladder, warning sheets,
opaque thread identifiers, App Group settings store. *Exit:* previews off by default; the
NSE syncs correctly at every ladder level; no room or member name reaches a notification
body at level 0.

**E13 — Recovery.** ADR-P4: self-signed device revocation and Wall wipe, in-app biometric
lock, threshold social recovery with the 7-day delay and cancel-from-any-device path.
*Exit:* a wipe cannot be authorised by fewer than the threshold; a user holding their
identity is never routed to the social path; every pending recovery is cancellable.

**Build order:** E0, E1, E2, E3 (no UI). Then E4, E12, E5 — usable by three people. Then
E6, E7. Then E5a, E13. Then E8, E9, E10, E11.

---

## 8.1 Handoff to Claude Code

### Start here

Build E0 first and completely. Do not begin E1 until the codename lint passes in CI and
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

E1 through E3 have no UI at all. That is deliberate. The feed engine, the epoch chains,
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
in a debug view from E2 onward, and never suppress a verification failure.

**Over-promising in copy.** Three places where the implementation guarantees less than
plain language implies: revocation residue (ADR-P2), Wall wipe (ADR-P4), and screenshot
blocking. UI strings in those flows are part of the security design. Route any new copy in
them through the owner rather than writing something reasonable-sounding.

### Definition of done, per epic

Code, tests, the exit criterion in §8 demonstrably met, and any new decision recorded as
an ADR. An epic with passing tests and no ADR for a decision it made is not done.


---

## 9. Open questions

| ID | Question | Blocks | Resolution path |
|---|---|---|---|
| OQ-1 | **Resolved — see ADR-P1.** Do not use the public database as the mailbox. Each member owns a shared zone acting as their own outbox; storage bills to that member's iCloud quota and costs the developer nothing. | E4 | Implement per ADR-P1; verify quota attribution on a real account. |
| OQ-2 | **Resolved by owner.** Volume is expected to be small: aggressively optimised payloads, mostly text with some images, **groups capped at 25 members for v1**. Still instrument the write budget from the first build — the cap makes overrun unlikely, not impossible, and the measurement costs nothing. | E4 | Instrument and confirm in TestFlight. |
| OQ-3 | **Resolved — see ADR-P3.** Do not use silent push. Use `CKDatabaseSubscription` with `shouldSendMutableContent` and a generic alert body, and do the fetch and decrypt in a Notification Service Extension, which runs for every visible push. | E4 | Implement per ADR-P3. Prototype the 30-second budget against a realistic packet. |
| OQ-4 | **Resolved by owner: backfill includes text and media.** Consequence: a joiner's first sync may be very large. Transfer text first so the room is usable immediately, then media in the background of the same session, resumable. | E7, E9 | Implement staged backfill; cap per-room media retention. |
| OQ-5 | **Resolved by owner: the Wall inherits from shared rooms**, with global per-member overrides. Old-Twitter shape: thoughts, links, images, songs, comments, emoji reactions. | E5, E5a | See ADR-P2 for the full permission model. |
| OQ-6 | **Resolved by owner.** Pairing requires the first device online to serve the second-factor exchange and the initial backfill. After setup the new device is a peer like any other and syncs with anyone. Keychain sync may make this redundant on a shared Apple Account — treat pairing as mandatory anyway, for the verifiable device audit trail. | E1, E7 | Build the pairing flow unconditionally. |
| OQ-7 | **Resolved by owner.** Device loss is survivable: identity lives in iCloud Keychain, other members hold the content, group state is replicated. Keychain reset is not survivable, and that is accepted. | E1 | See note below. |

**Note on OQ-7.** One correction to the recovery picture: after a Keychain reset the user
cannot sign as their old identity, so they return as a **new participant**. Their previous
Wall entries remain readable by whoever already had access — those entries do not vanish —
but the old feed is permanently closed and cannot be appended to. Recovery is: new
identity, re-invited to each group, re-granted Wall access by each member. Handle
`CKError.zoneNotFound` as the trigger and present this clearly rather than as an error
state. It is rare, unrecoverable, and the user deserves a plain explanation of what
survived and what did not.

---

## 9.1 Architecture Decision Records

### ADR-P1: Per-member shared-zone outbox, not a shared public database

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

### ADR-P2: Wall visibility is group-granted with global per-member overrides

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
participant from your outbox shared zone (ADR-P1). They can no longer fetch ciphertext
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

### ADR-P3: Sync runs in the Notification Service Extension, not on silent push

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

### ADR-P4: No service account. Device loss is self-authorised; identity loss is social.

**Context:** the owner proposed a hyper-secure service account able to wipe a lost user's
Wall, gated on genuine identification.

**Decision: do not build it.** The capability is unnecessary for the common case and
unacceptable for the rare one.

#### Why it is unnecessary

Losing every device does not lose your identity. Signing keys live in synchronizable
Keychain, so a replacement device restores them from the Apple Account. You still hold
your own key, which means **you can sign the wipe instruction yourself.** It is ordinary
revocation from ADR-P2, self-authorised, no external authority involved.

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
never imply the content becomes unrecoverable. Same honest-actor class as ADR-P2's
revocation residue, and the UI copy must be consistent with it.

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
says they sent it and I never got it" — unreproducible and trust-destroying. E2 and E3
are pure and fully testable on purpose. Do not skip the property tests to get to UI faster.
