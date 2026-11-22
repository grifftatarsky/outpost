<!-- COPY BEGIN 9c6274b6 [NEEDS HUMAN REVIEW] -->

# Formats after the first tester build, and how a member learns to update

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../part-b-plan.md).

## For Griff, on one page

**The strategy.** Three kinds of data, three rules. In Spring Boot terms: saved messages are an
event store, never rewritten, and every one ever stored stays readable. What devices hand each other
(packets, keys, what your devices write for each other) is a DTO mapped at the controller, with a
reader for exactly one prior shape. This phone's state file is a Flyway migration run once at launch.
A change is expand-then-contract: release k reads the new form, k+1 writes it, and k+1 ships only
once k is live on the App Store for everyone. One release behind, everything works both ways.

**What a member sees.** One release behind: a banner they can dismiss, "Somebody you talk to is using
a newer version of Outpost", back next launch if still true. Two behind: messages still arrive;
anything newer is saved, shows as "Needs a newer version of Outpost", and shows normally after the
update without being re-sent. If someone in a room wrote something newer there, that room takes no
writes ("Dana sent something this version can't show…") and a banner stays; removing Dana or leaving
still works. A tester who goes back a build gets a stop screen and the data is untouched. Settings
shows the version.

**What the update check shares.** No server, no call to Apple. Each phone puts the format number it
reads (decision 3: and its App Store build number) inside the sealed packet it already sends.
Everyone it sends to learns that number and roughly when it changed, including someone removed from a
room until the phone stops writing to them. iCloud sees only packet sizes and that a packet is not
yet signed for. The store opens only on the member's tap, and Apple then sees the visit.

**Before any code:** confirm the promises in section 2 (CLAUDE.md rule 1).

**Your decisions** (recommendation in bold):
1. *Old history* is never converted and always readable. A rule fix ships as a new message type; once
   a room has seen it, the old type is ignored from anyone whose message shows they saw the new one.
   Cost: a modified app that hides what it saw keeps the old rule until removed. **Yes.**
2. *Pacing:* read in k, write in k+1, and k+1 reaches outside testers and the store only after k is
   the store's version with its phased release done. My reading of "after one release has passed". **Yes.**
3. *What the banner compares.* Format only: heard only at a format step, which is rare. Plus the App
   Store build number: heard after any newer store release, as you asked; contacts learn the exact
   build. **Add the build number, sent only by App Store copies.**
4. *The hold:* a member with a modified app can stop others writing in a room until removed. And a
   changed key hand-off is written in the shape the recipient announced, so no room goes unreadable
   over an update they were never offered. **Yes to both.**
5. *No App Store lookup* (tells Apple the phone's address each time it opens; the only thing that
   "just looks"), *no developer-edited public iCloud record* (a server in all but name), *no
   build-age reminder* yet (TestFlight ends builds at 90 days). **No to all three.**

**Part One (section 5), build now:** stamps, refusing newer, keeping and later showing newer items,
the hold, the state-file check, notices, version in Settings. **Part Two (section 6), at the
freeze:** pinned fixtures, the previous-release reader, the room history setting and other changes.

---

Spec, rewritten 2026-11-11 after review (42 findings, 2 blockers), branch `overnight-2026-10-31`.
Nothing in the repository was changed, built or run. `Sources/` is `Packages/Carpenter/Sources/`,
`Tests/` is `Packages/Carpenter/Tests/CarpenterKitTests/`.

Tags: **read** = the line was read for this spec. **inventory** = from `migration-research-code.md`,
not re-read. **web** = from `migration-research-web.md` at the URL it gives. **inferred** = reasoned,
not checked. **not verified** = could not be checked. Everything is PROPOSED unless marked RULED.

Rulings that bind (all read):
- RULED 2026-09-12, version numbering (`docs/decisions.md:169-203`): `0.x.0` for a breaking change,
  the build number rises by one per upload and never resets, two TestFlight groups.
- RULED 2026-11-10, "Get rid of the older layout stuff" (`docs/decisions.md:6509-6537` in the working
  tree). Its "What it costs" line (a reader for the version before it, once testers exist) is
  Claude's text inside that entry. Griff's request of 2026-11-11, "We'll support ONE prior message
  format", is what binds that now.
- Griff's standing rules: no servers; nothing reads a format no build writes; no app code only
  tests call; no comments in Swift.

## 1. The model

| Kind | What | Rule |
|---|---|---|
| **Kept** | Saved messages: the entry envelope and its sealed payload, plus the signed forms every phone re-checks when it replays a room (invitation, join confirmation, key-change proof, room id, signed pair link, attachment seal), device certificates, device removals, the erase-everywhere mark | Never converted. Every form ever written stays readable. |
| **Passing through** | Packet body and its lists, key grants, receipts, records a member's devices write for each other, device approval, invitation codes, tap-to-swap frames, photo copies | Read on arrival. One prior shape is read. |
| **This phone's own** | `state.json`, keychain items | Converted while decoding, at the first launch of the new build. |

Why kept forms cannot be converted: a signature and hash are taken over bytes the reader rebuilds
from its own layout (`Sources/CarpenterKit/Log/Entry.swift:54-58,66-77`, read). The log is verified
again at every launch (`Sources/CarpenterApp/Session/AppSession.swift:464-480`, read). Edits,
reactions, room links and removals name entries by hash. Only the author's device could re-sign, and
that changes the hash. Membership entries are replayed by every phone to build the member list
(`Sources/CarpenterKit/Membership/RoomRoster.swift:281-360`, read), so they can never be dropped.

So "one prior format" applies to the second and third kinds. For kept forms the design needs no
conversion: the envelope never changes, a payload body only gains optional keys, and anything else
is a new payload type number (decision 1).

## 2. What it must guarantee

Each sentence is something a test tries to break. Griff confirms them before code.

**Reading**
1. A build reads everything the release before it wrote, in iCloud and on the phone.
2. A kept message is readable by every later build.
3. A build never acts on a newer form as if it understood it. Once a room has seen a fixed rule, an
   older form is not applied by the weaker rule to anyone whose message shows they saw the fix.

**Meeting something newer**
4. An item stamped newer that this phone can verify is saved whole, with the same hash and
   signature, before the packet is signed for. After the update it shows without being sent again.
   Keys or photos for it may have to be received again.
5. A phone never saves an item it could not verify, and never signs for a packet it did not take
   whole. The signed kinds in a packet (items, identities, device certificates, device removals)
   are always taken when they verify, whatever the packet's stamp says.
6. A room is held (nothing written there except a removal or leaving, no key handed on) only while
   somebody who may write there has written something stamped newer than this build. Removing that
   person, or leaving, lifts it. On an Outpost only the owner's own newer item holds it.
7. A state file saved with a newer shape is not opened and not written over, by the app or the
   notification extension. Nothing is erased or created before that check.
8. A number another device chose is only compared, never used as a loop bound, size or index.

**Being told**
9. The member is told when somebody they talk to, or another of their own devices, announces a newer
   format (decision 3: or a newer App Store build). They can dismiss it. It comes back at the next
   launch only if it is still true.
10. A notice that cannot be dismissed shows only while a room is held.
11. Nothing a contact, a removed member or a removed device can forge holds a room or pins a notice.

**What it shares**
12. The number is sealed inside the packet. iCloud can still see a packet's size and that a phone has
    not yet signed for one. Everyone this phone still sends to learns the number and roughly when it
    changed, including somebody removed from a room until the phone stops writing to them. An
    invitation's stamp is outside any seal and any signature; it only picks which sentence the
    member reads.
13. The store opens only when the member taps.

## 3. The mechanism

### 3.1 The numbers

`FormatNumber.current: Int` in a new `Sources/CarpenterKit/Log/FormatNumber.swift` (the name is not
in Darwin, Foundation or SwiftUI as far as a search of the SDK headers would show; not verified, the
lint's symbol rule checks). It is the highest format this build reads. It is 1 in the first tester
build and moves only when a release first reads a form an older build must not act past.

| Key | Meaning | Where |
|---|---|---|
| `version` | The lowest format a reader needs to act on this item. 1 unless the item uses something newer. | Payload envelope (exists today), packet body, records a member's devices share, invitation code |
| `reads` | The writer's `FormatNumber.current`. Only for the notice and, later, for a writer to pick a recipient's shape (decision 4). | Packet body, records a member's devices share |
| `build` | The writer's build number, from App Store copies only. Only if decision 3 is yes. | Packet body |
| `shape` | Which shape `state.json` is in. Raised with every change to `PersistedState`. | `state.json` |

The payload key stays `version`: `Payload.version` is already written as 1 and nothing reads it
(`Sources/CarpenterKit/Log/Payload.swift:78,84`, read; grep of `Sources/`). It is inside the seal and
the ciphertext is what the entry signs (`Sources/CarpenterKit/Crypto/SealedPayload.swift:16-20`,
read). Renaming it is churn. The other containers use the same key with the same meaning. This is
Signal's design: one integer per message saying what a reader must understand (web,
`requiredProtocolVersion`).

`state.json` gets its own `shape` rather than `FormatNumber`, because a release can add a state key
without moving the format, and the file is decoded field by field and rewritten whole (CLAUDE.md, "A
hand-written decoder"), so an older build with the same format would drop the key. Keychain items
take no stamp: an item's shape never changes, and a new shape is a new key name.

Invitations and device approvals: an invitation carries `version` because its sentence is the only
thing it changes. A device approval carries none: the phone waiting for approval was just installed
and is the newest build (inferred). Anybody holding the identity can write an approval record
(`Sources/CarpenterKit/Crypto/DeviceApproval.swift:101-111`, per review, not re-read), so a stamp
there would be one more thing a removed device could forge.

### 3.2 What may change, and how

| Change | Rule |
|---|---|
| **Add** an optional key to a **payload body** or to this phone's own state | Absent means what it meant before. No number moves, but `shape` moves for state. Never add an enum case that rides in a body: an unknown raw value fails the whole body (inventory 2.4). |
| **Add** anything to a packet, a key grant or a devices' record | Stamped `version` = F and sent in a packet of its own. The first of a member's devices to collect a packet signs for it and the sender withdraws it, and the others get only what that device relays in typed fields (`Sources/CarpenterApp/Session/AppSession+Sync.swift:196-199,468-478,584-586`; `Sources/CarpenterKit/Sync/SiblingMail.swift:117-125`, per review, not re-read). An older device must leave such a packet for the newer one. |
| **New payload type** an old build may skip | New `PayloadType` number, `version` 1, fallback text if it should be seen. |
| **Must be understood** (who is in a room, keys, removal, access) | `FormatNumber.current` moves (3.3). A kept body change is a new payload type number stamped F; the old type stays readable for history. A passing-through change keeps one `Prior` (3.4). |
| **Closes a hole** | Passing-through: no `Prior`; the old shape is refused from the fixing release. Kept: the new type replaces the old; a new build ignores an old-type entry whose clock had seen (`hadSeen`, `Sources/CarpenterKit/Log/Projection+Standing.swift:162-164`, per review) an entry of the new type from a current member of that room (decision 1). |
| **Frozen** | Never changed. A change here is a new place old builds never read, or a wipe, and goes to Griff each time. |

**The frozen list.** One rule for every signed layout: frozen, because an older build rebuilds the
bytes without any new field and refuses the signature, so "growing" a signed form is refusing it.
- Entry signing bytes, hash and JSON keys: `Entry.swift:54-58,66-77,232-249` (read).
- Payload seal and associated data: `SealedPayload.swift:16-26` (read). Payload envelope keys:
  `Payload.swift:76-89` (read).
- Packet wrap and contexts: `Sources/CarpenterKit/Sync/SyncEngine.swift:139-160,195-205` (read).
- Device certificate and removal layouts: `Sources/CarpenterKit/Crypto/DeviceCertificate.swift:96-107,203-222`
  (inventory). The erase-everywhere mark: `Sources/CarpenterKit/Crypto/Deathmark.swift:21-33` (read).
  A removal and the mark must be obeyed by a device on any build.
- Invitation attestation `Sources/CarpenterKit/Membership/MembershipAttestation.swift:92-110`, join
  confirmation `Sources/CarpenterKit/Log/Bodies/MembershipBodies.swift:28-31`, key-change proof
  `Sources/CarpenterKit/Crypto/EpochChain.swift:59-75`, room id
  `Sources/CarpenterKit/Membership/RoomFounding.swift:7-11`, signed pair link
  `Sources/CarpenterKit/Membership/Invite.swift:54-58`, attachment seal
  `Sources/CarpenterKit/Crypto/SealedAttachment.swift:63-99`, photo copy wrap
  `Sources/CarpenterKit/Crypto/PhotoCopy.swift:59-67` (all read).
- The 96-byte identity `Sources/CarpenterKit/Crypto/IdentityStore.swift:43-62` (read), recovery key
  v2 `Sources/CarpenterKit/Crypto/RecoveryKey.swift:44-91` (inventory; :84-91 read), every `Domain`
  string `Sources/CarpenterKit/Crypto/Identity.swift:254-314` (read).
- The device request, two public keys written unsealed (`DeviceApproval.swift:4-55`, inventory).
- Everything iCloud can read: zone names, record types, record-name shapes, the scanned fields
  (`Sources/CarpenterCloudKit/CloudKitMailbox.swift:33-37`, read), subscription IDs
  (`Sources/CarpenterKit/Sync/PushChannel.swift:10-16`, read), and the two plain prefixes on every
  devices' record, `carpenter.signed.v1\n` and `carpenter.devices.v1\n`
  (`Sources/CarpenterKit/Sync/SiblingFeed.swift:205,272`, read). Renaming any of these to `v2` would
  tell Apple which accounts moved (inferred). A changed wrapper is stamped inside the seal instead.

Not signed into the envelope: a format number. The envelope can then never gain a signed field
without older builds refusing those entries. Signing one in now changes every layout and would only
let an old build say why it refused. Left out (PROPOSED).

### 3.3 When a release may start writing a new form

- Release k: `FormatNumber.current` becomes F. It reads F and F-1, writes only F-1 forms, and its
  packets say `reads: F`, so phones on k-1 show the first notice.
- Release k+1: starts writing F forms. A phone on k reads them. A phone on k-1 saves what it can,
  holds a room where a current member used F, and shows the notices.
- A release does one or the other, never both, so the format moves at most every second release.
- **A release is counted on the App Store.** The release that first writes F goes to outside testers
  and the store only after the release that first reads F is the store's current version with its
  phased release finished. Anyone can install a phased release by hand at any time; only automatic
  updates are staged over seven days (web,
  developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases). A
  reader that only went to TestFlight is never followed by a writer. External TestFlight builds can
  wait for review (web, developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview).
- A fix that cannot wait is written at once, on Griff's word. Phones one behind then get both notices.
- A phone whose iOS the new release no longer supports cannot take the update. Each minimum-iOS raise
  goes to Griff with that cost.

This is expand and contract (web, martinfowler.com/bliki/ParallelChange.html) and what Session did
with a date (web, getsession.org/groups-v2-how-to-upgrade).

### 3.4 Reading one prior shape (Part Two; the recipe for the first change)

For passing-through forms and the phone's own state only. Kept bodies never get a `Prior`.

- Release k: the new shape is the model. The old shape is a nested `Prior`, `Codable`, with
  conversions both ways. The writer encodes `Prior` and stamps the old number.
- Release k+1: the writer encodes the new shape and stamps F. The conversion back is deleted.
- The `Prior` reader is deleted **in the release that moves the number again**, so a build always
  reads `current` and `current - 1`.
- The container decodes `version` first and picks the shape in its own hand-written `init(from:)`.
  No `decoder.userInfo`.
- Every conversion of the phone's own data happens while decoding and writes nothing. The
  notification extension's stores swallow every write (`Sources/CarpenterKit/Storage/ReadOnlyStorage.swift:10,33,47`,
  per review), and it may be the first process of a new build to run.
- After a prior reader is deleted, a packet from a phone two formats back whose lists no longer
  decode is signed for once its entries are on disk, and its lists are dropped on purpose. A key
  grant addressed to this phone that will not unwrap or decode leaves the packet unsigned
  (`SyncEngine.swift:182-185` drops it silently today, read).
- On the first launch after an update, the arrival work done once per entry (photos owed,
  `Sources/CarpenterApp/Session/AppSession+Attachments.swift:291-304`; removal notes,
  `AppSession+Sync.swift:253-264`, per review) runs again over saved entries stamped above the format
  the old build read. The new build records that it has done so in a state key of its own.
- Keys a phone failed to read: the sender offers them again after its next launch, because
  `issuedGrants` is in memory only (`AppSession.swift:195`, per review; inferred).

### 3.5 What a phone does with something it cannot read (Part One unless marked)

| What arrives | What the phone does | Signed for? |
|---|---|---|
| An entry whose payload says `version > current` | Verified and saved like any entry; integrating never opens the payload (`Sources/CarpenterKit/Log/Replica.swift:190-229`, read). `Payload.decode` throws. Rendered as a newer placeholder before the type switch, so a newer edit, reaction, withdrawal, removal or departure is never applied. Holds the room under 3.6. | Yes: it is on disk. |
| An entry whose signature fails | Not saved, as today (`Replica.swift:381-389`, read). | No (`Sources/CarpenterKit/Sync/SyncSession.swift:549-574`, read). |
| A packet whose body says `version > current` | Takes entries, identities, certificates and removals, each checked as today; skips every other list and every key grant. Sets the first notice. | No. It waits in the sender's iCloud up to nine days (`SyncSession.swift:203-205`; withdrawal `Sources/CarpenterApp/Session/AppSession+Sync.swift:583-591`, read), then is read whole after the update. |
| A packet with `reads > current` | Read whole as today. Sets the first notice. | Yes. |
| A devices' record with `version > current`, from a device that counts (`siblingTrust == .full`, `Sources/CarpenterApp/Session/AppSession+DeviceSync.swift:139-153`, read) | Takes certificates, removals and entries; skips keys, people, addresses, photos, asks and forwarded grants. The mail is not marked taken, so the writer keeps it (30 days, `SiblingMail.swift:115`, inventory). Sets the own-device notice. | Not taken. |
| The same from a device that does not count | Today's refused record. No notice. | — |
| `state.json` with `shape > current` | Checked first in `load()`. Not opened, nothing written, nothing erased, no device key made. Stop screen. | — |
| An invitation code with `version > current` | Its own sentence. | — |
| A list from two releases back that no longer decodes | Part Two, 3.4. | — |

Why this keeps the acknowledgement rule: saving happens before signing (`AppSession+Sync.swift:266-283`,
read), and a packet with anything skipped is never signed for. Entries from a new device or a new
person in a stamped packet still integrate, because their certificate and identity are taken from
the same packet: `integrate` refuses an entry with no registry (`Replica.swift:194-199`, read), the
sender's introduction rides in every planned packet (`Sources/CarpenterKit/Sync/PacketPlan.swift:63,72`,
read), and certificates are admitted before entries (`SyncSession.swift:518-547`, read). The log file
re-encodes each entry from its fields (`Sources/CarpenterKit/Storage/LogStore.swift:94-104`, read),
which loses nothing only while the envelope's keys are frozen.

Writer rule for later builds (Part Two): stamped content travels in a packet of its own, so the
packet carrying entries stays one an older phone can sign for. Otherwise the sender's phone shows
"Sent. Not received yet." for a message the older phone did show
(`Sources/CarpenterUI/Components/Messaging/DeliveryMarkView.swift:106,126-130`, per review). An
unsigned packet is unwrapped and decoded again every round until withdrawn (`SyncSession.swift:471-489`,
read); that cost is bounded by the nine days.

### 3.6 The hold

- **Where it is seen.** The standing walk opens only roster-shaping payloads
  (`Sources/CarpenterKit/Log/Projection+Standing.swift:13,50-51`, read), so it cannot see an unknown
  type's payload. The mark goes on the rendered entry instead: `LogRenderer.step`
  (`Sources/CarpenterKit/Log/LogRenderer.swift:138-148`, read) checks `payload.version` before the
  type switch and renders `.unrenderable(type:fallback:newer: true)`.
- **Who can hold.** In the walk (`Projection+Standing.swift:267-296`, read), after the cut check and
  before `guard let payload`, a newer entry is never handed to `roster.apply` or to `claim`. It
  records its author only if the author is a member who may write at that point
  (`RoomRoster.swift:127-129`, read). The room is held while any recorded author is still a member
  who may write at the end of the walk. This matters because `apply` acts on a departure by its type
  alone (`RoomRoster.swift:355-356`, read).
- **What it stops.** One shared check used by `append` (`AppSession.swift:367-383`, read) and photo
  send (`Sources/CarpenterApp/Session/AppSession+Messaging.swift:89-95`, read; it uploads before
  `append` runs). It lets `.removal` and `.departure` through (`AppSession+Membership.swift:521,533`,
  read). `grantsOwed()` skips a held room (`Sources/CarpenterApp/Session/AppSession+Peers.swift:127-140`, read).
- **An Outpost.** `append` skips the roster for a wall (`AppSession.swift:373`, read), and readers
  write into the owner's wall room. The owner's Outpost is held only by an entry the owner wrote
  (from another of the owner's devices) that is newer: in the wall room, or among what
  `accessChanges(of:)` reads (`Sources/CarpenterKit/Log/Projection+Outpost.swift:33ff`, read in
  part). A reader's newer comment is a placeholder and holds nothing.
- **What the member sees.** `RoomStanding` (`Sources/CarpenterKit/Model/ReadModel.swift:29-35`, read;
  computed at `AppSession+Membership.swift:545-553`, read) gains `.heldForUpdate(by: Member)`, and the
  composer line names that member.

Without the hold: as a member on an old build, I keep writing to somebody a newer removal took out of
the room, under a key they hold.

What the hold cannot see (decision 4): an entry this phone holds no key for renders `.sealed`
(`LogRenderer.swift:139-146`, read), so its stamp is unread. If keys arrive only in stamped packets,
a phone two behind never gets a rotated key and the room is not held. The recommended answer is that
a writer sends a changed key hand-off in the shape the recipient last announced in `reads` (Part
Two). The other answer, holding every room a sender shares while their stamped packet waits, rests on
weaker evidence: a removed device still holds the pairwise secret.

### 3.7 Pinned forms (Part Two)

CLAUDE.md: a round trip proves nothing. Today's pinned tests build expected bytes with the app's own
`CanonicalBytes.payload` and `Domain` (`Tests/SealBindingTests.swift:52-69`, read).

- `Tests/Forms/kept/<n>/` and `Tests/Forms/passing/<n>/`: one file per form with the exact bytes
  build n writes, plus test keys. Declared as test resources (`Packages/Carpenter/Package.swift:61-68`
  declares none today, per review). Written once; never edited after it ships (`Scripts/check-all.sh`
  gains `git diff --exit-code <last release tag> -- Tests/Forms`).
- `WhatThisVersionWritesTests`: decode each, compare field by field with values in the test, verify
  signature and hash; where encoding is deterministic, assert today's code produces the stored
  bytes. **Kept forms: every number ever shipped. Passing and own: `current` and `current - 1`.**
- `Scripts/check-previous-release.sh`: `git archive` the last release tag, copy in this build's
  newest forms and a test file, run it there. It asserts what section 2 says an older build does.

## 4. The update notice

### 4.1 Every option

| # | Option | What it shares, with whom | Verdict |
|---|---|---|---|
| 1 | Something saved is stamped above this build | Nothing new. | **Build** (the placeholder; the hold's notice). |
| 2 | `reads` (and `build`) in the sealed packet and the devices' record | With everyone this phone sends to, and its own devices; see guarantee 12. | **Build.** The only way to learn an update exists before anything is unreadable, without asking anybody. A contact can lie upward; the cost is a banner the member dismisses. |
| 3 | App Store automatic updates | Nothing from the app. On by default; with them off the store notifies (web, support.apple.com/en-us/102629). | **Rely on it.** |
| 4 | TestFlight | Nothing from the app. A build stops opening 90 days after upload; testers are told of new builds (web, testflight.apple.com). | **Rely on it.** |
| 5 | Release notes | Nothing. | **Use.** |
| 6 | The build's own age, as a reminder | Nothing; needs a build date in Info.plist. Fires whether or not an update exists (Delta Chat moved 90 to 183 days for that, web). | **Not in the first tester build** (decision 5). |
| 7 | The build's age as a hard stop (Signal, 90 days, web) | Nothing. | **Refuse.** Strands a member with no newer build. |
| 8 | `itunes.apple.com/lookup?bundleId=` | Address, app id and time to Apple each call; probably the build via the default User-Agent (web; not measured). Undocumented for this use. | **Refuse** (decision 5). |
| 9 | A developer-edited record in the public CloudKit database | Makes the developer account something every phone asks. | **Refuse** (decision 5). |
| 10 | StoreKit | No API on iOS 18 to 27 reports a newer version (web). `AppTransaction` gives the installed copy only (`App/Carpenter/AppRootView+Supporter.swift:22`, read). | Not possible. |
| 11 | A file on a website | A server. | Refused by standing rule. |

### 4.2 What the member sees, and where

Inline, never an alert: "Avoid using an alert merely to provide information" (web, HIG Alerts,
developer.apple.com/tutorials/data/design/human-interface-guidelines/alerts.json). The banner takes
the iCloud hold's place and shape (`Sources/CarpenterUI/Theme/ICloudHold.swift:4-40`, read), in the
root's top inset (`Sources/CarpenterUI/Screens/RootView+Outpost.swift:159-163`, read).

Draft copy. Every string: `COPY BEGIN/END` with a new id from `python3 Scripts/copy-review.py new-id`,
status `NEEDS HUMAN REVIEW`, `bundle: .module`, the name through `Branding.displayName`. Words follow
the copy terms (shown, saved, received, item or message; never "entry" or "log").

| When | Where | Words (draft) | Dismiss? |
|---|---|---|---|
| A contact's packet says `reads` (or `build`) above this build | Banner; a Settings row | "Somebody you talk to is using a newer version of Outpost." Button: "Open the App Store" | Yes. Held in memory only; back at the next launch if still true. |
| A record from another of the member's devices that counts says so | Banner | "Another of your devices is using a newer version of Outpost." Same button | Yes, same |
| Some room is held | Banner | "Something arrived that this version can't show. It's saved on this phone." Same button | No, while any room is held |
| A newer item | In the conversation, at the item | Its fallback text if any, then "Needs a newer version of Outpost." A newer plumbing item shows nothing. | — |
| A held room | Where the member types | "Dana sent something this version can't show. Nothing can be written here until this phone can show it." | — |
| `state.json` from a newer shape | Whole screen, on `DataProblemView` | "This phone's data was saved by a newer version of Outpost. Nothing was changed. Install the newer version to open it." Same button | — |
| A newer invitation code | The sheet it was opened on | "That invitation was made with a newer version of Outpost. Update, then open it again." | — |
| Settings | A row, always | "Version" and `Branding.version` (`Sources/CarpenterKit/Branding.swift:37-47`, read) as `Text(verbatim:)`. No screen shows it today; `ReportView.swift:47` only sends it (read). | — |

The button opens `https://apps.apple.com/app/id<App Store id>` (web, StoreKit "Requesting App Store
reviews" sample), the id from `Config/Branding.xcconfig` through Info.plist the way `ReportFormURL`
goes (`App/Carpenter/Info.plist:5`, `Branding.swift:23-28`, read). In a TestFlight copy
(`Distribution.channel()`, `AppRootView+Supporter.swift:8-33`, read) there is no button and the line
ends "Open TestFlight to update." Whether that link opens the App Store app directly or passes
through a non-Safari default browser first is **not verified**; nothing a member reads says
"only Apple sees it" until a real phone has been checked.

---

## 5. PART ONE: build now

Everything here is the same whatever format changes come before the first tester build, because it
is what build 1 does when it meets build 2 or 3. Each step is one commit; tests are written first
and fail first. The filtered suite while working, the whole suite before each commit. Cleanups are
their own commits. All copy follows 4.2.

How tests make newer items without app code only tests call: a test decodes a hand-written JSON
`Payload` (`{"type":…,"version":2,"body":…}`; `Payload` is `Codable`) and passes it to the existing
internal `append(_:to:)` on a peer session. Newer packets are sealed by hand in the test with the
documented wrap (`SyncEngine.swift:139-160`), the way `SealBindingTests` writes layouts by hand. A
newer devices' record is a `SiblingFeed` decoded from JSON and sealed with the app's own sealing
call. Two devices of one member use `keychain.sibling()` and `approveNewDevice(_:)`.

**Step 1. Cleanups, four commits.** No new test where the form can no longer be built.
- a. Remove the unbound-writer fallback (`SealedPayload.swift:71-76`, read) and make `writer`
  non-optional (`SealedPayload.swift:22,37,57`, per review), so no test can still write that form.
- b. Remove the pass-through in `Sources/CarpenterKit/Crypto/PhotoCopy.swift:82` (inventory; re-read
  first).
- c. Remove `Payload.canonicalBytes` (`Payload.swift:91-100`, read; no caller).
- d. Remove the retired-identity branch (`IdentityStore.swift:45`, `CryptoError.retiredIdentity`,
  `AppSession+Identity.swift:32-37`, read), so a wrong-length identity is `malformedKey` and lands on
  the data-problem screen instead of erasing the phone. Test first: a 64-byte identity item, then
  `load()`: state is `.failed`, nothing erased. Under RULED 2026-11-10 ("any cruft like that is fair
  game").

**Step 2. The number, the guard, and how newer items show.**
- Tests first, `AnItemFromANewerVersionIsKeptTests`: a payload of unknown type 9999, `version` 2, junk
  body, from a member: received, saved, same hash after a relaunch from disk, its packet settled,
  `decode` throws, shown with "Needs a newer version"; the same at `version` `Int.max`. A `.post` at
  `version` 2 shows the placeholder line. An `.edit`, `.reaction` and `.tombstone` at `version` 2
  leave their target unchanged. Type 9999 at `version` 1 with no fallback: not in the conversation,
  not unread, not the room's last line, not `latestIncomingMessage()`
  (`AppSession+Messaging.swift:503-516`, read). With fallback text: shown with it.
- Code: `FormatNumber.swift` (`enum FormatNumber { static let current = 1 }`). `Payload.init` loses its
  `version:` parameter and always writes 1 (`Payload.swift:84`). `Payload.decode` throws a new
  `LogError` case when `version > FormatNumber.current` (`Payload+Making.swift:165-167`; `LogError`
  at `Replica.swift:22`). `RenderedContent.unrenderable` gains `newer: Bool` (`LogRenderer.swift:10`);
  `step` checks the stamp before the switch (`:148`). `isConversation` becomes
  `!plumbing.contains(type) && (PayloadType.allKnown.contains(type) || has fallback text)`
  (`ProjectionSupport.swift:4-6`; `allKnown` at `Payload.swift:55-60`, read). The placeholder text at
  `Projection.swift:107-110`: newer gives fallback then "Needs a newer version of Outpost."; "Not
  supported by this version." is deleted with its words (chunk `80dfd221` stays `NEEDS HUMAN REVIEW`).

**Step 3. The hold.**
- Tests first, `ARoomWithSomethingNewerIsHeldTests`: (a) a member's newer post: `append` throws
  `heldForUpdate`; photo send throws with zero uploads in the fake media mailbox; `grantsOwed()` has
  nothing for that room; `standing(in:)` is `.heldForUpdate(by:)` that member. (b) Nothing held for a
  newer item from a removed member under the old key, from somebody never admitted, or from a member
  after their removal (cut). (c) A newer departure and a newer removal change nobody's standing and
  hold. (d) Removing the author of the newer item succeeds and lifts the hold; leaving a held room
  succeeds. (e) Outpost: a reader's newer comment holds nothing; the owner's own other device's newer
  item holds the owner's Outpost.
- Code: `RoomRoster` gains the set of newer authors and `heldBy` (members who may write)
  (`RoomRoster.swift`). The walk change in 3.6 (`Projection+Standing.swift:267-296`). One shared
  write check used by `append` and photo send (`AppSession.swift:373-383`,
  `AppSession+Messaging.swift:89-95`). `grantsOwed()` skips held rooms (`AppSession+Peers.swift:127-140`).
  The Outpost rule (`AppSession+Outpost.swift`, `Projection+Outpost.swift`). `RoomStanding.heldForUpdate`
  (`ReadModel.swift:29-35`, `AppSession+Membership.swift:545-553`). `MembershipError.heldForUpdate`
  (`MembershipAttestation.swift:172`) and its sentence in `Sources/CarpenterApp/Session/SessionProblem.swift`.
  The composer line (`ConversationView+Composer.swift:223`, `PostComposerView.swift:128`, inventory).
  The held state goes through the projection cache (`cached(_:_:_:)`, CLAUDE.md).

**Step 4. Packet stamps.**
- Tests first, `APacketFromANewerVersionTests`: (a) `version` 2 with entries, a new device's
  certificate and entries from it, a new person's identity and entries from them, a device removal,
  a key grant, a repair request and an address: every entry saved, certificate admitted, removal
  applied, grant not adopted, request and address ignored, packet not settled, first notice set. (b)
  `version` 1, `reads` 2: read whole, settled, first notice set. (c) `version` and `reads` at `Int.max`:
  as (a) and (b), no crash. (d) A body without `version` does not open (no build writes one).
- Code: `SyncEngine.Body` writes `version: 1` and `reads: FormatNumber.current`; `init(from:)`
  (`SyncEngine.swift:104-120`) reads `version` first and above `current` decodes only `entries`,
  `identities`, `certificates`, `revocations` and marks itself skipped. `unpack` decodes no grants
  for a skipped body (`:182-185`). `Delivery` (`SyncEngine.swift:40`) carries `skipped` and `reads`.
  `integrate` does not settle a skipped packet (`SyncSession.swift:574`) and reports who announced a
  newer number. `AppSession+Sync.swift` turns that into the notice.

**Step 5. Devices' record stamps.**
- Tests first, `ARecordFromYourNewerDeviceTests`, with `keychain.sibling()` and `approveNewDevice`:
  (a) an approved sibling writes a `version` 2 mail record: certificates, removals and entries taken;
  mail not marked taken; epochs, people, addresses and forwarded grants not adopted; own-device
  notice set. (b) A removed device writes the same: refused as today, no notice. (c) `version` 1,
  `reads` 2: read whole, notice set.
- Code: `SiblingFeed` gains `version` and `reads` and the same skipped decode (`SiblingFeed.swift:30-58`
  and its `init(from:)`). In `AppSession+DeviceSync.swift:79-125`, a skipped feed acts only when
  `trust == .full`, and never reaches the `.mail`/`.catchUp` "took" lines (`:101-107`).

**Step 6. The state file.**
- Tests first, `DataSavedByANewerVersionIsNotOpenedTests`: a `state.json` with `shape` 2 written
  through the documents store. `load()` ends in the refused state, `enrolment` nil, no device key
  saved, nothing erased. Then a sync round, a device-sync start and a push-arrival round: the file's
  bytes are unchanged. The same with read-only storage (the extension). An undecodable `state.json`:
  `enrolment` nil and bytes unchanged after a round (the same hole today: `load()` sets `enrolment`
  at `AppSession+Identity.swift:45-46` before the state load at `:47`; `sync` checks only `enrolment`,
  `AppSession+Sync.swift:18`, and ends in `saveState()`, `:81`, which writes the empty default,
  `AppSession.swift:99,231-241`, all read). And `TheStateFileSaysItsShapeTests`: the sorted list of
  `PersistedState`'s stored properties (by `Mirror`) and `shape` are spelled out in the test, so
  adding a field fails until both change.
- Code: `PersistedState` writes `shape`; its `init(from:)` reads it first, required, and throws a
  dedicated error when above (`Sources/CarpenterApp/Session/PersistedState.swift`). In `load()` the
  state decode moves to the top of the `do` block, before `wasRemoved`, the identity load, the erase
  and the device key save (`AppSession+Identity.swift:19-43`), held in a local and assigned where it
  is now. The refusal clears `enrolment` and sets a new `AppSession.State` case (`AppSession.swift:48-58`;
  `RootDecisions.swift:10`). `saveState()` writes nothing in that state (`AppSession.swift:231`).
  `DataProblemView` gains the Update button (`Sources/CarpenterUI/Screens/Identity/DataProblemView.swift:14-35`).
  `thisDeviceID` is nil with `enrolment` nil (`AppSession.swift:82`, read), so device sync does not
  start (inferred).

**Step 7. Invitation stamp.**
- Tests first, `AnInvitationFromANewerVersionSaysSoTests`: a code with `version` 2 and an otherwise
  junk body gives the newer sentence, not "does not hold up to checking"; a code without `version`
  is malformed.
- Code: `Invite` writes `version` outside the attestation (`Invite.swift:21-25`); `decoded(from:)`
  (`:28-33`) reads it first; a new `MembershipError` case and sentence in `SessionProblem.swift`
  beside `.malformedInvite` (`:170`).

**Step 8. The notices and the version in Settings.**
- Tests first, `TheUpdateNoticeTests` (what a screen is told): a packet with `reads` 2 raises the
  contact notice; dismissed, it is gone for this session; a new session without such a packet shows
  nothing; with one, it shows again. A held room raises the notice that cannot be dismissed; removing
  the author clears it. A sibling's newer record raises the own-device notice. A removed device's
  record and a removed member's newer item raise nothing that cannot be dismissed. Only comparison is
  done on the numbers (`Int.max` is fine).
- Code: a new `Sources/CarpenterApp/Session/AppSession+UpdateNotice.swift` (seen flags in memory, the
  held state from the projection). `Sources/CarpenterUI/Theme/UpdateNotice.swift` beside
  `ICloudHold.swift`, in a `GlassEffectContainer` if it uses glass; `RootView+Outpost.swift:159-163`;
  `App/Carpenter/AppRootView+Ready.swift`; a Settings row through `SettingsRow` and `IconTile`
  (`Sources/CarpenterUI/Screens/You/YouView+Settings.swift`). `Config/Branding.xcconfig` gains the
  App Store id, Info.plist carries it, `Branding.appStoreURL` reads it. The App Store id is not
  known yet; not verified that the app has one.
- If decision 3 is yes: the packet body also carries `build` from App Store copies, from
  `CFBundleVersion` passed into the session the way the channel is (`AppSession+Supporter.swift:17,42`,
  per review); the contact notice compares it too. One key, one test case.

**Step 9. Subscriptions.** The two sweeps delete every subscription they do not recognise
(`Sources/CarpenterCloudKit/CloudKitMailbox+Subscriptions.swift:32-35`;
`Sources/CarpenterCloudKit/CloudKitEntrySync.swift:111-127`, read), so an older build deletes a newer
build's subscriptions (`docs/testing.md:444-446`, read). Change both to delete nothing they do not
name; the first tester build names none. Whether the device-feed sweep is also what removes the
sync engine's own silent subscription is **not verified**; `LiveSiblingFeedTests` must still show
device pushes arriving. Not covered by `swift test`.

**Step 10. Tap to swap (only if Griff says yes, section 7 question d).** On a frame that will not
decode (`App/Carpenter/TapSwapper.swift:211-214`, read), say "That phone may have a different version
of Outpost." No stamp: the frame crosses plain TCP on `_tapswap._tcp` (`TapSwapper.swift:28`, read).

**Step 11. Docs.** A decisions entry marked by who decided each part; the forms table and frozen list
in `docs/architecture.md`; a format log (number, release that reads it, release that writes it, what
changed, which `Prior` exists and when it goes); the not-provable list in `docs/testing.md`; an epic
and its roadmap line. Copy markers on all of it.

### 5.1 Part One on two Apple Accounts

Alpha runs the candidate. Beta runs a throwaway branch, never merged: `FormatNumber.current = 2`,
`PersistedState` shape 2, and two launch arguments, `--stamp-posts` (posts written at `version` 2)
and `--stamp-packets` (packet bodies at `version` 2). Build once, install everywhere, as CLAUDE.md
says. Software keyboard on for every screen with a field. Count to ten for anything intermittent.

1. Beta, `--stamp-posts`, in a room with alpha, sends a post. Alpha: placeholder line, the room held,
   the composer names beta, sending and a photo both refused with nothing uploaded, the banner that
   cannot be dismissed. Beta's packet is signed for and gone from beta's space.
2. Beta, `--stamp-packets` only, sends a plain post. Alpha shows it and the dismissible banner. After
   three rounds the packet is still in beta's space, unsigned.
3. Beta with no flags sends. Alpha shows the dismissible banner and writes in any room not held.
4. A second room held by beta's stamped post: alpha removes beta. The removal goes, the hold lifts,
   alpha writes, beta sees the removal.
5. Install the throwaway on alpha. Step 1's post shows without being sent again, the hold lifts, step
   2's packet is signed for. This is the only proof of guarantee 4; one build cannot be both.
6. Last, because it leaves alpha unable to open the candidate: put the candidate back on alpha. Stop
   screen. Foreground it and send a push from beta. `state.json`'s bytes (`shasum` in
   `xcrun simctl get_app_container`) are unchanged. Reinstall the throwaway: everything opens.
   Restoring alpha to the candidate then needs a device reset and onboarding per
   `docs/simulator-rig.md`; read its warnings first, never `--reset-account`. If Griff prefers, step 6
   stays a unit test and is reported as not verified on the rig.
7. Put the real build back on every simulator.

Not provable on the rig, so **not verified** until two iPhones on one account and a real TestFlight
install: two devices of one member on different builds (simulators cannot share an account,
CLAUDE.md), the TestFlight update itself, the store link and which app opens it, tap to swap.

## 6. PART TWO: at the freeze

1. **Format changes still wanted, made before the first tester build.** Each costs a format step and
   a kept older rule afterwards: the room history setting (`docs/open-questions.md:221-251`, per the
   first draft: "it has to land before the first tester build"), the per-pair seed, the signed link to
   a room's older key, trimming the devices' shared record (`docs/open-questions.md:42,258,302`,
   inventory).
2. **Pin the frozen forms** (3.7), declared as test resources, and the check that shipped fixtures are
   never edited.
3. **Tag every uploaded build**, so the previous release can be checked out.
4. **At the first format change:** the recipe in 3.4, `Scripts/check-previous-release.sh`, the writer
   rules (stamped content in its own packet; a changed key hand-off written in the shape the
   recipient announced, decision 4), the hole rule in 3.2, the arrival-work rerun, and the
   read-only-session test (a read-only session loads the prior state shape and writes nothing).
5. **At the first App Store build:** decide the build-age reminder (decision 5).

## 7. Questions for Griff

The five decisions are on page one. Smaller ones, each with a recommendation:

- a. **The 2026-09-12 ruling says a breaking release is a wipe.** Recommend it becomes: a `0.x.0`
  release is a format step with a reader for the one before; a wipe is the named last resort for a
  frozen form. It is his ruling, so it changes only on his word.
- b. **How far back a build opens the member's own data** (`state.json`, and the records the member's
  own devices leave in iCloud, which a phone restored from its recovery key months later meets).
  The store offers no build in between, so a member who skips two format steps would lose
  preferences and other things those records hold (`SiblingFeed.swift:31-59`, per review). Recommend
  keeping every conversion for these until he drops one; they are rare and a few lines each.
- c. **The format changes still open** (Part Two item 1). Recommend deciding each before the first
  tester build.
- d. **Tap to swap.** Recommend no stamp and one sentence when a frame will not decode (step 10).
- e. **Device approvals carry no stamp** (3.1). Recommend yes: the waiting phone is the newest build.
- f. **The subscription sweeps stop deleting what they do not name** (step 9). Griff's own devices
  keep any stale subscriptions from earlier development until reset. Recommend yes.

## 8. Not verified, in one place

- Nothing was compiled or run. Every behaviour is from reading.
- Guarantee 4 after an update rests on the projection being rebuilt from the saved log at launch
  (`AppSession.swift:464-474`, read; render cache in memory only, `OpenedPayloads.swift:3-5`, per
  review). Rig step 5 is the check.
- What a sender repeats after a nine-day withdrawal beyond certificates, removals
  (`AppSession+Sync.swift:135-136`, read) and keys. The writer rule (stamped content alone) limits
  what can be lost to the new-form content itself.
- Whether an older device rewriting its devices' record drops a key only a newer device knows
  (inventory 2.14). Under 3.2 such a key is stamped, so the older device leaves it alone (inferred).
- What the notification extension shows for a newer item; step 2's test covers
  `latestIncomingMessage()`, not the extension's own fallbacks
  (`App/CarpenterNotificationService/NotificationService.swift:39-127`, read in the first draft).
- Whether an old extension process can outlive an install.
- The store link through a non-Safari default browser; `itms-beta://`; TestFlight's default for
  automatic updates.
- The App Store id exists.
- Whether `FormatNumber` collides with any SDK name (the lint's symbol rule checks).
- Whether `RoomStanding.mayWrite` being false also hides the remove and leave controls in the UI.
- Lines marked "inventory" or "per review" were not re-read for this rewrite.

## 9. Findings not taken, and why

Numbers are positions in `findings-migration.json`. Every blocker and major finding was checked
against the code; the two blockers were confirmed by reading (`Replica.swift:194-199`,
`PacketPlan.swift:63,72`, `SyncSession.swift:518-547`; `AppSession+Identity.swift:44-47,100`,
`AppSession+Sync.swift:18,81`, `AppSession.swift:99,231-241`, `AppRootView+Sync.swift:57`). Taken in
full: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 28, 29,
30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41 (42 asked for no change). What was not taken, or taken
another way:

- **15 (the hold cannot see keyless entries).** Not taken: "hold every room a sender shares while
  their stamped packet waits". A removed device still holds the pairwise secret, so it could freeze
  rooms it left. Answered instead by decision 4: a writer sends a changed key hand-off in the shape
  the recipient announced.
- **16 (throw on a stamped packet and land in the unopened path).** Not taken for build 1. Throwing
  drops identities, certificates and removals, which is blocker 27 again. Its writer rule (stamped
  content travels alone) is taken for later builds. The "lists fail to decode" branch moved to Part
  Two as it suggested.
- **24 (things to delete).** (a) Taken as one more value on `.unrenderable`, not a flag on the entry,
  because the placeholder text is computed from the content. (d) Taken for device approvals; not
  for invitations: the invitation stamp is unsigned and unsealed, but all it can change is which
  sentence shows, and without it a newer invitation tells the member "Do not use it — ask the person
  by voice" (`SessionProblem.swift:178-181`, read), which is wrong and alarming. Guarantee 12 says the
  stamp is unsealed. (b), (c), (e), (f), (g), (h) taken.
- **40 (an unreadable key grant should leave the packet unsigned).** Taken for Part Two, not build
  1. In build 1 a grant in a shape it does not know arrives only in a stamped packet, whose grants it
  already skips. Making build 1 refuse to sign over a grant that fails to unwrap would leave packets
  unsigned for good over a sender's fault, and the sender would show "Not received" for messages
  that were shown.
- **8 and 22 (the state file).** The fix offered two ways: its own counter, or the build number. Took
  the counter (`shape`): it needs no injected build number, and debug builds all carry build 1
  (`App/Carpenter.xcodeproj/project.pbxproj:446,476,510,559`, read), so a build-number check would
  refuse a dev build on a phone that once held a TestFlight build.

<!-- COPY END 9c6274b6 -->
