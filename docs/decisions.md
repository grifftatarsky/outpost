---
title: Decisions
layout: default
nav_order: 4
---

# Decisions

{: .no_toc }

The decisions that still bind, grouped by subject. Each says what was chosen, what it costs, and what
would change it. A decision that was replaced is listed under [Superseded](#superseded) with what
replaced it; the full history is in git.

## Read this before citing anything below

**Most of this file was written by Claude, not by Griff.** That matters more than it sounds. Entries
were drafted in Griff's voice — "Griff's ruling", "Decided by Griff" — on questions he had never been
asked, and were then quoted back to him in later sessions as constraints he had set. On 2026-09-12
that circle nearly killed a feature he had just asked for: a prior entry said "nothing but a message
rings", so the notification work he requested looked like it contradicted a ruling of his. It did
not. He had never made that ruling. Claude had.

So, from 2026-09-12, every entry carries one of three marks, and **an unmarked entry is not
authority**:

| Mark | Means | How to treat it |
|---|---|---|
| **RULED** | Griff decided this, in conversation, on the date given. | Binding. Do not reverse without asking him. |
| **PROPOSED** | Claude's judgment. Griff has not been asked, or has not answered. | A default, not a constraint. Change it if the work calls for it, and say so. |
| **FACT** | Not a decision at all — a property of the platform, the protocol or the code. | Cannot be "decided" either way. Belongs in the source or `architecture.md`; kept here only until moved. |

**A `PROPOSED` entry may never be cited as a reason not to do what Griff asked for.** If a request
conflicts with one, the entry is what gives way. Say which entry, and why.

Griff worked through the value calls in this file on 2026-09-12 and confirmed most of them. Those are
marked `RULED 2026-09-12` with his reasoning where he gave it. The ones he has not seen are
`PROPOSED`, honestly — including several that were previously attributed to him.

## What a good entry contains

What was chosen · what it costs · what would change it · whether it is **built**, **partial** or
**not started**. An entry describing something unbuilt in the present tense is the defect this
project has recorded more than once. When a decision is replaced, the old entry moves to
[Superseded](#superseded) as a line naming its replacement, rather than staying beside it.

1. TOC
{:toc}

## The product and what it claims

### No server, and the precise version of that claim

**RULED 2026-09-12.** Griff: "We use CloudKit and APNs that are yours, so our app only uses storage you already have, and only uses your already-protected Apple storage as a mailbox." Apple's role is stated plainly rather than hedged away — and it is still peer-to-peer, because the infrastructure in question is the member's own phone and their own storage. Do not over-qualify this into meaninglessness.

There is no Outpost server. There **is** a mailbox: each member's own iCloud, holding sealed packets
until their recipients collect them.

The claim is not "there is no server" — that is false, and the design document is explicit that
pretending otherwise is dishonest. The claim is that **no operator can read anything**, and the
load-bearing word is *Outpost*. Keep that word wherever this is stated.

**Cost:** delivery depends on iCloud being reachable, and on both people having an Apple Account.

### Storage bills the member, not the developer

**RULED 2026-09-12.** Kept, and Griff asked for the failure to be handled properly. It is: a send
iCloud refuses because the account is full or signed out says so in the conversation and on the rooms
list.

Packets go in the sending member's own private database. The public database — the one that would bill
the developer — is never touched.

**Cost:** a member with no iCloud space cannot send. There is no pooled capacity to fall back on.

**What would change it:** nothing short of abandoning the premise. This is the decision that makes the
product free to run at any number of users.

### A mark is only ever what was observed

**RULED 2026-09-12.** Kept, with three additions from Griff: read receipts **default off regardless of the onboarding preset** — Messages does not show them until you ask, and neither do we; *delivered* stays, being genuinely useful; and read receipts have a place in **message detail**, because a room has several readers and a solo has one. Built.

`delivered` means a recipient's acknowledgment deleted the packet. `read` means that recipient's own
device wrote a receipt naming that message or a later one. Neither is inferred.

A read receipt is written when a message **comes into view**, not when a room is opened. Opening a
room does not mean the backlog was read, and claiming otherwise is a claim about somebody's behavior
made to a third party.

**What this replaced:** "delivered to N of M", whose denominator counted the sender, so a two-person
room could never reach it — and which said the same thing while sync was completely broken.

**Absence of evidence is not evidence of collection, and the evidence has to outlive the process.**
The rule that decides both marks is "an entry in no outstanding packet has been collected", so a
device that has forgotten which packets are outstanding reads *every* message it ever sent as
collected. That record was in memory only, so every relaunch lit both marks on messages nobody had
touched, and the first sync then turned them off again — a mark going backwards, which is the one
direction it may never go. It is written down now, beside the log.

### The product is an iPhone app until TestFlight

**RULED 2026-09-13 by Griff.**

The design set claims three platforms and draws one. Every Mac and iPad decision in the app is
Claude's, taken against iPhone boards. So the claim changes rather than the app: the listing, the
site and the docs say iPhone.

The Mac window keeps working — it runs in three columns and its keychain behaves like iOS's — because
Griff uses it. It is not offered, described, or supported.

**What would change it:** somebody to draw the other two platforms for.

### The version says what a build can read, and the alpha says so out loud

**RULED 2026-09-12.** Alpha, breaking changes acceptable, nuke as the escape hatch — reconfirmed after recovery keys existed.

**2026-09-09, Griff's ruling.** `MARKETING_VERSION` is `0.x.y` for the whole alpha and `CURRENT_PROJECT_VERSION`
increases by one per upload for ever.

- **`0.x.0`** — new capability, **or any breaking change to what is on disk or on the wire**: a new
  `PayloadType`, a change to any `CanonicalBytes` layout, a `PersistedState` field an older build
  cannot tolerate, or a fold rule that re-decides existing logs. *A confirmation answers one
  invitation* would have been one of these.
- **`0.x.y`** — fixes and copy that leave the log readable by the build before.
- **`1.0.0`** — the first build for which a breaking change would be a migration rather than a wipe.
  Not before the operational list is done.

**Not `1.0` for the alpha.** The number is a claim about the data model, and `1.0` tells a tester it
is stable — which is the one thing this alpha explicitly does not promise. Breaking changes are
acceptable here and the version has to say so.

**The build number never resets.** Apple refuses a re-used build number for a marketing version, and
resetting per version is the ordinary way to be locked out of an upload at two in the morning. One
rule that never bites: increment by one per upload, never reset, ignore the marketing version.

**Every breaking release names the wipe in its own release notes**, in those words: *this build
cannot read data from 0.3.x — erase everything.* An alpha tester forgives a wipe they were warned
about and does not forgive one they were not.

{: .unbuilt }
> **A backup file is not built.** When it is, it carries its own format version, and a restore refuses
> a file it does not understand rather than half-reading it.

**Cost.** Two TestFlight groups to keep honest — one that takes every build, one that takes only
releases — and the discipline that a breaking change is a minor bump even when it feels like a fix.

### The source is published under the Mozilla Public License 2.0

`PROPOSED` by Claude, 2026-09-17, on Griff's "make a license" — a default, and easy to change until
the source is published.

[App Store §3](app-store.md#3-export-compliance) rests the export position on the source being
publicly available under a license that allows redistribution. Three families were weighed:

- **GPL or AGPL.** Keeps every fork open, and its terms are widely read as conflicting with the App
  Store's own, which is why other people could not ship a fork there. Griff could, as the author, but
  contributions would complicate that too.
- **Apache 2.0 or MIT.** Simplest, and a fork may close its changes.
- **MPL 2.0, chosen.** Copyleft by the file: anybody shipping a changed version of these files has to
  publish those files' changes, and anybody may build something larger around them under other terms.
  It is used by apps that ship on the App Store. For a messenger whose case is that its claims can be
  checked, a closed fork of the crypto and sync files carrying the same claims is the risk worth
  closing; the file-level scope is what keeps it compatible with store distribution.

`LICENSE` at the root is the license text as published by Mozilla, fetched 2026-09-17. No per-file
header is added — the license allows the notice to live in a `LICENSE` file, and this repository has
no comments. The license covers copyright; it grants no right to the name *Outpost*.

### Supporter before TestFlight: a free year, and a badge a member chooses to show

`RULED` — Griff, 2026-09-17:

- Everyone on TestFlight gets a year of Supporter free once the app is released.
- On TestFlight the You page carries a bar below the mark: white on the accent, an exclamation mark
  symbol on the left and an arrow on the right, *Become a Supporter* over *One Year Free for
  TestFlight users*. Tapping it grants the free year.
- A thank-you page follows, with a party popper that wiggles, saying what support pays for and that
  friends do not need to be Supporters to use what a Supporter has.
- A new Supporter is asked whether to show the badge: a small accent circle on the bottom-right of
  their picture holding the mailbox drawing in white.
- The price will be $12 a year or $1 a month, with no discounts.

`PROPOSED` by Claude, 2026-09-17 — defaults, not constraints:

- **The year starts the first time an App Store build opens**, not on the day of the claim, since a
  year counted from a beta day would be spent before there was anything to support. On TestFlight the
  year has no end yet.
- **The claim is kept in the member's preferences**, so it rides the sealed sibling feed to their
  other devices and to a new install on the same account, rather than living only in one install.
  If two devices both claim, the earlier claim stands. Whether the App Store build keeps a TestFlight
  build's data when it replaces it has not been measured; the sibling feed is the reason it should
  not matter.
- **A build knows it is on TestFlight from `AppTransaction`**: the sandbox environment is TestFlight,
  production is the App Store. If StoreKit cannot answer, the build treats itself as the App Store
  build and offers nothing. Debug builds do not ask; they offer the year unless launched with
  `--channel appstore`.
- **The badge travels as its own entry**, `supporterBadge`, into every room and Outpost the member is
  in, the way Do Not Disturb does, and again into a room they are later given a key for. Turning it
  off, or the year running out, writes an entry that takes it back. A blocked person's badge is not
  drawn.
- **Where it is drawn.** On any avatar 28pt or larger, never on an anonymous face, with a ring in the
  color of the surface under it. On the You row it takes the pencil's corner, and the pencil is not
  drawn while it is there — two marks in one corner is worse than either. **What that costs**, seen
  on the rig 2026-09-17: a member who turns the badge on loses the hint that their picture can be
  changed from that row. The function is not lost — the row is a link, and the page behind it draws
  the same picture at 64pt with its own pencil and a *Name* row, and **never draws the badge**, so
  the pencil there is never hidden. A member who declines the badge keeps the pencil where it was.
- **The App Store purchase is not built.** Nothing in a TestFlight build can reach it, so it waits
  for the release; see [Open questions](open-questions.md#not-built).

**What it costs.** A build older than this one draws a badge entry as a line it cannot read, because
an unknown payload type falls into the transcript. No such build has left the rig, but after
TestFlight a new payload type has that cost, and reusing a plumbing type is the way around it. A badge
is the member's own claim. The source is public and nothing but the
member's own devices keeps the record, so a modified build can show one without paying, and no other
member can tell. The badge says somebody chose to show it, and nothing more is claimed for it.
Detecting TestFlight through `AppTransaction` has not run on a TestFlight build yet.

### The Mac ships as its own app, and the iPhone app is not offered on Macs

`RULED` — Griff, 2026-09-19: "the iOS app is unticked, since we have the mac app." The native Mac app
is a second platform on the same App Store Connect record, so one purchase covers both; the
*iPhone and iPad Apps on Apple Silicon Macs* option is off, so a Mac gets the Mac app and never the
iPhone one. This replaces the 2026-09-13 ruling that the product was iPhone only.

`RULED` — Griff, the same day: "Yes, ipad." The iPad ships in the first version, with the wide layout
and the 13-inch screenshots. A Release build's Info.plist declares the device family `[1, 2]`, all four
iPad orientations and a launch screen, which is what App Store Connect checks for an iPad that
multitasks.

### A recovery key's header comes from the app's name, and every old name still opens one

`RULED` — Griff, 2026-09-19: use the branding variable for the header, and accept keys saved under
earlier names from a hard-coded list, with a note saying why.

`RecoveryKey.header` is the display name in capitals followed by *RECOVERY KEY*, so a key written today
says what the app is called today. `Branding.historicalDisplayNames` lists every name the app has
shipped under (today only one) and a key saved under any of them opens. A rename adds to that list
and never removes from it. `ARecoveryKeyTests` holds the header saved keys actually carry, written out
by hand, and fails if the name it came from is dropped.

**What it costs.** The old name stays written in `Branding.swift`, the one file the branding lint
exempts, for as long as anybody might hold a key saved under it.

### App icons are a white drawing on a color, in four drawings

`RULED` — Griff, 2026-09-17: add the antenna and mailbox drawings in every accent and in black and
white; drop the icons with the drawing stroked in an accent over white or black, because the white
drawing on a filled accent reads better.

`PROPOSED` by Claude, the same day: the Classic drawing (the mailbox on its stand) is offered in white
on the seven accents too, so all three drawings share the style Griff chose. Three drawings, each in
the seven accents plus a black drawing on white and a white one on near-black: twenty-seven
choices. The black-on-white Classic is the icon the app ships with, and a member who
has never chosen now sees it selected; before, the picker marked Cobalt Light, which the app was not
showing. The fill for each accent is the one the app uses behind white text, so the white drawing
reads at 4.6:1 on all seven. `Scripts/make-app-icons.py` draws them from `logo_svgs/`, and
`EveryAppIconShipsTests` fails if a choice, an icon set and the build's list of alternate icons stop
agreeing.

`RULED` — Griff, 2026-09-19: the mailbox is offered **filled and unfilled**, each in every accent with
the mailbox in white, and on white (the mailbox black) and on black (the mailbox white). The filled
drawing had only been used for the white Mailbox icon; it is its own drawing now, *Filled mailbox*,
and the white Mailbox is unfilled like the rest of its row. Four drawings, thirty-six choices.

**What it costs.** Anybody on a build that used one of the fourteen dropped icons keeps it on the
Home Screen until they choose again, and the picker shows the default selected meanwhile. Somebody who
chose the white Mailbox sees it unfilled after updating.
`AppIcon.appiconset` still carries Mac sizes from the earlier drawing; the Mac is not offered.

## Sync and the log

### Sync is pull-based; push is an accelerant

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A sync happens when the app comes to the front, while a conversation is open, and on pull-to-refresh.
Push only makes those happen sooner.

**Cost:** not realtime while the app is closed, for anybody who declines notifications.

**Why it is kept:** it makes declining notifications a coherent position rather than a broken app, and
no part of delivery depends on a permission a member may reasonably refuse. The app must never present
missing notification permission as an error.

### The share is a transport boundary, not a security one

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A member's outbox is shared with `publicPermission = .readWrite`, so its URL is a bearer token.
Payload encryption is doing the access control; a leaked URL yields ciphertext addressed to rotating
tags.

**What it no longer yields:** the ability to have a zone joined automatically. Offers of a peer's
mailbox are named by an HMAC under the pairwise secret and sealed to it, so a record only counts if it
sits at a name computed for a known peer and opens under that peer's secret.

**Cost, unmitigated:** anybody holding the URL can still write records into that zone and consume its
owner's storage.

### A round is as many packets as fit, and a packet that lands is never forgotten

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A packet used to be a round: every unsent entry, however many, in one record. CloudKit refuses a
record over a megabyte, and photos made that reachable — a hundred and seventy previews in one
round. A round is now batched under `SyncSession.packetByteBudget` (seven hundred kilobytes),
grants and credentials riding the first packet.

**What a partial round does.** A packet that fails after another has landed does not fail the
round: what landed is reported in `written`, the frontier advances only over those entries, the
outstanding-packet record gains only those packets, no bell rings, and the rest goes next round.
Throwing would have lost the record of the packets that did land — and the delivery-mark rule
"an entry in no outstanding packet has been collected" would then have read every message in
them as collected. The first packet failing still throws, because nothing was written.

**Cost:** several writes per round when a round is large, which is exactly the traffic the size
represents; and a round that stops short leaves its later messages unannounced until the next.

### A packet is acknowledged only when everything in it landed

**FACT** — a property of the platform or the protocol, not a choice anybody made.

An acknowledgment removes this recipient from a packet's outstanding list, and the mailbox deletes the
packet once nobody is left. Acknowledging a packet whose entries were refused therefore deletes the
only copy that was still reachable: the sender's frontier already records those entries as sent, so
nothing ever offers them again.

Refusal on arrival is nearly always transient — a certificate or an introduction that has not landed
yet — so the packet is left outstanding and the next round tries again.

**Cost:** a packet that can never integrate stays in the sender's outbox, and its delivery mark stays
honestly uncollected. That is the safe direction to fail in; the other one loses the message silently
on both ends.

### A photo travels beside the packet, keyed by the entry, and lives as long as it is in flight

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A photo is an entry like any other — payload type 16, sealed under the room's epoch key, hash-linked,
forwarded — and its bytes are not in it. The entry names an attachment: an identifier, a fresh
content key, a SHA-256 of the ciphertext, a pixel size and a forty-pixel preview. The bytes are
sealed under that key and uploaded as a `CKAsset` on their own record in the sender's outbox,
addressed to the room's rewrap targets by the same rotating tags a packet uses, acknowledged the
same way, and **deleted once the last recipient has collected** — the mailbox's own rule, applied to the thing
that actually costs storage.

**What this buys.** The packet stays under CloudKit's megabyte; a photo is opened by exactly the
people who can open the message, because the key is inside the sealed entry; a device can verify
what it fetched without holding any room key, so bytes can be kept before the key arrives; and the
transport learns a size and nothing else. The bytes are kept sealed on the device too, so the one
thing on disk readable without the Keychain is still nothing.

**Cost, stated plainly.** A device that arrives after the last recipient collected — a new member,
a phone that was off for a month — finds the entry and not the bytes. The bubble says *"No longer
available — the sender's iCloud has let this photo go"* rather than spinning. That is the same cost
a packet already carries and has never been hidden; a photo is simply where a member notices it.
A sibling device is in the same position, for the same reason. History repair, built since, brings
back the entry and not the bytes.

**Upload first, entry second.** An entry naming bytes nobody can fetch is a bubble that never loads
on every other device, so the bytes go up before the log hears anything; a failed upload writes no
entry, drops the local copy, and tells the composer. The one thing that can be left behind — the
app dying between upload and append — is swept on the next launch, and never within an hour of the
upload, because a sibling's entry may still be in flight.

**What would change it:** a transport with its own lifetime for blobs, or history repair, at which
point "deleted on last collection" becomes "deleted after N days" and the late arrival gets the
bytes from a peer instead.

#### A clip is a minute, sealed whole, and plays from a file

A video is the same entry and the same attachment, re-encoded at 960 × 540 H.264 through Apple's
`forSharing()` metadata filter, with its first frame as the preview and its length in the entry.
Two limits follow from sealing the whole file in memory at once, which is what `SealedAttachment`
does: **a minute at most**, with a longer clip offered the system trimmer first, and **forty megabytes** at
the sealing ceiling. Chunked sealing is what would
lift both.

**The one place a member's content sits readable without the Keychain.** `AVPlayer` reads files,
so a clip is opened into the app's temporary directory under complete file protection when it is
first drawn, and stays there for the launch; the directory is emptied on the next one. A resource
loader that decrypts on demand would remove this and is not built. Said here rather than hidden.

**Screened as a file, and not drawn until the verdict is in.** The system's video analysis reads
the whole clip — seconds for a minute — and the bubble shows the placeholder until it has answered,
because a clip must not start playing before anybody has looked at it.

### The rendezvous heals itself

**FACT** — a property of the platform or the protocol, not a choice anybody made.

Two members reach each other through one record each: an offer of their own outbox share, sealed to
the pairwise secret and left in the other member's zone. The offer used to be written only where
none stood, on the reasoning that a rewrite every round was the write loop that once flooded
subscriptions. That reasoning was half right and the half it missed cost a day: a share that is
erased and re-created, or that CloudKit retires, leaves the old URL standing in every peer's zone
forever, and every peer fails to accept it with "Stale short token" once a minute, indefinitely.

So the offer carries a keyed digest of the URL (`PairwiseSecret.shareOfferDigest`), and:

- the **writer** leaves a standing offer alone when its digest matches and writes over it when it
  does not — a rewrite of this record type reaches no subscription, because the inbox one is scoped
  to packets and the bell to bells;
- the **reader** retracts an offer whose URL the server rejects as an unknown item, so the writer's
  "absent → write" leaves a current one next round;
- the write reports what it did in numbers — written, standing, unplaced, failed — and a failed
  save is a failure, not a write.

What it costs: one small keyed hash per offer per round, and one deletion in the rare case CloudKit
retires a share. What would change it: a transport whose share URLs cannot go stale, or a directory
that learns a peer's zone from something other than their packets — today a member whose zone this
device has not seen writes no offer at all, and says so as "unplaced".

Seen on the rig on 2026-09-04: beta read one zone all day; with the digest, alpha rewrote its
offer on the first round, beta accepted it on the next, read two zones, and twenty-four packets
arrived — among them a reaction sent five hours earlier. Exercised on purpose on 2026-09-05 with
the debug row *Rotate mailbox share*: retraction, fresh offer, acceptance and a message each way,
in about ninety seconds. The rig doc has the procedure.

### A repair rides the packet and asks for exactly what is missing

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A device names the history it lacks — every position below a feed's highest held or claimed number
that nothing occupies, its heads, and the room — and asks a peer for that. The request and the
answer travel in the sealed packet body beside the entries, never as log entries; the entries that
answer are ordinary entries; the answer says what the peer does not hold and its own heads. Repair
packets go to one peer, after the round's frontier and delivery marks are settled, and touch
neither.

**What this buys.** A hole is a specific thing the app fixes rather than a whole log re-sent on a
hunch; *Resend everything* is gone. A member who joins late asks the inviter for the room on
arrival, which is the first time a third member has been handed the room at all.

**What it costs.** Finding the holes is one pass over the log in memory per check. A peer that never
opens the app never answers, and the line says *waiting* for as long as that is true. A request to
a peer who holds nothing of what was asked is a round trip that ends in *nobody asked has them*.

**What would change it:** a cached gap index if the pass ever shows in a profile; a repair that
asks peers on its own when a hole appears, which is a product question about how much traffic a
quiet room should make.

### A grant carries every link the granter holds

**FACT** — a property of the platform or the protocol, not a choice anybody made.

The design said one link would do because the rest are published in the log, and they are — inside
`epochChange` entries each sealed under the epoch *before* the one it announces, so every existing
member can read it. That is exactly the epoch a joiner two steps back does not have. A grant now
carries all of the granter's links; links are opaque without the newer secret, so nothing is
revealed and a grant grows by a few hundred bytes per membership change.

**What it costs.** Nothing that shows: a grant is issued once per epoch per recipient. A build that
predates this decodes a grant without the field as before, and sends grants that a joiner two
epochs back still cannot use — the walk stalls where it always did until the inviter updates.

**What would change it:** sealing each `epochChange` under the epoch it announces instead, which
would let the log carry the walk on its own and is a format change for every existing room.

### A packet carries the keys its certificates name

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A sync packet passes on every device certificate this member holds, so somebody who has met Alice
can vouch for her devices to somebody who has not. It now passes on the identity keys those
certificates name, and a receiving replica introduces them before admitting anything.

**Why it had to.** A replica refuses a certificate for a participant it has never been introduced
to, so vouching for Alice's devices to a member who has never met Alice achieved nothing: the
certificate was refused as `unknownParticipant`, and every entry behind it with it. A member who
joined a room on somebody else's invitation could therefore never verify the founder — they saw a
room with one other person in it and no name, for ever, because the room's founding was written in
a feed they could not check. Two Apple Accounts cannot show this: with two, the inviter is always
the founder.

**Why it is safe.** A `ParticipantID` is a SHA-256 of the two public keys it names. A peer that
hands over the wrong key for Alice hands over a key whose id is not Alice's, and every entry names
its author by id — so a forged introduction introduces a stranger nobody's history refers to,
rather than impersonating anyone. Nothing else about verification changes: an entry still needs its
device's certificate and a valid signature.

**What it costs.** Two 32-byte keys per member this device has met, on the first packet of a round.
A member who has met a hundred people carries about six kilobytes; the packet budget is seven
hundred.

**What it does not do: widen who this device writes to.** Being able to check somebody's signature
is not a relationship with them, and for a while it was treated as one. `peers()` was
`knownParticipants`, a set that used to grow only through this member's own acts — an invitation, an
attestation, a room folded from the log — and introductions made it the transitive closure of the
social graph: Alice knows Bob, Bob knows Carol, and Alice addressed Carol. Every packet Alice wrote
carried Carol's tag, and every round of Alice's read Carol's outbox. `AppSession.addressable()`
narrows it back to rooms this device folds, walls either way, and questions outstanding in both
directions — the last of which is what carries a joiner from accepting an invitation to holding the
room, before any roster exists to name the inviter.

**What is still true, and is the design rather than a defect.** Verification is independent of
origin, so a peer forwards whatever is above its own frontier to everybody it addresses — Bob's
packets carry Alice's room-R entries to Carol whether or not Carol is in room R. Those entries are
sealed and Carol cannot read a word of them, but an `Entry` keeps its room, author, device, sequence
number, wall time and clock *outside* the seal, so a friend of a friend can see that a room exists
and how much is being said in it. What the introduction changed is that Carol now *stores and
forwards* those entries rather than refusing them as unverifiable. Narrowing this further means
forwarding per recipient, and the sent frontier is deliberately one high-water mark per feed for
every peer, so it is a change to that model rather than a filter. It is noted in the inbox rather than
done here.

**What would change it:** a transport where a packet is addressed to one recipient with no
forwarding, at which point vouching stops being how anybody meets anybody.

### One question about attachments was answering two

`PROPOSED` — Claude, 2026-09-13, diagnosed from the CloudKit integration target on its first day.

`CloudKitMailbox.pendingAttachments()` filtered out every record less than an hour old. Two callers
wanted opposite things from it:

- **`sweepAttachments`** deletes uploads no entry names. The hour is *right* here: it is the grace
  period that stops the sweep racing an upload whose entry has not been integrated yet.
- **`offerOutpostMedia`** asks who still owes an attachment, then re-uploads it to a new reader as
  `recipients: (waiting[id] ?? []).union(tags)` with `savePolicy: .allKeys`.

So letting a reader into an Outpost within an hour of posting a photo read `waiting[id]` as empty,
overwrote the outstanding list with **only the new reader**, and silently dropped everybody who had
not collected it yet. They never got the photo and nothing reported anything. The window is the
common case: post a picture, add a reader in the same sitting.

`pendingAttachments()` now answers "who still owes this" with no age filter, and
`sweepableAttachments()` answers "old enough to consider orphaned" and keeps the hour.

**Why no test caught it.** `InMemoryMailbox.pendingAttachments()` returns every outstanding
recipient with no age filter at all — the fake was *easier* than the real thing, which this
repository already knows costs more than no test. The live target caught it on the day it existed,
and the assertion that catches it is mutation-proven: restoring the filter fails that test alone.

### The app syncs on a loop wherever you are, not only inside a conversation

`PROPOSED` — Claude, 2026-09-14, measured on the rig between two Apple Accounts.

The only recurring sync was `ActiveSyncLoop` in `ConversationView`, five seconds while a room is
open. Everywhere else the app synced once per appearance, on a push, or when the scene became
active. That was fine for somebody who already has rooms, and a dead end for the person being let
into their first one.

Measured: beta confirmed an invitation at 01:03, and its app then went **silent for four minutes**.
It had no room to open, so no loop ran; the rooms list's `.refreshable` cannot be pulled because the
empty state has nothing that scrolls; and neither the visible bell nor the silent inbox subscription
woke it. The reverse-channel offer that lets the inviter read the joiner's outbox is written *during
a sync*, so alpha could not see the join either. What broke the deadlock was backgrounding and
foregrounding the app by hand — which is not a step the product can ask for.

So the root view now runs the same loop at twenty seconds. A conversation keeps its five. While one
is open both tick, and `syncNow()`'s in-flight guard turns the overlap into one extra round rather than
two concurrent ones.

The cost is a CloudKit round every twenty seconds while the app is in the foreground, on every
screen. That is the price of not depending on a push that demonstrably does not always come, and the
rig is where it was demonstrated: a green suite said nothing about it, because no test drives a
`.task`.

### What comes out of a zone is put in the order it was written

`PROPOSED` — Claude, 2026-09-14, measured against a live account.

`CloudKitMailbox.everything(in:)` built its array by iterating
`CKFetchRecordZoneChangesOperation`'s `modificationResultsByID`, which is a `Dictionary`. Iterating
one is not an order. Measured by writing four packets and fetching them back with the sort removed:
**two runs in four came back out of order**, and the other two looked fine — which is exactly how this
would have been dismissed as a coincidence.

Nothing in the suite could see it, because `InMemoryMailbox` keeps an `order` array and replays
packets in the order they were written. The fake was easier than the real thing again, in the one
dimension nobody had thought to compare.

What rode on it: `SyncSession.integrate` accumulates almost everything a delivery carries — grants,
requests, answers, confirmations are appended — but `notifyWalls` is taken as a whole from each
packet, so the last one wins. A peer only re-sends that list when it *changes*, so an arbitrary order
could apply their older wish about their wall bell and leave it there indefinitely. A member turning
the bell off could watch it stay on.

`everything` now sorts by `modificationDate`, with the record name as the tiebreak so two writes in
the same millisecond still order the same way on every device. The cost is a sort per fetch, which is
nothing next to the round trip. `packetsComeBackInWriteOrder` is the guard and it runs against a real
account, because this is not a property a fake can have an opinion about.

### The record ceiling is the app's own, and CloudKit never asked for it

`FACT` — measured by Claude against a live account, 2026-09-14.

`MailboxRules.recordByteCeiling` was written down as though it were CloudKit's limit, and every test
about it was written against the in-memory mailbox. Asked directly, the server accepted **one, two,
four, eight and sixteen megabytes** in a single `Data` field without complaint. The 1,000,000 in that
constant was never the server's number.

So two things were wrong at once. The fake was *harder* than the real thing — the mirror image of
the usual failure, and the kind that makes a test fail for something that works. And the real mailbox
enforced nothing, so a packet the suite refused would have gone straight out in the field.

The ceiling stays, because a round that writes sixteen megabytes is a bad round whatever the server
allows: it holds that much in memory on a phone, it costs the recipient the same on the way back, and
a failure part-way retries all of it. But it is the app's rule now and the docs say so, and
`CloudKitMailbox.put` weighs the record before writing it, so both mailboxes refuse the same packet
with the same `MailboxError.recordTooLarge`.

What is **not** measured: where CloudKit actually stops. The probe walked to 16MB and was retired
rather than pushed further — the number is somewhere above that, and nothing in the app needs to know
where.

### A key handed over carries the way back, or it hands over nothing

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

A joiner is granted the room's **current** epoch. Everything said before they arrived — including the
`roomProfile` that gives the room its name — is sealed under older ones. What bridges the two is the
epoch *link*: epoch N's secret opens the link that yields N-1, and so on down to the beginning.

So a grant carries `chain.link(at: epoch)`, and without it the grant is worthless in a way that does
not look like a failure. The joiner is admitted, pushed, synced, holds a key, holds every entry
verified in their replica — and their rooms list is empty, because `summary(of:)` cannot find a name
for a room whose naming entry will not open.

**Links are rebuilt on launch, not persisted.** `restoreEpochs` reads secrets out of the Keychain;
links were in memory only, so after a relaunch a host's chain had every secret and no links, and
every grant it issued from then on carried `link: nil`. The device can open its own `epochChange`
entries with the secrets it just restored, so the links are derivable from the log it is already
holding — a second stored copy would be state that can disagree with the log.

**Cost:** one walk of each known room's entries at launch, on a device that already folds the whole
log at launch anyway.

**What would change it:** a log big enough that the walk is measurable. It is the same traversal
`unwindEpochs` already does when a grant arrives, so the answer would be to cache links beside the
secrets rather than to stop rebuilding them.

**Measured, 2026-09-03.** Two fresh accounts could not pair for an afternoon. The joiner's log said
`entriesDelivered=7 entriesReceived=0 alreadyHad=7 rooms=0` — every entry present and the room
absent — and then, once `adopt` was made to say so, `link absent`.

### Somebody who stays turns the key after somebody leaves

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Every other membership change has an obvious advancer — the inviter for a join, the remover for a
removal — and Build Decision D32 wants exactly one, or a single change mints several secrets all
claiming one epoch. A departure is the one change whose author must not answer it: `advanceEpoch`
generates the next secret and keeps it, so a leaver who turned the key would walk out holding the key
to everything said afterwards. Asking them to generate it and promise to forget it is a hope, not a
guarantee.

So it falls to `RoomRoster.keyTurner`: the founder if they are still in the room, otherwise the
lowest identity remaining. Arbitrary, and *identical on every device*, which is the property that
matters. Each device records which departures it has already answered, because an epoch says that the
key turned and never which membership change turned it.

**Cost:** liveness. If the member who has to turn it does not open the app for a week, the key does
not turn for a week. What protects the room meanwhile is that a departure takes the leaver out of
`rewrapTargets` immediately on every device that has folded it — nobody addresses them a packet, so
there is nothing for the old key to open. It is also one round slower than a removal even in the best
case: the round that *collects* a departure is the round that turns the key, and the grants for the
new epoch go out on the next one.

**What would change it:** a way for the leaver to mint a secret they demonstrably cannot keep. Absent
that, the alternative is not rotating at all, which is what leaving did before it did anything.

## Cryptography

### The crypto gets a brief, and no outside reviewer

`RULED` — Griff, 2026-09-14.

The ticket asked for a written brief, a review by somebody competent and unconnected, findings
recorded here, and the known limits stated before release. Griff's ruling: **the brief, and not the
reviewer.** His reasoning is that the source will be open, so anybody who wants to look can, and
problems surface by being read rather than by being commissioned.

**What was checked before he decided.** Every primitive is Apple's: ChaChaPoly, Curve25519, SHA256,
HKDF and `SymmetricKey`, counted across `CarpenterKit/Crypto`. Nothing is hand-rolled — no cipher, no
curve, no hash. That is the part a reviewer would have cleared fastest.

**What the brief therefore has to cover, because it is the part that is ours.** Twelve files compose
Apple's parts into a protocol Apple did not design: `EpochChain`, `EpochGrant`, `Pairwise`,
`DeviceCertificate`, `DeviceRegistry`, `CanonicalBytes`, `SealedPayload`, `SealedAttachment`,
`RecoveryKey`, `Identity`, `IdentityStore` and `ShortAuthenticationString`. Every crypto failure this
project has actually had was in that composition and none was in a primitive:

- The sibling feed carried every epoch secret the member held to CloudKit **in the clear for four
  weeks**. ChaChaPoly worked; nothing called it.
- Adding two optional fields to `SealedPayload` changed the associated data every existing payload
  was sealed against, and the canonical bytes every signature was taken over. Every entry on every
  device stopped opening and stopped verifying at once.
- `confirmations` keyed on the person rather than on the thing it answered, so a gate stayed open for
  anybody ever removed.

So the brief is not a formality. It is the document that would have made each of those visible, and
it is what a reader of the open source needs in order to find the next one.

**What it costs, stated plainly.** Nobody outside the project will have read this protocol before
members use it. Being open to inspection is not the same as having been inspected, and the app's copy
must not imply otherwise — no sentence may claim the design has been reviewed, audited or verified by
anyone. It may say what is true: the primitives are Apple's, the composition is ours, the source is
open, and the brief describes it.

**One premise did not hold at the time.** Griff also gave a pre-TestFlight vulnerability scan as a
reason, and there was none. There is now: `Scripts/scan-for-vulnerabilities.sh` checks dependencies,
runs the static analyzer and scans for secrets, and ran clean on 2026-09-15 (see
[Before TestFlight](pre-testflight.md#a-scan-for-known-vulnerabilities)).

### What the crypto brief found

`PROPOSED` — Claude, 2026-09-15, writing [the brief](crypto-brief.md) the ruling above asked for.
Recorded here because that ticket requires findings to be written down **including any accepted
rather than fixed**, with the reasoning.

**Nothing found contradicts the ruling.** Every primitive is Apple's, as was checked before Griff
decided: ChaChaPoly in six files, Curve25519 signing and agreement as **two independent seeds**
rather than one key reused for both, HKDF-SHA256 wherever a secret becomes a key, and twenty-four
distinct domain strings so no construction's bytes can be mistaken for another's. There is no
hand-rolled cipher, curve, hash, MAC or KDF, and no injectable randomness seam in the shipping path.

**One finding needed a ruling.** The six-character verification phrase was about 29.4 bits with **no
commitment step**, so one side of a man-in-the-middle could grind it offline in minutes. Griff ruled
on 2026-09-15 for **ten characters and a commitment**, both built the same day, with the modulo bias
beside it; see [the ruling above](#the-verification-phrase-gets-ten-characters-and-a-commitment).

**Three things are accepted rather than fixed, and here is the reasoning for each.**

- **No forward secrecy, deliberately.** Whoever holds a room's current epoch secret and its links
  holds the room's entire history. That is not an oversight: the app's promise is that history lives
  on the devices of the people who were there, and an app that makes that promise cannot also destroy
  the keys to it. The compensating property is real — post-compromise security holds, because each
  epoch's link is sealed under the *new* secret, so turning the key genuinely shuts an old holder out
  of everything said afterwards.
- **Non-repudiable, deliberately.** Every entry carries a device signature, and those entries sit on
  other people's phones, so anybody in a room can prove what somebody said in it. Signal provides
  deniability; this cannot, because the same signatures are what make a serverless merged log safe.
  Correct trade for this architecture, and **no copy may ever describe it as if it were not.**
- **The recovery key is plaintext.** Both private seeds, base64, no passphrase and no KDF — so the
  file *is* the identity, permanently. Accepted because the mitigations that matter are editorial and
  already in place: the file says so in its own first paragraph, and the screens say it too. Wrapping
  it under an optional passphrase is noted in the brief as an unaddressed cost rather than proposed
  here.

**Two small things.** `FeedKey.canonicalBytes` has no length prefixes and was safe only by the
convention that both IDs are 32 bytes; on 2026-09-15 that width became an invariant the initializers
enforce, without changing the bytes, because changing the canonical bytes of a live wire format is
what broke every signature once before. And `RandomSource` is a seam nothing in the shipping path
uses, parked in the [Inbox](inbox.md).

**What the brief does not cover, stated so its silence is not mistaken for a clean bill:** no formal
analysis, no side-channel work on the composition, no fuzzing of the membership state machine, no
post-quantum anything, and the three-party cryptographic cases still need a third Apple Account.

### The verification phrase gets ten characters and a commitment

`RULED` — Griff, 2026-09-15, answering the one finding in
[the crypto brief](crypto-brief.md#finding-the-phrase-can-be-ground-out-offline): **both, not either.**
His reasoning, in his words: "All cryptography is increasing the amount of effort it takes to crack;
here, we can increase the effort, and potentially disable the whole strategy/surface of exposure."

**His read of the problem was right and one part of his arithmetic was not.** He said the offline
grind is the problem rather than the bits, and that entropy increases are moot because it is "days at
most" either way. The first half is exactly right. The second half holds for ten characters and not
for twenty: each character multiplies the work by thirty, so six to ten multiplies it by **810,000**
and ten to twenty multiplies it by a further 5.9 × 10¹⁴. Twenty characters (2⁹⁸) is past brute force
permanently — but twenty characters read aloud get misread, and a check people perform badly is worse
than a short one they perform. Ten and a commitment is the right pair, which is what he chose.

**What ten buys, and why it is not marginal.** A sixteen-core desktop ground the old six
characters in about **seven minutes** and one GPU in about **one minute**; at ten characters a
hundred rented GPUs need about **seven days**. The binding constraint is not money, it is the social
window — two people are standing there waiting to read the phrase to each other. A one-minute grind
fits in a pause. A seven-day grind does not fit in an invitation.

**What the commitment had to do.** The joiner published their code and the inviter signed last, which
is the order that lets the last party grind: the attacker can vary the room UUID, the timestamps,
their own keypair **and the Ed25519 signature itself** (RFC 8032 verification does not require a
deterministic nonce), so there is unlimited free grinding material. The grinding party has to be
committed before it sees what it must match. This entry first concluded that meant the inviter
speaking first. **What was built does not change the order**: the joiner's code carries a commitment
to a fresh nonce, the inviter signs over it, and the phrase depends on the nonce revealed afterwards,
so signing last buys the inviter nothing. See
[the crypto brief](crypto-brief.md#what-was-built).

**Two findings fall out of designing it, both recorded here rather than done quietly.**

- **The signature does not belong in the transcript.** The phrase derives over
  `signingPayload + signature`. Two valid signatures over one payload mean the same thing — the
  signature is verified separately — so including it attests nothing extra and hands the attacker
  unlimited post-hoc freedom. Removing it is a strict improvement and is required for the commitment
  to bind.
- **A pairwise fingerprint must never be the phrase.** Deriving from the pair's shared secret rather
  than the invitation looks like it removes the grinding surface and does the opposite: both sides
  become computable offline from public keys, turning a preimage search into a **birthday** search —
  about 24 million operations at ten characters. Recorded so nobody reaches for the obvious fix.

**Done immediately, on his instruction: the modulo bias.** `Int(byte) % 30` over a 256-value byte
made sixteen symbols 12.5% likelier than the other fourteen. Fixed by **rejection** at 240 rather
than by swapping to a 32-symbol alphabet, because the thirty symbols exclude I, L, O and U and this
phrase is read aloud. Worth well under half a bit, and never what made the grind work — his read that
"it does nothing good and is a mistake" is right on both counts.

**On rate-limiting a failed check.** Griff proposed closing an invitation after too many failures.
The instinct is right and the mechanism is simpler than he expected, because **the phrase is never
typed** — it is displayed on both screens and compared by eye, so there is no guessing loop to rate
limit. What matters is the other half of what he said: a mismatch **closes the invitation** rather
than offering a retry, because with a commitment the attacker gets exactly one shot per invitation
and a retry hands them more. His copy needed one correction, and has it: by the time a check fails,
the joiner's **public identity keys** have already reached whoever was in the middle, so "no
information has been accessed" would overstate it. The refusal screen says nothing was joined and
nothing was shared.

### Identity stays in the envelope, and the seal is the wrong place for it

**FACT** — a property of the platform or the protocol, not a choice anybody made.

**Decided 2026-09-07**, after a study of three designs, each read adversarially against the source.
An entry's author and device stay outside the seal. What was removed instead is the *content* a
stranger was being handed.

**Moving the author inside the seal achieves nothing, and the reason is one sentence.** The reader
being hidden from is somebody the wall's owner let in. Holding that wall's epoch key is what being
let in *means*. Anything sealed under it is handed to exactly the person it was meant to be kept
from. The question is not "inside or outside the seal" — it is "in the entry at all, or delivered
per recipient".

**Taking it out of the entry is a re-architecture, not a field move.** Three things block it, and
each was checked in the source rather than assumed:

- **The clock is the whole social graph, in the clear, on every entry.** `AppSession.append` stamps
  `clock: replica.frontier`, and `Replica.frontier` is every feed this device holds — every room,
  every wall, including feeds it only forwards. `FeedKey.canonicalBytes` is literally
  `author.rawValue + device.rawValue`. So a pseudonymous entry carries its writer's real feed key
  inside its own signed clock, and the writer's *next real* entry carries the pseudonym's. Both
  directions, silently, with everything working. Fixing it means partitioning the frontier per
  scope, which means partitioning feeds per scope, which breaks the single `head` that makes a
  device's whole history one hash chain across every room.
- **Blocking and the deny list key on `entry.author`**, and both work on entries this device cannot
  decrypt. A pseudonym bypasses both silently — a confirmed abuser in the shipped deny list would be
  drawn by every device. That is a trust-and-safety regression traded for a privacy property.
- **`FeedKey` has synthesised `Codable` inside `VectorClock`.** Changing its shape changes the JSON
  of every entry ever written and every packet from an un-updated peer, and `FileLogStore.loadAll`
  stops at the first record it cannot decode. The designs that promised no migration would have
  delivered a total silent loss.

**What was done instead.** A stranger reading the same wall as you was not merely holding your
32-byte key: they were holding **your display name, your photo and your Do Not Disturb message**,
because three announcement paths walked `chains.keys` and a wall you were let into is one of those
keys. That is content, it is worse than an identifier, and it needed no format change to stop. See
"Stop announcing yourself onto other people's Outposts", 2026-09-07.

**What a co-reader still holds**, stated exactly: the writer's `ParticipantID` and `DeviceID`, the
vector clock naming every feed their device had seen, `seq`, `previous`, `wallTime`, the signature,
and the ciphertext length. Two comments by one stranger still carry one key and always will under
this decision.

**What would change it.** All three of: a per-scope vector clock and per-scope feeds; an answer for
blocking and the deny list that does not depend on a stable author; and a third Apple Account,
because the triangle cannot be observed on a two-account rig.

## Rooms, invitations and verification

### Room membership is monotonic

**RULED 2026-09-12.**

Somebody admitted under an open room stays in when the founder tightens the setting. Membership
accumulates as the log folds rather than being recomputed from the current setting.

**Cost:** you cannot retroactively tighten who is in a room, only stop new people joining.

**Why:** a room that quietly drops members when a setting changes is worse than one that has to ask
again.

### An invite travels as a link, and the link changes nothing about the invite

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Both halves of the introduction — the joiner's identity key, and the attestation that comes back — are carried in a
URL the app registers a scheme for. The bytes inside are exactly what the pasted code carried: an
attestation still names the joiner's own keys, still expires, and is still checked by every member
before anybody rewraps a key. **A link that anybody can forward admits nobody it does not name**, so
there is no new trust in it.

What it removes is the part that was only ever friction. Tapping opens the app on the screen the code
was for — the phrase check for an invite, "which room" for a code — instead of asking somebody to find
a four-hundred-character blob in a share sheet and paste it into the right field.

A link that arrives on a device with no identity **waits**. That is the ordinary case rather than the
edge one: the person being invited is by definition new. Onboarding asks for a name, and the
invitation opens itself as soon as there is somebody to address it to.

**Cost:** a custom scheme is not a universal link, so it does not survive a device with the app not
installed, and some apps do not linkify one in plain text. A universal link needs a domain, an
`apple-app-site-association` file and a verified association, none of which exist yet.

**What would change it:** shipping that file on the marketing domain. `InviteLink` takes the scheme as
a parameter and parses both spellings, so the change is additive.

### A room announces what happened to it, in its own transcript

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Somebody added, somebody let in or refused, a rename, a change to who gets in: each is drawn as a
centered line in the transcript, in the same treatment as the day heading.

Every one is folded from a signed entry that was already in the log, so a notice cannot claim a
membership change that did not happen, and two devices holding the same log draw the same lines in
the same places.

`PayloadType.plumbing` is still the right list for what never appears as a *message*; it was being
read as "never show the member", which is a different claim. Receipts, policies and epoch changes
stay hidden — those really are machinery.

Leaving is one of them, as of 2026-09-02: **"Beta left this room"**, with nobody named beside them.

### Leaving and being removed are two acts, and never one with a flag

**RULED 2026-09-12.**

Two payload types, two maps on the roster, two notices, two error cases. A departure names nobody
because there is nobody to name; a removal names the remover because board 26 makes that one of the
three facts it has to state.

The reference point is iMessage, which shows a removed person **"You have left this conversation"** —
the same sentence it shows somebody who actually left. That is a false statement to a member, and
this app will not make it. The mirror is just as false: announcing that somebody was removed when
they walked out invents a remover who did nothing.

The one place the distinction is deliberately dropped is `Projection.absenceWindows`, which decides
whether to draw what somebody wrote while they were not here. The answer is no, either way, so that
code asks only "were they out", and its type is named for the question rather than for one of the
answers.

**Cost:** every screen and every fold that cares about somebody being out of a room has to handle two
cases rather than one, forever. `RoomRoster.absent` exists for the callers that genuinely do not
care, and it is deliberately the exception.

**What would change it:** nothing short of deciding the two are the same thing to a member, which is
the claim the epic exists to refuse.

### An invitation is an offer, not an admission

**RULED 2026-09-12.**

**2026-09-08.** Nobody is in a room until the joiner has confirmed the verification phrase **and**
the room's `RoomAccess` rule is satisfied. Two gates, in that order. A refusal at either one is
visible on both devices.

**Why.** Measured on two accounts: the joiner tapped *They do not match* and was in the room, on
both devices. Creating an invitation writes the joiner into the roster, so an invitation both offers
a room and puts somebody in it, and the phrase check gates only whether the joiner calls `accept`.
The one control against a person in the middle defeated nothing.

**The joiner confirms first**, before the room is asked, so that a room is not asked to vote on
somebody about to discover they are being spoofed — and so that a room's name, members and history
are never shown on the strength of an invitation that has not been accepted.

**What it costs.** Built 2026-09-08 and proved on two accounts on 2026-09-09. **One** new payload type,
not two: a refusal deliberately does not travel (below), so the only thing on the wire is the joiner's
confirmation, `PayloadType.joinConfirmed`. An invitation stops writing to the roster, which is the
half most likely to break something that works.

**And a join is now a round trip, which is not free.** The joiner holds no epoch key for the room
they are being let into, so their confirmation cannot go into it. It travels **in the packet, beside
the epoch grants**, and the inviter relays it in as an entry of their own — the same relay an
invitation takes (Build Decision D28). That is two sync rounds where there used to be none, and
there is no shortcut: the confirmation has to reach somebody who can put it in the room.

**In the packet rather than on the joiner's own feed, and that was not the first answer.** Writing
it as an entry on their own wall works and is wrong: it would be that member's *first entry ever*,
written before they have any peer but the inviter — and every member who joined afterwards would
claim that sequence number from a vector clock and never be offered the entry itself. Every join
left a permanent-looking hole in every other member's history, healed only by a repair an hour
later. Measured at four members in `MembersOverTimeTests`. A confirmation is a credential, not
history, and it belongs where the grants are.

Three more consequences fell out of it, each of which broke everything until it was written down:

- **The inviter learns the joiner's keys from the invitation, not from the membership.** An entry
  whose author is unknown is refused before its device is looked at, so an inviter who waited for
  somebody to become a room-mate could never open the confirmation that would make them one.
- **The key turns when the confirmation lands**, not when the invitation is made. A membership change turns the key
  on a membership change, and the membership change moved.
- **An invitation the joiner has confirmed keeps its inviter addressable.** Addressing is narrow and
  built from rooms this device folds, of which a waiting joiner has none. Under `unanimous` the wait
  can be days; the quiet repair that used to cover the gap is dropped as soon as it is answered.

**What `open` means now.** *An invitation is enough* — for the room. The joiner still decides whether
the invitation is real, and their confirmation is the only gate. Before this rule, that setting had
no check at all.

**A refusal does not travel.** Decided 2026-09-08 against the first draft, which had it reach the
inviter with a warning. A joiner gets a channel to an inviter only by accepting that inviter's
CloudKit share, so sending a refusal means first attaching to the mailbox of somebody just declared
possibly hostile — and, worse, **in the case the warning exists for, "the inviter" is the attacker**.
A spoofed invitation's refusal travels to the spoofer; the person being impersonated learns nothing
either way. The only thing it would achieve is telling an attacker their target is live and reading.

So the warning goes where the knowledge is: the joiner is told, on the screen where they refused,
and told to ring the person by voice. The inviter is told the one thing that is observable — the
invitation was **never accepted**. Weaker, and not a lie.

**Which makes the invitation's own controls load-bearing.** With nothing coming back, an invitation
the inviter cannot end is an invitation they cannot take back: they choose the expiry when they make
it, they can see what is outstanding, and they can purge one by hand at any time.

**It applies to history, and that is a cost rather than a detail.** Folding is where the rule lives,
so every open room already in existence is re-decided by it: those logs hold an invitation and no
confirmation, and everybody who joined one before this is no longer counted in it until they confirm.
Not a removal — nothing folds as one, nobody is told they were put out, standing to write is
untouched, and the same invitation still admits them. Measured in `JoinsFoldedBeforeTheRuleTests`.
Accepted because the app is in development; **reaching anybody with it needs a migration instead.**

**Nothing may remove from `acceptedInvitations`.** It is the joiner's only copy of the verification
phrase — the room keeps the inviter's in `requests` for ever, and there is no third place — so every
plausible reason to prune it is a reason to destroy the answer to the rig's own report, *"as the
invitee I couldn't find the verification code"*. Whether an invitation is still *outstanding* is
asked of the rosters this device holds now rather than recorded, and the costs are accepted: an
unbounded array, one attestation per invitation ever accepted, and a *waiting to be let in* row that
an indefinite invitation nobody ever honors never clears.

**That last cost widened on 2026-09-09, deliberately.** The row used to clear when the invitation
lapsed — the expiry was the only thing that ever ended it — and that is exactly what made a joiner
who confirmed in time watch their one view of that room disappear overnight with nothing said. So a
lapsed invitation now keeps its row and says the invitation ran out, and the cost is that the row is
permanent for every unanswered invitation rather than only for indefinite ones. **And what it may say
is capped**: this device cannot tell an offer that ran out from one the room refused, because a
refusal deliberately does not travel, so the sentence stops at the date passing and names the way
back. It never implies either reading.

**An invitation can be taken back, and taking it back reaches nobody.** `PayloadType.invitationRescinded`
= 22. Whoever holds the link still holds it and can still confirm; the room folds the withdrawal and
declines to admit on that invitation. That is the only shape available when the other device may be
offline or may be the party this exists to protect against, and it is the shape every membership
question here already has. It never evicts: somebody already in stays in, because membership is
monotonic and putting a member out is a removal that says so.

**And anybody in the room may take it back, not only whoever offered it.** *2026-09-09, replacing the
first answer.* It was the inviter's alone, on the reasoning that a wider rule would be "a removal with
none of a removal's honesty, and drawn as nothing at all". Both halves of that turned out to be about
the **drawing** rather than the permission: the transcript named the offer's inviter instead of the
entry's author — invisible only because the fold forced the two to be the same person — and the notice
itself had existed since the payload did. The attribution is fixed, the row and the sheet say whose
offer is being undone, and the fold asks for standing the way a removal does.

What is left is the permission, and the asymmetry ran backwards. The room's rule for putting somebody
out is already *anyone may remove anyone* (Board 26, 2026-09-01, on the grounds that in the default
room a founder is not a role that means anything — and neither is inviter). So any member could put
the joiner out one second after they landed, loudly and with a key turn, and none but the inviter
could stop them arriving — while under `open`, arriving hands them the epoch key and every message the
room has ever held, which removal takes back from nobody. An invitation is the first half of
membership, and this is the room's rule for the second half applied to the first.

It also frees an invitation nobody could reach. Removing or losing a member clears the offers made
*to* them and nothing clears the offers made *by* them, and a member who has left may not write to
the room — so an indefinite invitation from a departed member sat on the one screen whose job is
saying what the room is waiting on, for ever, with nobody able to clear it.

**Cost.** A quiet, cheap veto in every member's hands: `rescind` appends and returns, with no key turn
and no round trip, where removal is loud and expensive. A transcript line is not a notification, so a
member scrolling a busy room may never see it. And **the way back is not symmetrical** — `rescinded`
is keyed by the invitation's signature, so re-opening means a *fresh* invitation, which needs the
joiner's identity code, which in the shipped app only the original inviter holds. A hasty withdrawal
by a third party can strand a join only somebody else can rebuild. The sheet says so; that does not
make it untrue. **The symmetry is in the permission and not in the act**: a removal turns the key and
files a record the removed member's own device reads, and a withdrawal does neither, so nothing here
argues for adding an epoch advance — a merely-invited person was never addressed by `rewrapTargets`,
and minting a secret would put two on one epoch number for one membership change.

**What would change it.** A way for a joiner to reach an inviter without trusting them first. There
is none today and there may never be — attaching to the mailbox of somebody you have decided to talk
to is the architecture. See [Who you are talking to](verification.md).

### An invitation's lifetime bounds the offer up to the confirmation, and the room is not where it is asked

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-09.** The date on an invitation decides whether it can still be *taken*. Once the room has
folded the joiner's confirmation, the offer has been taken and the date stops mattering — what is
left is the room's own `RoomAccess` rule.

**The fold asks no expiry, and may not.** Three things follow from that and each is load-bearing:

- **A lapse has no entry, so it has no position.** A withdrawal can be asked about in the fold
  because it *is* an entry: `.invitationRescinded` carries `guard !established.contains(...)`, so
  one arriving after somebody is in folds to nothing and nobody is ever evicted. A lapse is a date
  inside a signature every device already holds; nothing is written when it passes. That guard
  cannot be written for it, and `isAdmitted` is what decides `established`, so asking there is
  circular.
- **There is no first admission to grandfather.** `Projection.roster(of:)` builds a fresh roster and
  refolds every entry on every `AppRootView` body pass and at the top of every sync round. Every
  fold is the first fold, so a rule added there is applied to all of history, every time.
- **And it would constrain nobody.** The only deterministic instant available is `entry.wallTime`,
  and a `.joinConfirmed` entry is authored by the inviter *relaying* it — the same identity that
  signed the expiry when it chose the lifetime. The gate would compare one party's clock against a
  lifetime that party chose: redundant against an honest inviter, whose device declined to relay it,
  and useless against a dishonest one, who writes the `wallTime`. A clock read there would be worse
  still: membership would differ between two devices holding one log, and flip mid-session.

So it is enforced at three writes, all on the device that is about to do something:

| Where | What it stops |
|---|---|
| `AppSession.inspect` / `accept` | The device holding the link redeeming or confirming a dead offer. |
| `AppSession.outstandingInvitations` | That device going on re-offering a confirmation nobody will take. |
| `AppSession.relayJoinConfirmations` | **The inviter writing a confirmation into the room that it collected after the date.** This is the one that was missing. |

**What it costs.** Built 2026-09-09. The gate at the inviter's relay has not been seen on two
accounts, because it needs an inviter offline past the date.

A confirmation signed while the offer stood and collected after it lapsed is refused, and that is a
real regression on the honest path. The default lifetime is a day and the joiner stops re-offering at
the expiry, so the packet is effectively one-shot: an inviter who does not sync between the
confirmation and the date loses the join, and the remedy is a fresh invitation. Nobody has measured
how often that happens — a join is two sync rounds, and the shortest option is a day, so it is
assumed ordinary rather than exotic rather than priced at zero.

**And the gate cannot tell an honest late delivery from a device that ignored its own expiry**, so it
refuses both. There is no joiner-signed instant anywhere: `JoinConfirmedBody` carries the invitation,
the joiner and a signature. The party whose word would settle it signs no time at all. The gate is
therefore *a courtesy honoured*, not a credential revoked, and no copy may imply otherwise — which is
why the inviter's row stopped saying an offer ran out "with nothing back". Something may well have
come back and been declined, and this device keeps no record of which.

**A taken-but-unapproved offer stays admissible indefinitely.** A confirmation folded in March can be
approved in September, for as long as the offer it answers is the one on the table. The remedy is to
take the invitation back, and that is why a confirmed offer stays in `pendingInvitations` even past
its date: that list is what draws the row the control hangs off. *Amended 2026-09-09 — this said
"nothing purges `confirmations`", which is no longer true and was never the whole story: a removal now
ends the offer it clears, and after a removal the remedy named here was unreachable anyway, because
withdrawing needs the attestation and the removal had already cleared it. See* **A confirmation
answers one invitation, not one person***.*

**The expiry is not a security property.** A member who wants that person in can simply invite them
again. What it enforces is an inviter's expressed intention, which is what the picker sells.

**What would change it.** A time signed by the joiner inside `JoinConfirmedBody`, which would let a
device tell a late *answer* from a late *delivery* and refuse only the first. That is a canonical-form
change to a body that is already signed, so it is not free — see the `CanonicalBytes.optional` trap.

### A confirmation answers one invitation, not one person

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-09.** `RoomRoster.confirmations` is keyed by the invitation's signature, so the first of the
two gates asks *has this joiner confirmed the offer the room holds for them now* rather than *has this
joiner ever confirmed anything here*. A removal or a departure additionally records the offer it ends
as **spent**, so it cannot be put back on the table.

**Why.** Keyed by the person, a confirmation outlived every membership, and the gate that
[An invitation is an offer, not an admission](#an-invitation-is-an-offer-not-an-admission) exists to
close was permanently open for anybody who had ever confirmed anything in that room. Four ways in,
all reproduced:

- removed, then re-invited — under `.open`, back in the moment the offer folds;
- left, then asked back — the same, through the other ending;
- confirmed under `.founder` and never approved, then a *second* offer supersedes the first — the
  next approval admits them on an answer to a different transcript;
- withdrawn, then re-invited — no removal involved at all.

Under `.open` the harm lands earlier than "a bare invitation folds": `attest` appends the offer as it
is created, so the removed person was back **on the inviter's own device before the code had been
handed to anybody**, and the next round addressed them the current epoch key.

**And the honest path was broken at the same time, invisibly.** `hasConfirmed` was person-keyed, so
after any of the four the inviter's device believed it had already relayed and refused to relay the
joiner's genuine confirmation of the new offer — and the epoch advance behind it never ran. The room
admitted without a check and discarded the real one when it arrived. `outstandingInvitations` made it
worse from the other side: it asked whether the device *holds the room*, which is a sound proxy for
membership only until somebody is removed, because a removed member keeps the whole log. Their device
signed the fresh confirmation and offered it to nobody. It asks membership now.

**Membership rather than the offer, and that is forced.** Removal advances the room's epoch, so the
fresh `.joinRequest` is sealed under a key the removed member does not hold: their device cannot see
the offer at all. What they can answer is whether the room counts them.

**Spent as well as forgotten, because the question can be re-asked.** The fold checks nothing about a
`.joinRequest` beyond the room it names, so any member could re-append the ended invitation's own
bytes — already in the log — and the removed member's device, which keeps every invitation it ever
accepted, would sign it again for the inviter to relay. One member, replaying bytes, undoing a removal
with nobody reading anything aloud. Recording the signature closes it in four places at once, because
`isOpen` is what `isAdmitted`, `verify`, the relay and the two invitation lists all ask.

**The room's own half, closed 2026-09-14.** `admissions` and `refusals` were keyed by the person too,
so under any setting but `.open` an approval given for one offer still counted for the next. An
`AdmissionBody` now names the invitation it answers, and both maps key on it, so a vote for a
superseded offer admits nobody to the live one. `MembershipTests` and `JoinIsARoundTripTests` hold it.

**What it costs.** Built 2026-09-09 and seen on two accounts. A fold rule applied to all history,
on the precedent this feature already set: every log is re-decided, and anybody admitted on a stale
confirmation is outside until they confirm the offer the room now holds. Nobody is evicted who joined
through a confirmation of the offer on the table, which is every ordinary join. And an invitation back
into a room somebody was put out of is re-offered every round until it lapses, with the inviter
discarding each one — the cost already accepted for an invitation nobody honors, extended one shape.

**What would change it.** Keying `requests` by signature too, so a person may hold two live offers at
once. Today the room holds one, and any member may decide which by appending it — see the inbox.

### A tag the app keeps is derived, never filed

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-08.** Griff's call: app-managed tags exist, they sit in the member's own filter rail, they
are **promoted to the front of it**, and they are **visually distinct but subtly so** — the same
capsule, drawn as a soft fill where a member's tag is drawn as an outline, and said out loud to a
screen reader because a fill is not something it can pass on.

**Derived on every draw and never written into `RoomsListOrganisation`.** What the first one reflects
— a join still in the air — is already derived from the log, and the log already travels between a
member's devices; filing it would be a second copy of a fact that can then disagree with the first.
Staying out of the filing is also what keeps it off the screens that rename, reorder, delete and
assign a tag, none of which it could honor and none of which now needs a guard.

**The cost is that `arrange` has to be told.** Membership in a member's tag is a question about the
filing; membership in the app's is a question about the rooms, so the one function that answers
"which rooms does this filter show" takes both. It is the only place that knows there are two kinds.

**One word for two opposite situations, deliberately.** A room this member invited somebody to and a
room this member is waiting to be let into are opposites — and the rows say which, in their own
words — but the question a *filter* answers is the same one: what is still in the air. Two chips for
that would be two chips to learn.

### A conversation with one person is a solo, founded as one

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

A solo is not a second kind of thing in the log. It is a room — one log, one roster, one chain of
keys — whose founding profile entry says `RoomKind.solo`. Every device that folds it reads the kind
from that first entry, lists it under Solos, and titles it by the person it is with, as that device
knows them: their shared name where names are shown, their code otherwise. The founder's stored name
is a fallback for the moment before anybody is invited.

Why the kind travels rather than being inferred: the headcount rule (`memberCount == 2`) hid rooms
the moment a second person joined, observed 2026-09-01. Intent is known at exactly one moment — when
the member picks a person — so it is written then and never guessed again.

What it costs: one optional field on the profile body, which older builds decode as absent and read
as a room; a solo has no name of its own, so it cannot be renamed; and a second person cannot be
added to one — the conversation's invite action is withheld for a solo, because a three-person solo
is a room that lies about itself. What would change it: a demand for solos that grow into rooms,
which would want a kind that can change and a rule for who may change it.

### A solo is verified, not admitted

**RULED 2026-09-12.**

**2026-09-08.** Solos are exempt from the above. There is one solo per person and nobody to approve
anybody, so the room's admission machinery does not fit. Instead: a member chooses in advance whether
a stranger's solo opens at all, and either side may ask to check who they are talking to at any time.

**A hold belongs to whoever asked for it.** The asker may freeze their own view of the conversation
while a check is outstanding; they may not freeze the other person's. The other side is *told* a
check was asked for, so the silence is explained. A hold that reached both ways would let anybody
freeze anybody's conversation by asking — a safety control that is also a griefing tool is neither.

**A refusal in a solo blocks it both ways** and deletes nothing already received, because the history
is the evidence. **Nor does it hide it.** The transcript stays on screen under the notice, and the
notice says so — *"it is what there is to look at"*. Somebody deciding whether to check again in
person or block the other person needs to read what they were sent, and covering it protects nobody,
because whoever sent it has already sent it. A `coversTheTranscript` written against the opposite
reading survived until 2026-09-09 as a property nothing read and a test that passed; both are gone.

**The way out of a refusal is a question raised afterwards and confirmed** — never the one that was
already in the air when the refusal landed, which settles that question and leaves the conversation
closed. That is what the fold does, and the screens now offer it: the refusal card carries the
standing question and the answer to it. Until that was wired, the way out existed only in the model
and a refusal was permanent on both devices. Costs: two people who both refuse must both, eventually,
ask and confirm; blocking is the other exit, offered on the same card.

### Verifying somebody later: a shared code, a note to yourself, and a line when they add a device

`RULED` — Griff, 2026-09-16, across three answers: compare a **shared code** made from both
people's keys; offer the comparison **once per person, the first time a conversation with them opens
after joining, skipped if you already compared**; and tell a member, with a date, when somebody they
talk to **adds a device**, since keys never change and a stolen account would show up that way.

**Why the fingerprint-change warning was dropped.** In this app a `ParticipantID` is the hash of the
keys, and nothing rotates them. Somebody who starts over without their recovery key is a new person,
who has to be invited again and compare again; somebody who restores with it is the same person, and
already produces the *sets up again* notice. There is no "same person, new key" event.

**What was built, and the parts Claude chose.**

- `PROPOSED` **The shared code is two halves**, one derived from each person's keys and hardened with
  4,096 rounds, ten characters each. A single short hash of both keys would fall to a birthday search
  by somebody choosing keys on both sides. The reasoning and the layout are in
  [the crypto brief](crypto-brief.md#the-code-two-people-compare-later).
- **Who is offered.** Everybody in the room you did not invite and were not invited by, whom you have
  not marked as matching, and who has not been offered before. The two people in an invitation
  compared its characters at the time. The offer waits for the room's greeting, because only one
  sheet shows at a time, and every person listed counts as offered the moment it appears.
- **The note to yourself.** *They match* records the date in the member's own preferences, which
  follow them to their devices and nobody else. The page then says when it was marked and whether
  that person has added a device since.
- **The device line.** A dated *Alex added a device* in every conversation with that person, for any
  device whose certificate is newer than the first thing this phone heard from them in that room — so
  the phone they joined with, and anything they already had, never shows. It is dated by the
  certificate, which their own device signed.

### Leaving a room is an action sheet, because the HIG says so

`RULED` — Griff, 2026-09-14, on the shape; the component follows from Apple's guidance.

Leaving was a single `.alert` with Leave and Cancel. Griff asked for the Outpost-access question to
be offered alongside it, defaulted off, so that leaving a room stops handing somebody access the
member meant to end.

**Read on the day, at
[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) and
[Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets):**
an alert holds "a title, optional informative text, and up to three buttons", plus a text field on
iOS — **there is no toggle in an iOS alert**. And the guidance names this exact case: "Use an action
sheet — not an alert — to offer choices related to an intentional action… Although an alert can also
help people confirm or cancel an action that has destructive consequences, it doesn't provide
additional choices related to the action."

Leaving is an intentional action with a related choice, so it is a confirmation dialog: *Leave and
Review Outpost Access*, *Leave*, *Cancel*. Three buttons inside Apple's limit of four including
Cancel, destructive styling at the top where the guidance puts it, Cancel at the bottom.

**What was dropped.** The review screen — a page listing every consequence before the confirm. Apple:
"Provide a message only if necessary. In general, the title — combined with the context of the
current action — provides enough information to help people understand their choices." So does the
step-of-how-many counter, which belonged to a flow that no longer exists.

**Note for the drawings.** The boards specified this as a multi-step flow. The boards predate Liquid
Glass and do not cite the HIG, so from 2026-09-14 the acceptance criteria say what the screen does in
words and cite Apple where a component is being chosen, rather than pointing at a drawing.

## Outposts

### A bell for a post is asked for by the reader, and the asking travels

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Asking to be told when somebody posts to their Outpost is a switch on the reader's device, and the
list of walls a member wants bells from is restated to those members in the packet the two of them
already exchange. It is never an entry.

**Why it has to travel.** A bell is a record the *sender* writes into the *recipient's* mailbox —
that is the only visible push channel there is, and it is what makes a message ring. A post is not
addressed to anybody, so nothing about it says who to ring. The poster has to be told, and the only
person who knows is the reader.

**Why not ring every reader and filter on arrival.** The extension cannot cancel a notification it
has been woken for; it can only change the words. So a reader who never asked would get a banner
about a wall they merely have access to, and the quietest thing the extension could put in it is
"New message". Filtering after the ring is not filtering.

**What it discloses, and to whom.** One person learns one thing: that somebody they already let in
would like to hear from them. That is what a follow is everywhere else. It goes only to that person,
sealed in the same packet as everything else, and to nobody else — not to the mailbox, not to other
readers of the same wall.

**Absent, not empty.** The list is sent when it changes rather than every round, because every
mailbox write can wake a peer's notification extension. So most packets say nothing about it, and
the field is absent rather than `[]` — an empty list is a member saying *I have stopped asking about
everybody*, which is a real thing to say and must stay distinguishable from silence. Getting this
wrong made every ordinary packet read as a withdrawal, and the switch appeared to work and rang
nothing.

**What it costs.** One extra packet on the round where the switch changes, and one on the first
round after a relaunch, because what was last sent is held in memory rather than on disk. A wasted
packet at launch is cheaper than a wish that silently never arrived.

**What would change it:** a push channel a device can subscribe to on somebody else's behalf, which
CloudKit does not offer.

### Access to a wall is a set of periods, and only one change is one-way

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

What somebody may read of a member's Outpost is a list of stretches with starts and ends, not a
single date. Three choices move between them: **from now on** opens a stretch, **stop** closes the
open one, and **everything** replaces every stretch with one covering the whole wall. From
*everything* the only remaining change is *stop*.

**Why it had to.** The key schedule has produced stretches since the day it shipped and nothing said
so. A grant hands over the links above its floor and none below, and a reader keeps every secret
they were ever given — so let somebody in, stop them, and let them back in, and what they can read
is two stretches with a sealed hole between them. Proved end to end in
`AccessWindowSessionTests`: the reader gets both stretches and neither the gap nor what came before.
The model carried one date, so every screen described the newest stretch and quietly dropped the
rest.

**Why *everything* cannot be undone.** It is not a permission, it is a delivery: the reader collects
the whole history onto their own device. Nothing this app can do reaches in and takes it back, and a
control that implied otherwise would be the one lie the product cannot afford. What a member can
still do is end the stretch, which stops what comes next — so that is the only change offered from
there, and the sheet says why.

**Why not a date in between.** An epoch covers everything said while it stood, so "from last
Tuesday" would really mean "from whenever this wall's key last changed". Three choices say what they
do; a date picker would not.

**What it costs.** A closed stretch whose grant never reached its reader is lost: the audience no
longer contains them, so nothing recomputes it. That is the same rule the rest of sync follows — a
key that was not collected may be gone — and it is stated rather than papered over.

**What would change it:** a way to un-send, which this architecture does not have and is not
getting.

### A wall is sealed to an allow-list, and where a reader came in is an epoch

**FACT** — a property of the platform or the protocol, not a choice anybody made.

An Outpost is a room whose membership is a list its owner keeps, entry by entry, on the wall
itself. Its key goes to the people on that list and nobody else — sharing a room grants nothing.
There are two offers: **everything**, which hands over the current epoch secret and every link that
walks back from it, and **from now**, which turns the wall's epoch first and hands over that epoch
with no links at all.

**Why not a date in between.** An epoch covers everything said while it stood, so "from last
Tuesday" would really mean "from whenever this wall's key last changed" — a promise the words do
not make. Two offers say what they do.

**Why the floor is remembered rather than recomputed.** Where the walk backwards stops is where a
reader's history stops, so the epoch they came in at is written into the entry that let them in.
Deriving it from the date instead would mean the next epoch change hands them the new key with no
links — silently taking back everything they could already read.

**What it costs.** An epoch change per dated grant and per revocation, which is one entry and one
rewrap to everybody still on the list. A reader let in later has to be handed the wall's history,
which the repair does by naming whose wall rather than which room. And revocation is forward-only:
what somebody collected is theirs, and no screen may imply otherwise.

**What would change it:** per-post keys, which would let an arbitrary date be honored exactly and
would cost a key per post to everybody who can read it.

### A comment belongs to the wall it lands on

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**Decided 2026-09-07.** A comment on somebody's post seals under *that person's* Outpost epoch, not
under the writer's own. Reactions to a post or a comment go the same way.

**What was wrong before.** A comment was an ordinary Outpost entry — `room: nil` — so it sealed under
the writer's own wall, and only the people *they* had let in could open it. Draw the triangle: Bob
lets Alice and Carol read his Outpost, Carol comments on a post of his, and Alice cannot read a word
of it. Neither can Bob, unless Carol had separately let him in. The thread under one post was legible
to a different set of people for every line in it, and to nobody at all for most of them.

**Why the wall is the right set.** A post's readers are exactly the people its author let in. That is
already the only membership the wall has, and it is the one every reader of the post shares. Sealing
the thread under the same epoch says it once, in the place that enforces it rather than the place
that draws it: whoever holds the key to the post holds the key to what is written underneath, and
nobody else does.

**What it costs.** Writing onto a wall needs the key for that wall, so `AppSession.appendToWall`
refuses when this device holds none — and, more carefully, never *creates* a chain for somebody
else's wall. Two devices each inventing a chain for the same room is a wall that splits in half.
Entries written before this change carry `room == nil`, and reacting to one still seals under its
writer's wall, which is the only place that entry ever was.

**What would change it.** A wall whose readers are segmented — several epochs alive at once for
different stretches — would make "the wall's epoch" ambiguous. It is not, today.

### Everybody you have not met is one person

**RULED 2026-09-12.**

**Decided 2026-09-07.** A `Member` this device cannot place — nobody in a room with this member, past
or present; nobody they let into their Outpost; nobody who let them into one; nobody they have given
a nickname — is drawn as a single shared figure. Not a numbered series. One.

**What it is for.** The decision above means Alice reads Carol's comment. That is the good outcome —
a thread with a hole in it is a conversation nobody can follow — and its price is that Alice now has
something from a person she was never introduced to. Hiding the comment removes the context that made
the post make sense, which is the failure people notice. Naming Carol hands Alice a person, which is
the failure people do not notice until it matters.

**Why one figure and not many.** "Stranger 1" and "Stranger 2" would let Alice count Bob's readers,
watch one of them across a year of threads, and eventually recognize them from what they say. One
figure carries the words and nothing else. It also makes the undoing free: the day two of them meet,
every comment already written simply resolves, because nothing was ever recorded about who the
stranger was. `AnonymousCommentTests` holds that.

**Where it is enforced.** `Projection.member(_:)` and `Projection.naming()` — every route a
`ParticipantID` takes to become a name on a screen. `Projection.met` is nil by default, which means
*not anonymising*: a projection built without it names everybody, which is what a room wants and what
every test that predates this got.

**What it does not claim.** An entry's author sits outside the seal, as its room, device, sequence and
wall time do. What is anonymized is the identity the app presents, and every route from a comment back
to a person — not the bytes. Somebody reading their own database can see that two comments came from
one key.

Precisely: after "Stop announcing yourself onto other people's Outposts" (2026-09-07) a co-reader who
has never met the writer holds the writer's `ParticipantID`, `DeviceID`, vector clock, sequence, wall
time and signature — the key and the routing. They no longer hold the writer's name, their photo, or
their Do Not Disturb message, all three of which they did hold before that change. See the note in
[Inbox](inbox.md) and "Identity stays in the envelope" below.

**What it costs.** Reactions were already only a count on a post's bar, so a stranger's reaction was
always a number. A reaction *list* — which only messages have — would have to collapse them, and
messages are between people who have met.

### A wall carries its own picture pointer, at the wall's own address

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-07.** The picture at the top of somebody's Outpost is announced as an ordinary
`memberPhoto` entry addressed to *their wall* — the address `setBlurb` already writes to — rather
than borrowing the pointer the rooms are told or taking a payload type of its own.

**Why it had to be somewhere.** `roomsToTell()` is roster-based and a wall has no roster, so no
photo pointer had ever reached a wall's readers. The bytes had: `addressable()` unions the wall's
audience, so a reader who was let in already held the sealed attachment and had nothing telling
them it existed. Their friend's Outpost drew a monogram however many photos that friend shared.

**Why the existing payload type.** A new `PayloadType` degrades badly on a build that predates it:
`isConversation` is a denylist, so an unknown type falls into the transcript and the Outposts feed
as "Not supported by this version." on the wall, once per change of picture. Raw 17 is already
classified as plumbing and is quietly ignored by anything that does not understand it.

**What it costs.** `Projection.photoReference(of:)` used to mean "their latest word on it
anywhere" and now means "their latest word in a room". A build that predates this and receives a
wall pointer draws the wall's picture in rooms as well. That is a mis-draw and not a disclosure —
the entry is sealed under the wall's epoch, so only a reader of that wall can open it, and drawing
it in a room shows it to somebody who is already a reader.

**The wall keeps its own attachment, even when it shows the same face the rooms do.** Pointing it
at the rooms' record would save an upload of a few tens of kilobytes and buy an ordering hazard:
changing the photo on You deletes the previous record, so the wall would have to be moved onto the
new one first, and a device collecting between the two finds a pointer standing over a record that
is gone — which draws nothing, reports nothing, and `unfetchablePhotos` never asks twice. It is
also what makes a wall work for somebody in no rooms at all, who has never had a rooms pointer to
borrow, and who is exactly the member this feature is for.

**What would change it.** A way for a reader to tell *withheld* from *lost* would make the
duplicate upload worth removing. Nothing else here is worth revisiting.

## People, names and faces

### Names and faces are shared by choice, both ways, and start off

**RULED 2026-09-12.** All four off on a bare install — *and* the onboarding preset decides: **Locked down** leaves all four off, **Familiar and open** turns all four on. The presets already do this; the entry previously described only the bare default and read as though the presets did not exist.

Four switches, all off on a fresh install: *Share my name*, *Share my photo*, *Show others' names*,
*Show others' photos*. Until a member turns the first on, their name stays on their device and every
room sees a short code; until they turn the third on, everybody else is a code and initials from it,
even people who shared a name. Griff's ruling, 2026-09-05.

What it costs: the first conversation between two strangers is between two codes, which is the
honest state and an unfriendly one; turning *Share my name* off takes nothing back from a room that
already holds the name, and the footer says so rather than implying a recall; and a photo, unlike a
name, does come back — see the entry below — which the footer says too. What softens it:
the privacy check-up, after the name, which asks once with examples rather than switches — two
presets and a walkthrough — so the default is a choice rather than a silence. Skipping it is a
choice too, and is not asked again; Privacy & Safety offers it whenever they like.

### A shared photo is a standing attachment, not a log entry

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

The bytes of a member's photo go up the way a message photo's do — sealed, as an attachment in the
member's own outbox — and what the log carries is a pointer: a `memberPhoto` entry per room naming
the attachment and its key, or naming nothing once the photo is taken down. Nobody acknowledges
the attachment, so the outbox keeps it for as long as the member leaves it there and a room joined
next month finds it the way it finds a name; the sweep counts the pointer as a reference. Replacing
the photo deletes the old attachment once the new pointer is written; taking it down withdraws the
pointer first and deletes second, so a device collecting between the two finds a withdrawal rather
than a pointer to nothing.

Why not the log: an entry is forever and hash-linked, and a photo is neither small nor something a
member should be unable to take back. Why not a message attachment as-is: those are in flight and
deleted on the last acknowledgment, and a photo is meant to stand.

What it costs: a pointer entry per room per change — a few bytes each, which is the history a photo
is owed; one record fetch per person per change on the collecting side; and a stale copy on a
device that has not collected since the takedown, which lets go on its next round. What would
change it: a transport with a standing record type of its own, which would drop the pointer.

### Silence is shared like a name: by choice, both ways, and the app never reads the room

**RULED 2026-09-12.** Kept. Griff also asked for **Notify anyway**, a way to break through a Focus. That
was answered from Apple's documentation on 2026-09-15: a messaging app's banners are communication
notifications, and the system decides by sender. See
[The app does not set an interruption level](#the-app-does-not-set-an-interruption-level-because-it-is-a-messaging-app).

Whether a member has notifications silenced is the system's answer, asked only after they turned
*Share when I've silenced notifications* on and allowed the question. It travels as an entry per
room per change — two small entries a day for a Focus that comes and goes — and is drawn only where
the other person turned *Show others' silence* on, as one line over the field in a solo. The app
does nothing else with it: no quieter haptics, no held messages, no "notify anyway". Delivery under
a Focus is the system's business already, and the app's job is to be a message from a person — a
communication banner with a face — and to offer a Focus filter, so the system has what it needs to
decide.

What it costs: the Communication Notifications capability and a usage string; an entry per change
in every room; and a simulator that cannot show any of it, so the rig has a debug row where the
system would be. What would change it: Focus's allowed-people matching reaching people who are not
in Contacts, at which point the banner's sender could carry a handle the system can match.

### What you call somebody is yours, and so is the face you give them

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

A nickname and a photo for another person are this member's own words about them: drawn everywhere
that person appears, over whatever they shared or did not, and sent to nobody — not to the person,
not to a room. The nickname rides the sibling feed, because a name given on the phone that the iPad
does not know is the one somebody notices; the photo stays on the device it was chosen on, because a
picture is too big to ride the feed and a face that is on one device and not another is a smaller
surprise than a feed that carries pictures.

What it costs: two answers to "who is this" that can disagree — the page shows both, as *What you
call them* and *Their name*, so neither is mistaken for the other; a nickname hides a shared name
that later changes, which the page also shows; and a photo picked on the phone is absent on the
Mac. What would change it: a sibling feed that can carry a small sealed attachment, at which point
the photo would follow the nickname.

### Which picture is drawn for somebody, in one place

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-07.** Four rungs, and the viewer is not one of them: the photo the reader chose for that
person, then the picture that person shows on their own Outpost, then the picture they share to
rooms, then their initials. On a wall the middle two swap. The viewer's own disc is recognized
rather than looked up.

The rule is `avatarSource`, a free function with a test over it, because the two-rung version it
replaced was an expression hand-copied into five views — and a rung added to one of them and not
the others compiles, draws a face, and quietly draws a different one from the screen beside it.

**What it costs.** One more environment value (`viewerID`) that every screen drawing a person now
depends on. **What would change it.** Nothing; if a fifth rung ever appears it goes here.

## Notifications and marks

### Exactly one push channel may be seen

**FACT** — a property of the platform or the protocol, not a choice anybody made.

A subscription's `recordType` scopes what fires it; its `NotificationInfo` decides whether it is
visible. Those two facts must agree, and they live in one table (`PushChannel`) rather than at three
call sites.

Only a `MessageBell` may produce a banner — a record a sender writes when it has put a real message in
the mailbox for that recipient. Acknowledgments, grants, certificates, renames and share offers
cannot ring.

**What this replaced:** an unscoped visible subscription on the shared database, which fired on every
write to every accepted zone. In a room of three, one message produced one banner plus one more for
each other member's acknowledgment of it.

### Notifications are sorted by what rings them, and the badge is told what to count

**RULED 2026-09-11 by Griff**, who specified the structure. The defaults inside it are Claude's and
are listed as a question in [Open questions](open-questions.md).

Notifications is a master switch over two pages, **Messaging** and **Outposts**, because the two are
different kinds of interruption and a member who wants one rarely wants both. Messaging covers
messages and room updates, each with its own level. Outposts covers new posts — all of them, only the
walls turned on, or none — then replies, comments and likes, each its own switch.

**The app icon's number has its own setting**, on both pages, saying whether it counts messages,
Outposts, both or neither, with a line under it spelling out in words what the number will then mean.
Apple's guidance is that a badge is a number or an exclamation point and is reserved for information
a member would want to be interrupted for; a number that silently mixes two kinds of thing is not
that.

**The app's own housekeeping never touches the icon.** A check-up, a history warning, an unsaved
recovery key: those appear inside the app, on the You tab, because the number on the icon means
somebody is trying to reach you.

**Cost:** five switches and two levels is more surface than one master toggle, and a member who never
opens the pages inherits five defaults nobody has tested on them.

**What would change it:** a member finding the two pages harder to reason about than one list. The
structure is Griff's; the defaults inside it are not, and those are the part to change first.

### A seen mark is the first receipt that covered it

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

A read receipt is a cursor — the furthest entry its author had read — so one receipt is evidence
about every position at or before it. A message's mark carries the *earliest* instant among the
receipts that reach at least that far, not the reader's latest.

**Why.** The old answer gave every message under a reader's cursor that cursor's timestamp, so a
message first seen at 12:02 read *seen 7:21 PM* the moment its reader went past something later.
True, and not the question a sender is asking.

**What falls out of writing it as a minimum over a suffix.** A device that fell behind and caught up
cannot walk a mark backwards, because its later receipt names an earlier position and is simply not
in the set for anything beyond. And evidence that arrives late can only make a mark *earlier* — the
honest direction, since the app reports the earliest moment it can prove.

**What it costs.** The instants are other people's clocks, compared with each other only to choose
which to draw. Nothing orders history by a clock; `CausalOrder` does that.

### A message is only pending when nobody has it

`RULED` — Griff, 2026-09-14.

A send that has not gone drew nothing at all: `.pending` is not `isVisible`, so the bubble carried no
mark and an empty VoiceOver label, and the one sentence explaining why — a full or signed-out iCloud
— was written to the rooms list, one screen back from where the member was standing.

The fix is not a failure color. There is no failure: `unsentEntries()` re-offers the entry every
round, for ever, and in a serverless app a message waiting for the other person to open theirs is
**ordinary**. Alarming about it would be the app lying in the other direction.

Griff's rules, which say when waiting stops being ordinary:

- **Pending means nobody has it.** If any recipient collected it, it sent; a single recipient who is
  behind is that recipient's problem, not this message's.
- **Two signals raise the mark.** More than one *newer* message has been delivered while this one has
  not — which is proof something is wrong rather than slow — or the member's chosen time has passed.
- **The mark is an orange information circle**, and it replaces the delivery marks on that message
  rather than sitting beside them. Tapping it says why it has not gone, or how long it has been
  trying.
- **The time is per room**, set in that room's settings: a day at the minimum, a week at the maximum,
  in whole days, and it can be turned off — off leaves only the newer-message-delivered signal, so
  the icon then appears only when something has actually gone wrong.
- **The explanation carries a quiet link** to that room's setting.

**What it costs.** A member who turns the timeout off and talks to somebody who has stopped opening
the app will never be told that nothing is arriving. That is the setting doing what it says.

### A room that has not chosen waits three days

`PROPOSED` — Claude, 2026-09-16, building the not-sent mark.

Griff ruled the range — one to seven whole days, or off — and not what a room uses before anybody
chooses. Three days is the middle of the range. The reasoning: in a serverless app a message waiting
for somebody who has not opened the app is ordinary, and a mark after one day would call that
ordinary thing out in any room with a weekend in it; a week is long enough that a message somebody
needed would be missed. The newer-messages signal does not wait for anything, so a genuine fault is
still shown as soon as there is proof.

**The setting lives on the room's sheet** — the one the conversation menu opens as *Notifications*,
where the room's read receipts already are — because that is the room's settings today. If rooms
get a settings screen of their own, it moves there.

**What it costs.** A message in a room nobody has set can sit for three days before anything is
said, unless newer messages prove it wrong sooner.

### The app does not set an interruption level, because it is a messaging app

`PROPOSED` — Claude, 2026-09-15, answering Griff's question about defining breakthrough as Time
Sensitive. **This closes the one open question that was marked "ask Apple before shipping it"**, and
it closes it out of Apple's own documentation rather than by asking.

Griff's proposal was to mark messages Time Sensitive after warning the sender that the level is only
for time-sensitive messages, mimicking iMessage. Apple's
[Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications),
read 2026-09-15, answers it three times over:

> If you support direct communications — like phone calls and messages — you use **communication
> notifications**; for all other types of tasks, you use noncommunication notifications.

> You need to specify a system-defined interruption level for each **noncommunication** notification
> you send … when a communication notification arrives, **the system uses the sender** to determine
> when to deliver the alert.

So interruption levels are not the lever for a messaging app's messages at all, and **this app is
already on the right path**: `NotificationService` donates an `INSendMessageIntent` with an `INPerson`
carrying the sender's name and picture and a `conversationIdentifier`, both Info.plists declare
`INSendMessageIntent`, and the only level it ever sets is `.passive` — a *downgrade*, for the quiet
ones.

**The warning Griff wanted already exists, and it is on the correct side of the conversation:**

> The first time a Time Sensitive notification arrives from your app, **the system describes how such
> a notification works and gives people a way to turn it off** if they don't agree that the
> information requires their immediate attention.

That is the *recipient's* device explaining it at the moment of the interruption, with an off switch.
An in-app sheet could not match it and would be asking the wrong person — the sender is not the one
being interrupted.

**What Griff remembered about iMessage is real, and it is already available with no code from us.**

> **People identify the contacts and apps that can break through a Focus** to deliver notification
> alerts.

It is a **recipient-side, persistent** allowance, chosen in Focus settings — not a per-round or
per-sender toggle. And it can be granted to an *app*, so somebody who wants this app through their
Focus can already have it, today.

**What remains, and it is smaller than the question.** Per-*person* breakthrough needs the sender to
be in Contacts, and this app has no contacts relationship — `contactIdentifier` is `nil` in the
intent, necessarily. So the honest options are (a) leave it, which is what the copy already says
happens, (b) tell people in the Notifications screen that they can allow this app in a Focus, which
is one sentence and true, or (c) offer to write a member into Contacts, which is a new permission for
a small gain. **(b) was proposed and is built**: the Notifications page says a Focus silences these
like anything else and that the app can be allowed in a Focus. (c) is not proposed, and Griff parked
it on 2026-09-15 ([After TestFlight](after-testflight.md#whether-a-member-can-be-written-into-contacts)).

### The notification extension writes nothing to the container it shares

`PROPOSED` by Claude, 2026-09-17 — a default, not a constraint.

Writing a test for the app and the extension together found the extension's read-only round saving
its own copy of the state file — loaded before the app's latest save — over the app's. A mute set
while a banner was being prepared was undone; a room deletion stopped being recorded. The lock made
each save whole and did nothing about which one won.

Two ways out: merge the extension's changes into the app's under the lock, or have the extension
write nothing. Nothing the extension learns is lost if it writes nothing, because a read-only round
acknowledges no packet and the app collects all of it again, so the second is chosen: the log, the
state file and the keychain are opened through read-only views. It still reloads from disk to find a
message the app wrote while it ran, but only after looking at what its own round collected, since the
reload discards that.

**What it costs.** Opening the app from a banner shows the message once the app's own round has
collected it, not from what the extension already held — a round the app runs as it comes forward.

### Reply and Mark as Read need the device unlocked and never open the app

`PROPOSED` — Claude, 2026-09-19, on Griff's "Do it".

Both actions carry `.authenticationRequired` and neither carries `.foreground`. A reply appends to
the log and seals under keys the app keeps in the keychain and in files that are unreadable while the
device is locked, so an action that ran locked would fail after the member had typed. A banner action
that opened the app would be the tap on the banner again, which the HIG warns against. Reply comes
first because a watch's double tap runs the first nondestructive action, and Messages makes the same
choice.

**What it costs.** From a locked device, the member unlocks before either action runs.

### An answer from a banner waits for the load and the round in flight, then runs its own round

`PROPOSED` — Claude, 2026-09-19, from two faults measured on the rig.

iOS suspends the app when the notification handler returns, so an answer's work has to finish
inside the handler. Two things got in the way, and both were measured on gamma the same day:

- **A cold background launch creates the window.** Its `.task` handlers register before its bring-up
  has loaded the session, so a reply reached `send` with no identity and was dropped. An answer now
  waits for `session.state` to leave `.loading`. Bring-up loads only a session nobody has loaded, and
  two loads in flight share one, so the answer's load and bring-up's load cannot race.
- **A round already running** made `syncNow()` flag "go again" and return. The handler returned with
  it, iOS suspended the app, and the reply waited for the next foreground. An answer now waits for
  that round, then runs one of its own.

Both waits are capped at 20 seconds so the handler returns before the system gives up on it.

**What it costs.** The handler can hold the app awake for a round and a half.

### A reply that could not be sent comes back as a notification, with its words

`PROPOSED` — Claude, 2026-09-19. **A deliberate departure from the HIG.**

The HIG says to show an error in an alert, not a notification. A reply from a banner has no window
to put an alert in: the member never opened the app, and the words exist nowhere else. So a failed
reply posts a notification in its room saying it was not sent, with the words unless the Focus
filter hides previews, and tapping it opens the conversation. The alternative, an alert the next time
the app opens, reaches the member after they have stopped expecting an answer, and it would have to
keep the words on disk to be any use.

**What it costs.** A notification that is an error message, which the HIG asks apps not to send.

## Safety

### Screening is on the device, is the member's to switch off, and is never claimed when it is off

**RULED 2026-09-12.** Switchable, deliberately.

Trust and safety decisions D1 and D2. Received photos go through Apple's `SensitiveContentAnalysis`
before they are drawn; a photo it flags is blurred with the reason on it until the member decides.
Nothing leaves the phone, nothing is scanned on any server, and there is no server. The switch
defaults to on and can be turned off — App Store Guideline 1.2 asks that a filter exist, not that it
be unbypassable.

**The framework answers only when the system's own Sensitive Content Warning is on**, and most
members will have it off. So there are three verdicts, not two: `clear`, `sensitive`, and
`notScreened`, and the third is drawn as an ordinary photo and *explained* in the Privacy & Safety footer —
"photos are not screened, and this app does not claim they were". Collapsing `notScreened` into
`clear` would be the app claiming a look it did not take, which the honesty rule forbids. This is acceptance
criterion 4 of the trust and safety design, and it has a test.

**Cost:** for most members the filter does nothing until they turn a system setting on, and the
App Review reply must not overstate coverage. The footer says exactly where the setting is.

### A report is words, and cannot be anything else

**RULED 2026-09-12, and the reasoning here was wrong.** Griff: the report goes to **abuse@outpostmessaging.com**, not to the member themselves. The reason is not tidiness, it is liability — "I don't want to be in the legal mire of holding potentially illegal things. Report and pass to the authority." Whoever handles it contacts the reporter using the contact details they supplied. The app must never hold illicit material, which is why `AbuseReport` has no field that could carry any.

Trust and safety decision D3. Reporting a message opens a mail the member sends themselves, to a
published address, carrying their description, the sender's fingerprint, the entry hash, the times
in UTC and the app version — and **no message content and no media**, because `AbuseReport` has no
field for either. That is a stronger guarantee than a rule: nothing decrypted leaves the device
except by the member's own hand, and nobody at the receiving end can be handed something they must
not hold. There is no background send and no new network destination.

The screen says what happens next and what does not: the report is acknowledged and acted on; the
member is not told the outcome, and the person reported is not told at all. Canada's Mandatory
Reporting Act forbids disclosing an escalation, and a promise to "let you know" would be a promise
to break it.

**Cost:** a report lands in a third-party mailbox, which is the open problem in
[trust-and-safety.md](trust-and-safety.md#where-report-records-live) and is an operational fix, not a code one.

### Blocking is local, immediate, silent, and reversible

**RULED 2026-09-12.**

Trust and safety decision D4. A block is a stamped flag in `MemberPreferences`: it follows the member
to their own devices on the sibling feed and reaches nobody else. Nothing is written into any room —
an entry would tell the blocked person — and nothing is erased: their entries are still held,
verified and forwarded, because the log is the same on every device and a hole fails everything
after. What changes is what this member's devices *draw*: nothing from that person in any room, no
unread dot for it, no banner from the extension, and no photo of theirs fetched.

The way back is under Privacy & Safety › Blocked people, and unblocking shows what was held.

**Since 2026-09-14 a block also stops the key handover**: a blocked person is handed no new room
keys, media or bells from this member. See
[Blocking stops the key handover](#blocking-stops-the-key-handover-and-stopping-it-is-the-whole-point).
It is still not the membership refusal `RoomRoster` records, which the room can see.

### The deny list ships in the binary

**RULED 2026-09-12.**

Trust and safety decision D5. A list of SHA-256 fingerprints of people confirmed abusive, as a
resource in `CarpenterKit`, applied on receive as if the member had blocked them, behind a switch
that defaults to on. It changes when the app does. The alternatives — the public CloudKit database,
a static file on a CDN — would turn every launch into a check-in visible to whoever runs the
endpoint, in an app whose whole claim is that nothing observes its members.

**Cost:** propagation is one release cycle. Local blocking is the immediate remedy, and the settings
footer shows the list's date so a member can see how old what they rely on is.

### Blocking stops the key handover, and stopping it is the whole point

`RULED` — Griff, 2026-09-14.

Blocking somebody stopped their words being drawn and nothing else. They stayed a rewrap target, so
this member kept handing them a wrapped copy of every future room key, and kept collecting and
acknowledging their packets — which means their app said *collected*, and later *shown*.

Griff's reasoning, and it settles a question that had been treated as a dilemma: **people work out
that they have been blocked because their messages stop being delivered. Every messaging app behaves
that way and this one is not going to break the convention.** The app never says why. It simply stops
answering, and the sender's own *nothing has gone* mark is what eventually speaks — see
[the pending mark](#a-message-is-only-pending-when-nobody-has-it). His words: "If you block bob, you
shouldn't be responsible for handing him a key. He can't communicate with your impl."

So a block, from the blocker's device: they are dropped from the rewrap targets, their packets stop
being collected and acknowledged, and they are dropped from the Outpost audience. The room's key is
not turned; see below for why.

**What it costs.** In a direct conversation the blocked person can tell, because there is nobody else
to hand them a key. That is the intended effect rather than a leak. In a group they usually cannot,
because every other member still hands them theirs.

**What actually made it real, built 2026-09-14.** The filter is applied wherever `CarpenterApp`
addresses a person: `peers()`, the two `rewrapTargets` call sites, the media upload, the bell, and
`outpostReaders()`.

- **Not answering is the whole of it.** `peers()` did not filter blocked people, so their packets
  were still fetched *and acknowledged* — their app was told *collected*, and then *shown*. Dropping
  them from `peers()` is what makes messages stop being delivered, which is the signal the
  convention actually runs on.
- **The Outpost is the one place a block ends access outright**, because a wall has a single owner
  and there is nobody else to hand its key over.

**And one thing that turned out to be ceremony.** This entry first said blocking must also turn the
room's epoch, on the reasoning that a stable room never re-keys so the blocked person reads on with
the key they hold. Building it showed that is wrong in both directions, so it was not built:

- In a **group**, turning the epoch changes nothing. Every other member's `rewrapTargets` still
  includes the blocked person, so they are handed the new key by somebody else on the next round —
  which is exactly the property that keeps the block silent. The turn would cost every member a
  re-key and buy nothing.
- In a **direct conversation**, not answering has already done it. Nothing is written to them and
  nothing of theirs is collected, and there is no third party to carry anything either way.

So a block does not re-key a room. What a member gives up is stated plainly rather than implied:
inside a shared room, blocking is this device refusing to deal with somebody, not a wall around what
they can read.

**Where the filter may not go.** `RoomRoster.rewrapTargets` is in `CarpenterKit` and is derived from
entries every member replays; blocking is local and lives in `persisted.preferences`. Putting the
filter inside the roster would make the fold device-specific, and two devices reading the same log
would disagree about who is in a room. It goes at the `CarpenterApp` call sites.

**A case to accept deliberately.** If every member of a group blocks the same person, they receive no
key from anybody and are removed in effect while the roster still lists them as a member. That is the
sum of individual choices rather than a removal, and the member list will keep showing them.

## Deleting and hiding

### Deletion is shared ownership

**RULED 2026-09-12.**

A member may always refuse to hold something. A member may never reach into somebody else's history
and take it away.

Hiding is the default. It is kept in the member's own preferences, which reach their own devices,
rather than written as an entry, because an entry would reach every peer and so would *announce* that
you had hidden something. Deleting a whole conversation you are no longer in is also built, and is
equally local to the member. Hidden entries still sync: an entry that stopped syncing would let one
member silently rewrite what everybody else can see.

Removing a message from other people needs their agreement. See
[Advanced data etiquette](epics/data-etiquette.md).

### A purge is a tombstone, and the link survives it

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**2026-09-09.** Destroying a message replaces its payload with a tombstone and leaves
the entry where it is. The hash chain verifies unchanged, the words are gone from every device that
folds the tombstone, and the fact that *something was there* stays visible.

**Why not the other answer.** The alternative was removing the entry outright and teaching the
validator to accept a gap where a predecessor used to be. That buys one thing — nothing at all
remains — at the cost of the property the chain exists for: a validator that tolerates gaps cannot
tell a purge somebody asked for from a truncation somebody performed. Every entry in this app is
verified against its predecessor, so the day that check becomes optional is the day the log stops
being evidence of itself.

**What it costs.** A purged message leaves a hole a member can see: the room says something was here
and is gone. That is the honest reading and the screens must not dress it as anything else — a
transcript that closed over the gap would be the app hiding a thing it knows. It also means a purge
is not deniable: everybody who folded the room knows the message existed and knows it was destroyed.

**What this unblocks.** [Consensus hard delete](after-testflight.md#consensus-hard-delete) and
*Hard delete and desync quietly*, which were both blocked on this one question and were moved past
TestFlight on 2026-09-14.

**What would change it.** A verification scheme that can prove a gap was authorized — a signed
statement over the removed entry's hash, folded in its place. That is a tombstone with extra steps,
which is the argument for starting here.

### Silence in a consensus delete is silence

**RULED 2026-09-13 by Griff.** Somebody who never answers a consensus request does not consent and
does not refuse. The request hangs until the member who started it closes it, which is already what
the ticket asks for.

**Why not a window.** Both timed answers put a decision in somebody's mouth. Silence-refuses means a
week away is a vote against; silence-consents destroys somebody's copy on the strength of them not
looking at their phone, which is the one outcome this feature exists to prevent.

**Cost:** a request can stay open for ever, and the initiator has to close it by hand.

### A deletion leaves a line in the transcript, not a notice that fades

`RULED` — Griff, 2026-09-15: "Yeah, I'm good with the permanent inline."

His earlier ruling was a **passing notice** when somebody taps a *Consensus reached.* push. He asked
on 2026-09-15 that the HIG decide the form, and it pointed away from that. Apple's
[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) guidance, read the
same day:

> Avoid using an alert merely to provide information … **If you need to provide only information,
> prefer finding an alternative way to communicate it within the relevant context.**

> … you could show cached or placeholder data and **a nonintrusive label that describes the problem**.

There is no toast in the HIG because Apple does not want one. For a message that was deleted the
relevant context is *the place in the transcript where the message was*, and this app already draws
system lines there — *Griff invited Outie*, *Outie confirmed the invitation*.

It is also better on this project's own honesty rule: **a notice the member misses is a thing the app
did not tell them**, and there is no way for them to go back and check.

**Not built, because the thing it describes is not built.** Consensus delete is
[pushed out](after-testflight.md) and there is no consensus code in the source at all. This is
recorded so the form is settled before the work starts rather than under pressure during it.

### Hiding a message reaches your own devices

**RULED 2026-09-13 by Griff.** Hiding was per device: hide something on a phone and it was still on
the iPad, while the copy said "it stops being drawn on your devices", plural. Built the same day.

The per-message hidden flags ride the sibling feed, the way the member-level preferences already do.
That channel reaches this member's own devices and nobody else's, and since 2026-09-13 it is sealed
under their identity, so what they chose not to see is not readable by the transport.

**Cost:** a hidden flag is one more thing in a feed that is already the largest record this app
writes.

### Nothing this app holds is deleted without being asked

**RULED 2026-09-13 by Griff**, settling retention.

The storage row counts the photos and clips on this device and nothing removes them on a timer, at a
size cap, or on any other rule the member did not ask for. A control to clear media older than a date
the member chooses was planned and moved past TestFlight on 2026-09-14.

**Why not a default age or a ceiling.** Both mean the app destroys something the member kept, without
being asked, to solve a problem it decided they had. That is the opposite of every other line this
app takes about somebody's own history.

**Cost:** a phone can fill up, and the app will say so rather than fix it quietly.

### Deleting a conversation reaches every device, waits for the leaving, and leaves photos for others

`PROPOSED` by Claude, 2026-09-17 — a default, not a constraint. Griff ruled the shape on 2026-09-14:
record what is finished, built once. These are the calls made building it.

- **It follows the member.** A deletion rides `MemberPreferences.deletedRooms` on the sibling feed, so
  the member's other devices delete the room too. The alternative left the other phone handing the
  room's keys and its own entries straight back, and matches nothing else here: hiding already follows
  the member. What it costs: deleting on one phone deletes on the others, and that is unproven across
  two real phones on one account, which no simulator can join.
- **It waits until the leaving has been sent.** A departure still in the outbox when its entry is
  deleted is never sent, so the room would go on treating the member as present. Delete is not offered
  until it has gone; `deleteRoom` refuses with a sentence if asked anyway.
- **A photo this member sent stays in their iCloud outbox** until the people owed it collect it. Their
  copies are theirs; deleting mine does not take back what they have not fetched yet. It costs that
  photo's storage until the last acknowledgment.
- **Being let back in reopens it.** Accepting a new invitation to a deleted room gives its numbers
  back, so the history can be asked for again and may return. The alert says it *may not*.
- **The alert.** Title *Delete* and the room's name; one message; *Delete* and *Cancel*. *Delete* is
  not given the destructive style, because the person already chose a destructive item to get here,
  and the Alerts page says the destructive style is for an action "people didn't deliberately
  choose" ([Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)). The menu
  item that leads to it is destructive, with the trash symbol, and last, as Context menus asks.
- **Unavailable items are hidden, not dimmed**, which is what Context menus says for a context menu.
  That also stopped *Leave* being offered on a room already left.

## Recovery and devices

### Recovery is a key you download, and it is the only thing that opens a backup

**RULED 2026-09-09 by Griff, and reconfirmed since.** One of the few entries that was correctly attributed before this pass.

**2026-09-09, Griff's ruling.** At account creation the member is prompted to download their recovery
keys, the way GitHub and every enterprise tool prompts for recovery codes. Those keys are their
identity — the signing and agreement pair their `ParticipantID` is a hash of — and they are **the only
thing that can unlock a backup file**.

**Two files, opposite risks, and they must never be confused.** The recovery key is small, secret and
theirs alone: it contains no message and nobody else's data. A backup is large and full of words
other people wrote to them in confidence. Sealing the second with the first is what makes the pair
safe to hand somebody: a backup without the key is ciphertext.

{: .unbuilt }
> **The backup file is not built.** What is built is the key, and history coming back from the people
> who were there; see [A restored device asks its peers for what was said](#a-restored-device-asks-its-peers-for-what-was-said).

**What recovery restores, and what it cannot.** The keys make them *them* again — peers address them,
their entries verify, and the current epoch key is rewrapped to them on the next round, so the rooms
come back. History does not come with the keys; it comes from the people who were there, if the
member asks and they have not held it back, or from a backup once one exists. The screen says so.

**Social recovery is refused, and this is the decision that refuses it.** Nominated friends, k-of-n,
was the sketch and it is scratched. It replaces *nobody can become you* — which is the design rather
than a limitation of it — with *k of your friends, together, can hand your identity to whoever asks
convincingly*. The attack is a phone call, it works best against exactly the people somebody
nominates because they would help, there is no server to rate-limit it and nothing out-of-band to
check against. It also puts a named social graph into the protocol and makes those friends' devices
worth attacking for reasons of their own.

**Handing a trusted person your key or your backup is not the app's business.** It is a deliberate act
by the member, out of band, with no protocol support and no protocol risk. The app neither encourages
nor prevents it.

**Cost.** A member who loses every device *and* the key file is finished, and the app says so plainly
at creation and in Devices. Prompting at creation is the only moment the member has nothing to lose
yet, which is why it is there and not in a settings screen they never open. And an identity key that
copies itself anywhere without being asked would be a worse default than no recovery at all, so
nothing is automatic.

**What would change it.** Nothing short of a party who can vouch for a member without being able to
impersonate them, which the architecture does not have.

### Recovery is announced, and both sides of it have settings

**RULED 2026-09-13 by Griff.** He rejected a silent restore: "you're requesting to fill history
you've lost which means you're asking for it — I feel like that being silent is not great."

A recovery key restores who you are. History comes back from peers through the ordinary repair path,
and **that request is not silent**. Two sides, each with its own settings.

**The recoverer** chooses whether to ask peers for history at all. On by default; off means the key
restores the identity and the rooms come back empty, for somebody who would rather not announce a
restore to everybody they know.

**The person being asked** gets two answers. *Tell me when it happens* — a notification naming who
restored and which conversation was asked for. And *hold until I check* — nothing crosses until the
solo check passes with the restored device. **History goes by default and waits only if they have
said to wait.**

**The default follows the privacy check-up**, which is the one place this app already asks somebody
how careful they want to be. Griff's rule: *Familiar and open* leaves holding off, *Locked down*
turns it on, and the walkthrough asks. Note that this is the opposite of read receipts, which are off
whatever the preset says — receipts are a thing you do to other people, and this is a thing other
people do to you.

**Cost:** a restore can stall on anybody who chose to hold, and they may not be at their phone. That
is the price of the setting being theirs.

**What would change it:** a restore that peers cannot distinguish from ordinary repair. There is no
such thing today — a restored device is a new device key signing as a known identity, which is
exactly the shape worth telling somebody about.

### Turning every room's key on a restore is a question, not a default

**RULED 2026-09-13 by Griff:** ask on the restore screen.

Before this, nothing about a restore turned a key. If a lost phone is in somebody else's hands it still
holds the current epoch key and reads everything said afterwards, because `rewrapTargets` is keyed by
participant and the thief's device is still certified under that identity.

So the restore screen asks once — **was a device lost or stolen?** — and a yes turns the key in every
room. It is the one moment the member has actually said out loud what happened, and it makes the cost
legible instead of surprising.

**What it costs.** A burst of epoch changes across every room at once, and any device the member still
owns goes dark until they restore it too. Answering no leaves the old devices reading along until one
is revoked from the device list, which now shows a real arrival date for each.

**Why not automatic.** A key turn is not free and not reversible, and "I restored onto a new laptop"
is not the same event as "my phone was taken". The app does not know which happened and must not
guess.

### A restored device asks its peers for what was said

`PROPOSED` — Claude, 2026-09-13, from the rig.

An entry goes into a packet once. `syncedFrontier` is the sender's record of what it has already
written out, and it is not per-recipient, so a peer that has already delivered an entry to a member
will never offer it again — not to that member's new device, not to anything. That is the right
behavior for the ordinary case and it is exactly wrong after a recovery: measured across two Apple
Accounts, the restored device logged `entriesReceived=0` on every round while the peer logged
`unsent=0`, and nothing the peer held ever came back.

So **the restored device asks, rather than waiting to be re-sent to**. `restore(fromRecoveryKey:)`
sets `PersistedState.wantsWhatWasSaid`, and the first full round that finds both a room and a
reachable peer raises a quiet `HistoryRepair` in every room, then clears the flag. The flag is
persisted rather than held in memory because the rooms arrive from the member's own zone several
rounds after the restore, and a relaunch in between would otherwise lose the only signal that this
device is missing anything.

The cost: a restored device raises one repair per room on its first useful round, which is a packet
per peer per room. It is bounded — the flag clears once, and repairs already dedupe per room.

The alternative considered and rejected: have the *peer* re-offer when it meets a new device for a
member it already knows. That is a per-recipient frontier, which is a much larger change to the
sender's bookkeeping and would re-send to every device a member ever had, including the lost one.

**The automatic repair does not cover this**, and that is why it was missed: `repairWhatHasNotFilledItself`
fires on a named hole — a gap *between* entries a device holds. A restored device has no holes. Its
frontier is simply short, and a feed it has never seen cannot be a gap.

### A restore says so, and the person asked is told what was observed

`PROPOSED` — Claude, 2026-09-13, building [the ruling on announcing a recovery](#recovery-is-announced-and-both-sides-of-it-have-settings).

**The ask carries a reason.** `RepairRequest.reason` is `.gap` or `.recovery`, and a request written
by a build that predates the field reads as `.gap` — anything else would announce every old repair
as somebody coming back. The recoverer declares their own event; the responder does not infer it.
Inferring was the alternative, and it cannot be done honestly: from a peer's side a restore and a
second device are the same shape — a device key they have not seen, signing as an identity they know.

**A recovery ask rings the peer's bell.** An ordinary repair does not, which is right: it can wait
for the next round. "Tell me when it happens" cannot wait for the next time they open the app.

**What the banner may say is what was observed.** It says a new device was set up and which
conversation it asked for. It does not say "restored from a recovery key" — this device did not see
a key. It names whoever it can name, which for somebody who does not share their name is their code.
It obeys the notification level like every other banner: `.whereOnly` drops the person, `.nothing`
falls back to the generic one.

**The ask is recorded, not read off the duty.** A `RepairDuty` is taken on and answered inside the
same round, so it is gone before anything can read it — and the notification extension, which syncs
read-only and never answers, would have seen a duty the app never does. `PersistedState.restoreAsks`
keeps the last twenty, so both processes see the same thing and a relaunch mid-restore does not lose
it.

**The default is the preset**, per Griff's rule: *Familiar and open* off, *Locked down* on, the
walkthrough asks. **History goes either way** — this setting decides only whether somebody hears
about it. Holding history until a solo check passes is the other half of the ruling, in the next
entry.

**Measured on the rig 2026-09-13, two Apple Accounts:** the restored device logged `recovery: asked
1 peer(s) for what was said`, and the peer logged `recovery: 72b5c751 came back and asked for
history` and answered with three entries.

**Not measured:** the banner itself. The preference was staged on disk rather than turned on through
its row, and no push was delivered to a device a person was holding.

### The hold is on the backfill, not on the conversation

`PROPOSED` — Claude, 2026-09-13, building the *hold until I check* half of [the ruling on announcing a recovery](#recovery-is-announced-and-both-sides-of-it-have-settings).

**What it holds.** A `.recovery` repair answer, and only that. `answerRepairs` skips a duty from
somebody whose coming-back is `.held`, and the duty stays in place until the member decides. Measured
on the rig across two Apple Accounts: the peer logged `held until this device's member checks` and
wrote no answer; the restored device did not get the message; the member tapped *It matched — send*,
the peer logged `was let through` and answered with four entries, and the message arrived.

**What it does not hold, and why the copy now says so.** Anything the peer has not yet delivered
still goes by the ordinary path, because a restored device is the same identity and still a member
of the room. Holding that too would close the conversation for both of them over an event only one
of them knows about — and it would not protect anything, since somebody holding the key is a
legitimate peer of that identity until they are removed. So the hold covers *what was said before*,
which is what the recoverer actually asked for. A first cut of the rig test measured an undelivered
message and appeared to show the hold failing; it was measuring the ordinary path.

**Refusing is remembered, not forgotten.** A refusal sets the ask to `.refused` and drops the duty.
`RestoreAskRecord` is in `PersistedState`, so it survives a relaunch — the trap this repo already
has: clearing derived state does not end a question, and the restored device will ask again.

**Turning the setting off releases what is already waiting.** Otherwise the only way to answer a
held ask is a prompt the member has just told the app to stop showing.

**The characters come from the attestation either way round.** `roster.requests` is keyed by
*joiner*, so the person who invited you has no entry there — the phrase between you and them is on
the attestation that made *you* a member. Looking only one way, which is what the existing
`whoYouAreTalkingTo` does, gives no phrase to whoever was invited.

**Not measured:** the setting turned on through its own row; it was staged on disk.

### Asking for your history back is the recoverer's own choice, made at the restore

`PROPOSED` — Claude, 2026-09-13, completing [the ruling on announcing a recovery](#recovery-is-announced-and-both-sides-of-it-have-settings).

`MemberPreferences.asksPeersForHistory` defaults **on** — the first preference here that does, so
`isAskingPeersForHistory` reads `?.value != false` rather than `== true`. Off means `restore` never
sets `wantsWhatWasSaid`, so no repair is raised, nobody is asked and nobody is told.

**The choice is on the restore screen, not only in settings**, because that is the moment it matters
and the moment the member knows what happened. It is also a row on Privacy & Safety, because the
restore screen promises they can change their mind and a promise the app cannot keep is worse than
no setting. Turning it back on re-raises the ask, but **only on a device that actually came back from
a key** — `cameBackFromARecoveryKey` gates it, or toggling a setting would announce a restore that
never happened.

**It is not on the privacy check-up.** The preset rule Griff gave covers the person being asked; this
is the recoverer's own side and the check-up is not where somebody is when they restore.

**Measured on the rig, two Apple Accounts:** restored with the switch off, the device logged
`restored without asking anybody for what was said`, and the peer logged nothing at all — no recovery
line, no recorded ask, no duty.

**On driving switches.** An instantaneous synthetic tap did not move a switch that day, but a touch
that pressed and dwelt on it did, and the rows in this work were exercised that way.

**Not measured on the rig:** changing your mind afterwards. Covered by a test that fails without the
`wantsWhatWasSaid` reset.

### The lost-or-stolen question is a choice with no default, not a switch

`PROPOSED` — Claude, 2026-09-13, building [the ruling on turning keys after a restore](#turning-every-rooms-key-on-a-restore-is-a-question-not-a-default).

Griff ruled the restore screen asks *was a device lost or stolen?* and that the app "does not know
which happened and must not guess". A switch cannot express that: a switch always has a position, so
shipping one would be the guess the ruling forbids. Apple's **Toggles** page draws the same line —
*"A toggle always lets people manage the state of something, so if you need to support other types of
actions… use a different component"* — and this is not a state the member manages, it is a one-time
answer about what happened. So it is two `ChoiceRow`s with nothing selected, **Restore this device
stays disabled until one is chosen**, and the footer changes to name the cost of whichever answer is
showing.

**When the turn happens.** `restore` records the answer in `PersistedState.turnsEveryKeyAfterALoss`;
the first full round that finds rooms with chains owes an epoch turn in each and clears the flag.
It cannot happen at the restore itself — the rooms arrive from the member's own iCloud several rounds
later, which is why the answer is persisted rather than held in memory.

**Measured on the rig, two Apple Accounts:** answering yes logged `a device was lost or stolen; every
room's key turns`, then `turning the key in 1 room(s) after a loss`, then the turn itself; a message
sent afterwards was read by the peer, so the turn cut off the device that is gone without cutting off
the member who is still there.

**What answering no costs.** An old device keeps reading along until it is revoked from the device
list, which does show a real arrival date for each — checked on the rig
2026-09-13 with eight devices, every one carrying the minute it was added.

### A device has a name, and the name is the member's alone

`PROPOSED` — Claude, 2026-09-13, after eight devices accumulated on one account during the recovery
work and the list was accurate but unusable.

A device carries a name in `MemberPreferences.deviceNames`, keyed by `DeviceID` and stamped like
every other preference. Preferences ride the **sibling feed**, which goes to the member's own iCloud
and nowhere else and is sealed — so the list reads the same on every device they own and reaches
nobody they talk to. That matters: what somebody calls their own phone is not a fact about them
anybody else is owed.

**The default comes from the hardware identifier, and there is no marketing-name table.**
`HardwareName.ofThisDevice` reads `SIMULATOR_MODEL_IDENTIFIER` or `hw.machine`, giving `iPhone18,1`.
A table mapping that to *iPhone 17 Pro* is exactly the shape this repository has been bitten by twice
— a list somebody has to remember to extend, failing invisibly on the next model, which would show a
confidently **wrong** name. An identifier reads as a code and is never wrong.

**It is set once.** `nameThisDeviceIfUnnamed` returns early if the device already has a name, so a
later launch cannot overwrite what the member chose.

**The code stays visible under a named device**, because the code is how a device is matched when two
people compare, and a name the member invented cannot do that job.

**Clearing the name brings the code back** rather than leaving an empty row.

**Measured on the rig 2026-09-13:** this device named itself `iPhone18,1` on first launch; renaming
another to *The phone I lost* through the swipe action put the name in the row with its code and date
beneath.

### Removing devices is a selection, not a button in every row

`PROPOSED` — Claude, 2026-09-13, after Griff said the remove control was in the wrong place.

**What was there.** A hand-rolled `Button` in each row, inside an `HStack(alignment: .top)` so it
sat beside the device's name rather than with the row; duplicating a swipe action that already
existed; and drawn in `palette.accentColor` — a destructive action in the *approving* color, which
is the "a tint beats a role" rule failing in the other direction.

**What replaced it.** Native selection. Apple's **Lists and tables** is unambiguous — *"In iOS and
iPadOS, people must enter an edit mode before they can select table items"* — so the list takes a
`selection:`, a trailing **Select** toggles edit mode, and rows that cannot go (this device, and
already-removed ones) carry `.selectionDisabled`. The swipe action stays for the one-off, which is
also standard.

**Where the controls sit.** Apple's **Toolbars** page separates *navigation controls* from *actions*
and warns against crowding. Select is an action, so it belongs on the trailing side, not beside the
back chevron where it first went and read as navigation.

**The destructive action is not in the toolbar.** Apple's own pattern puts it in a bottom bar, but
this app draws a floating tab bar there — `.status` placement rendered it *behind* the tab bar,
found on the rig. It is a `safeAreaInset(edge: .bottom)`, which is what `RoomsListView` already does
on a tab-bar screen, in `destructiveActionButton()` so the color is the system's and not a hand tint.

**One removal is one event.** `revoke(_ devices:)` issues every revocation, then turns each room's
key **once** — not once per device. Removing three used to mean three bursts of rewrapping for
everybody in every room. A batch naming this device throws before anything is written, so a refusal
changes nothing.

**The confirmation names what is going.** A dialog that says only *Remove these 2 devices?* asks
somebody to confirm against a number while they selected by name — two screens that never reconcile,
on a decision with no undo. It lists each device by its name, or its code where it has none, above
the sentence about what removal costs.

**Inflection does not work in a `confirmationDialog` title.** `^[Remove \(n) device](inflect: true)`
rendered as its own raw markup on screen, while the same string inside the dialog's button inflected
correctly. Found on the rig. The title picks between two written sentences instead.

### The removal confirmation is a bottom sheet, not a dialog

`RULED 2026-09-13 by Griff`, on seeing it: "Use a bottom sheet, this looks awful."

A `confirmationDialog` on iOS 26 rendered as a popover with a tail pointing into the list, floating
over the rows in a narrow column that broke *Remove these / 2 devices?* across two lines. It is a
`.sheet` with `.presentationDetents([.medium])` now: the question, each device going by name, what
removal costs, then the destructive action and Cancel. Apple's **Sheets** page is the fit — *"a
sheet helps people perform a scoped task that's closely related to their current context"* — and its
rule that a confirming button is always paired with Cancel is why Cancel is there rather than relying
on the drag indicator.

### Being told a restore asked for your history is on unless you turn it off

`RULED` — Griff, 2026-09-13, that this is "not a setting — everybody gets it". Built the same day
with the opposite default, and fixed 2026-09-14.

`MemberPreferences.isToldAboutRestores` read `toldAboutRestores?.value == true`, so **nil meant no**.
Anybody who had never opened the privacy check-up was never told that a device signing as somebody
they know had come back from a recovery key and asked them for everything the two of them had ever
said. The *Familiar and open* preset — the friendly one, the one most people will take — set it to
`false` explicitly, which turned the notice off for exactly the members least likely to go looking
for it.

This is the one notice in the app about somebody else's device collecting this member's history. It
is now `!= false`: on unless the member turns it off, the check-up's default is on, and both presets
agree. `BeingToldAboutARestoreTests` pins the default, and pins that turning it off still works.

**How it was found**, because the route matters more than the fix: writing a live CloudKit test for
the restore path, which failed at the notice rather than at the history. Twenty-four tests covered
this feature and every one of them set the preference explicitly in its fixture, so none of them
could see the default. A fixture that configures the thing under test cannot fail the way a member
fails.

**What it cost while it stood.** Nothing measurable — no member has run this build. But the row said
*Complete (QA required)* with twenty-three passing tests, which is exactly the shape of a claim this
project has been wrong about before.

### A first launch that cannot reach iCloud waits

`RULED` — Griff, 2026-09-16: wait until it can check.

Before a device makes a member it asks the Apple Account whether one exists. An **occupied** account
already stopped; an account that could not be **reached** — no network, not signed in to iCloud,
or a managed account that is restricted — was offered a fresh member, because nothing could be
checked. That is exactly how an account ends up with two identities. It now stops at *Could not
reach iCloud* with a retry, and a recovery key still restores. A session never given a way to ask
counts as unreachable too, so the erase-everything path now asks the account the way launch does.

**What it costs.** A first launch with no connection cannot set up. The app cannot do anything
useful without iCloud anyway.

## Interface

### Native first, and custom only where the app is actually different

**RULED 2026-09-12.** Strict — and Griff asked that this cover Apple's **intention**, not only their components: "we want to follow their intention as well as their components." A `List` used where Apple would use one, arranged in a way Apple would not, satisfies the lint and misses the point. See the HIG rule below.

Anything the system draws, the system draws. A `List` section, a navigation bar, a toolbar, a sheet,
a `Toggle`, a swipe action, a scroll edge effect: these arrive maintained, keyboard- and
VoiceOver-correct, right at every Dynamic Type size, and they inherit whatever the platform does to
them next year. Reimplementing one buys nothing and signs up for all of that by hand, forever, on
three platforms, maintained by one person.

**The failure mode is not ugliness, it is silent drift.** Three screens hand-drew the same
inset-grouped list — a `VStack` of buttons, `Rectangle().fill(palette.separator)` between them at a
hand-measured inset, a rounded rectangle behind the lot. Each got the inset slightly different, one
animated the selection and two did not, and the selection idiom differed between them. All three
looked fine in isolation, which is exactly why nobody noticed they disagreed. They are one `Section`
of `ChoiceRow` now, and `lint-branding.sh` rejects a hand-drawn row separator so a fourth cannot
start quietly.

#### Liquid Glass belongs in a container, and custom glass answers a finger

Two rules, both straight from Apple's guidance, both of which this app was breaking:

**Sibling glass shapes go in a `GlassEffectContainer`.** *"Use `GlassEffectContainer` when applying
Liquid Glass effects on multiple views to achieve the best rendering performance"*, and *"applying
too many effects to views outside of containers can degrade performance."* A container is also the
only way two shapes can blend or morph into each other, which is most of what the material is *for*.
The app had **zero** containers and a composer whose plus button and text field were two glass
shapes side by side in an `HStack` — each sampling its own backdrop, neither able to interact with
the other, ever.

The container's spacing is the row's own spacing, deliberately: a container spacing *larger* than the
layout's makes shapes blend at rest, which for a button beside a field would read as one smeared
control.

**A custom glass shape that is a control takes `.interactive()`.** It is what gives a shape you drew
the responsive reaction the system's own glass buttons have. Glass that does not move under a press
reads as an inert panel rather than as a control. The one exception is the composer's plus button
where a conversation cannot take a photo: it is disabled, and a disabled control that springs under a
finger and then does nothing is a worse lie than a flat one.

`lint-branding.sh` rejects a file with more than one `.glassEffect` and no container.

**Why this matters beyond today:** the container is the unit the system animates and composes. Code
that puts its glass in one inherits whatever iOS 27 does to the material; code that scatters bare
effects has opted out of that by construction.

What stays custom is what the system has no opinion about, and each of these earns it:

- **The message bubble.** Its corner set is measured against its own height so a one-line bubble is
  not most of the way to a capsule, and the tail marks the end of a run.
- **The transcript.** A `LazyVStack` in a `ScrollView` rather than a `List`, because runs, notices,
  delivery marks and a bottom anchor are not rows.
- **The composer.** A glass capsule with send inside it, which is what Messages draws and no system
  control offers.
- **The mark.** Fourteen hand-drawn frames, played as stop motion.
- **`ChoiceRow`.** The row inside the system's section: a choice paired with the consequence of
  choosing it, read as one sentence.

**Cost:** the system's components carry the system's opinions, and some of them are not this app's
— a grouped list's top inset is wrong for a masthead, and `.tint()` still does not reach
`searchable()`. Each is answered where it comes up rather than by drawing the whole component again.

### The Human Interface Guidelines are the reference, and a departure is a decision

**RULED 2026-09-12 by Griff**, who proposed the rule. Extended the same day: Apple's *intention* is in scope, not only their components.

Where the system offers more than one way to draw something, the choice is made by reading
[Apple's guidance](https://developer.apple.com/design/human-interface-guidelines) for that
component — not by picking whichever looked better on the one screen it was tried on. Where the
guidance turns on a question about the app, that question is answered here before the modifier is
chosen.

**What it costs.** Reading before choosing, and writing down every deliberate departure with its
reason. The second half is the part that will be skipped: an undocumented departure cannot be told
apart from nobody having looked, and this file is where the difference is kept.

**What would change it.** Nothing about the rule. Individual departures change all the time — that
is what recording them is for.

**Why now.** `.searchToolbarBehavior(.minimize)` was chosen for the collapsed glass magnifier it
draws. On a 402pt iPhone it puts the clear control and the dismiss control inside one capsule; on a
440pt iPhone it separates them. Same build, two devices, reported from the rig — and the reason
nobody caught it is that nobody had read what Apple says about search. What Apple says is that the
question to answer first is *what is the scope of this search*, and that a search scoped to one
section belongs inline under the title, with placeholder text that names what is being searched:
the Music-library pattern, not the collapsed magnifier. That reading was itself overturned the same
day, as the next entry records: the app's main search became a tab.

### Search is a tab at the trailing end, and the inline field is for sub-views

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

**Decided 2026-09-12**, replacing a wrong call made the same day.

Search is a `Tab(role: .search)` at the trailing end of the tab bar, in **button appearance** — the
field takes focus and the keyboard comes up on tap — with a scope bar to narrow between messages,
Outposts and settings. The one inline field that stays is People, under You.

**What it costs.** A tab, and a global search that has to mean something across three kinds of
content. That is the work; it is not a modifier.

**What would change it.** Losing the tab bar, which would make it a bottom toolbar instead.

**The wrong turn, recorded because the reasoning is the useful part.** The first attempt dropped
`.searchToolbarBehavior(.minimize)` and made all three searches inline under their titles. That was
argued from a summary of the WWDC session rather than from the page, and the page says two things
that undo it:

> Place search at the bottom if there's room. […] Place search at the top when it's important to
> defer to content at the bottom of the screen, or there's no bottom toolbar.

This app has a tab bar full of content at the bottom and nothing that needs deferring to, so it is
not the top case. And the inline guidance is not the alternative it was read as:

> …although the main search in the Music app is a tab, people can navigate to their library and use
> an inline search field to filter their songs and albums.

Music has **both**. "Useful if your app has more than one search field" describes a tab *plus* an
inline filter on a sub-view — not three inline fields instead of a tab. Rooms, solos and the
Outposts feed are the top level of their tabs, so they belong to the search tab; People is a list
inside You, which is the Music-library case exactly.

**And the rule worked, slowly.** The HIG rule one entry up is what made this correctable: the first
call was written down, so it could be read back against the page and found wrong. A summary of a
video is not the page — see it, or do not cite it.

### The reaction picker is drawn here, and it is the one place the system offers nothing

**RULED 2026-09-13 by Griff**, after the first answer was wrong and he asked for it to be relitigated.

The bar keeps the four emoji this member reaches for most. Behind it is **our own searchable grid**,
in the shape Signal and WhatsApp use, rather than the system emoji keyboard.

**What the research found, 2026-09-13.** Apple's own Messages opens the emoji keyboard from a gray
button at the end of its tapback row. Every third-party messenger draws its own picker instead —
Signal searchable with skin tones, WhatsApp six fixed plus recents, Telegram sixteen. They do that
because **there is no public API to present an emoji picker**; the Reminders-style emoji-only keyboard
is private. The keyboard can be forced by overriding `textInputMode` on a text field, which is public.

**So native-first does not decide this one, and the first answer said it did.** Native-first is that
anything the system draws, the system draws. The system draws no emoji picker for apps, so a grid is
not a reimplementation of a system control — there is no control to reimplement. That correction is
why this entry exists.

**What it costs.** A Unicode table that has to be kept current, which is the same complaint that
retired the hand-maintained twenty — with the difference that a table is data and twenty hard-coded
characters were a guess. Searching by name is the thing the keyboard cannot do and the reason people
reach for these pickers.

### The rooms list row is Messages', and board 53 is overruled

**RULED 2026-09-13 by Griff**, ratifying a change Claude made on 2026-09-05 without asking.

Board 53 puts the sender's name in a group room's list preview. The app does not: the row is measured
against Messages on the same simulator — 45pt avatar, 8pt gutter with the unread dot in it, text at
84pt, two reserved preview lines, a chevron — and names no sender.

**Why.** Drawing the name as a pill above the preview pushed the row to three lines, and Messages is
the reference the rest of this app already uses for presentation. **What it costs:** in a group, who
said the last thing is one of the things the row is for, and it is not there.

### The mark stands where You's title would be, and that is a departure

`RULED` — Griff, 2026-09-14.

`YouView` sets `.navigationTitle(Text(verbatim: ""))` and `.toolbarTitleDisplayMode(.inline)`, and
draws an `AnimatedMark` at the top of its content. So the tab root has **no title**, and the app's
own mark occupies the place a title would. The roadmap claimed "You is large since 2026-09-05",
which was never true of the code.

**Read on the day, at
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars):** an empty title
is allowed — "If titling a toolbar seems redundant, you can leave the title area empty", which is
what Notes does for a single open note. Two other lines cut the other way. "Don't title windows with
your app name. Your app's name doesn't provide useful information about your content hierarchy",
and the mark is the app's name drawn rather than spelled. And "Use a large title to help people stay
oriented as they navigate and scroll", which is the orientation the tab root gives up.

**Decided: keep the mark.** It is a deliberate identity choice on the one screen that is about this
member and their app rather than about a conversation.

**What it costs.** You is the only tab root that does not say where it is, so somebody arriving by a
deep link or returning after a while has the mark rather than a word to orient on, and the large
title's scroll behavior — collapsing as content moves, expanding at the top — is not there to tell
them they are at the top of the screen. If a member is ever observed unsure of where they are on
that tab, this is the first thing to reverse.

**What it costs with VoiceOver, measured 2026-09-17** with VoiceOver actually running on the rig
rather than inferred from the element tree. Opening the You tab, the first thing VoiceOver says is
**"Outpost, Image"** — the mark, which is an accessibility element on purpose, labeled with the
product name and given the image trait so it does not read as a control. A sighted member at least
sees the mark and knows which app they are in. A VoiceOver member gets the app's name and no word
for the screen, and there is no title element anywhere on the tab to find with the rotor, because
the title is deliberately empty. So the cost this entry already names is strictly larger here: it is
not that the screen is titled weakly, it is that for VoiceOver the screen is not titled at all.

Left as it is, because reversing it is Griff's call and the entry above is his. The cheap half-step
if it is ever wanted: keep the mark and give the tab an empty-looking inline title that VoiceOver
still reads. Nothing has been changed on the strength of this measurement.

### The camera is asked for when it is first wanted, and never at launch

`RULED` — Griff, 2026-09-14, on adding camera scanning of an invite QR.

Redeeming an invite worked by pasting a code, and the QR was only generated, never read. Adding
scanning brought a camera permission and a usage description with it, which is a new surface for
review and a new thing to explain. Built 2026-09-16.

**The shape Griff asked for**, and Apple's guidance says the same thing at
[Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy):

- The app asks, in its own words, before the first use of scanning — never at launch. Apple:
  "Ideally, wait to request permission until people actually use an app feature that requires
  access", and "Avoid requesting permission at launch unless the data or resource is required for
  your app to function." Scanning is a convenience on top of pasting, so it is plainly not required
  for the app to function.
- Saying no leaves **the non-QR version**: the paste field. Nothing is taken away by refusing.
- A setting in the relevant area turns scanning on later, so a no is not permanent and does not
  send somebody to Settings to undo.

**The usage description** follows Apple's rule for the purpose string: "a brief, complete sentence
that's straightforward, specific, and easy to understand. Use sentence case, avoid passive voice,
and include a period at the end." It says what the camera is read for — an invite code — and nothing
else, because nothing else is true.

**What it costs.** A permission the app did not previously need, and a review question to answer. The
ask-first shape spends one extra tap to avoid spending the system's single permission prompt on
somebody who did not want the feature.

#### How the ask and the HIG's pre-alert rules both hold

`RULED` — Griff, 2026-09-16: "I like the camera shape. Once they allow camera access once, it
should save the setting, which defaults to off so it asks. That setting should live in an appropriate
collection." And, asked separately, *Not now* stops the asking.

The HIG's Privacy page, *Pre-alert screens, windows, or views*, forbids any way out of a view shown
just before a system permission prompt: "Include only one button and make it clear that it opens the
system alert", and "don't provide a way for people to leave the screen or window without viewing the
system alert — like offering an option to close or cancel." So the question and the prompt are kept
apart.

- **The setting is off until the camera has been allowed.** While nobody has answered, the join
  screen asks, under *Read the invite*: *Turn on scanning* or *Not now*.
- ***Turn on scanning* saves nothing.** It puts a **Scan** button beside Paste for this visit.
  Tapping Scan is the deliberate use, and goes to Apple's prompt with no screen of the app's in front
  of it. **Allowed** saves the setting on and opens the scanner. **Refused** saves it off, leaves
  Paste, and says the camera is off with *Open Settings*.
- ***Not now* saves it off** and the question stops.
- **The switch lives in Behavior** — *Scan invites with the camera*, beside Haptics and Help on
  every screen, because the page is "small things the app does as you use it", each this device's
  alone, and a camera permission is per device. Turning it on asks Apple if nobody has, and only
  stays on if the camera is allowed.
- A device that cannot run the scanner is never asked and shows no switch. A simulator is treated as
  able to, so the question can be seen on the rig; scanning there says the device cannot scan and
  changes nothing.

**What cannot be undone in the app.** A no given to Apple's prompt is Apple's to change, in the
Settings app, and the app says so.

**What it costs.** Two taps to the first scan rather than one.

**Sibling, fixed 2026-09-16.** The notification explainer is a pre-alert. It already had one button;
it could still be swiped away, which it no longer can.

### A disabled button keeps the system's look

`RULED` — Griff, 2026-09-16: keep Apple's look.

Apple's accessibility audit measured the disabled *Read the invite* — the system's
`.glassProminent` in its disabled state — at **1.70:1**, label on fill. The design record said a
disabled button's label still clears the floor; that described a board, not the build. WCAG 2.2 gives
text "that are part of an inactive user interface component" no contrast requirement, and
repainting a system control's disabled state is a departure from native-first. The record is
corrected rather than the control.

**What it costs.** Apple's audit will go on flagging every disabled prominent button.

### The accent retint fades, and the tab bar leads it

`RULED` — Griff, 2026-09-16: keep the fade.

The accent is set inside one 0.2s `withAnimation`. Recorded frame by frame, everything the app draws
crosses together; the tab bar iOS draws takes the new tint on the first frame, about 85ms ahead,
because a SwiftUI transaction does not reach it. The alternative was no fade at all, so every surface
changes on one frame.

### Secondary actions are bordered, with a label darker than their tint

`RULED` — Griff, 2026-09-16: "Just do the keep-the-hierarchy option."

**What it replaces.** Every secondary action — *I have an invite*, *Make a room*, *Not now* twice,
*Not for now*, *Not for me* — used Liquid Glass, whose near-white capsule measured **1.10:1** against
the screen. Apple's accessibility audit flagged it on all eight accents, including Monochrome, whose
label measured 10.59:1: the label was never the problem.

**Two options were built, screenshotted and measured before choosing.** Filled — the same as the
primary action — passed on both counts but made the two actions identical, against the HIG: "use a
more prominent button style for that option and a less prominent style for the remaining ones."
The system's bordered style kept the hierarchy, but colored the label with its own tint, and teal on
a teal tint measured **3.86:1** — the HIG's other warning, "Avoid applying a similar color to button
labels and content layer backgrounds."

**What was chosen:** bordered, with the label moved darker in light mode and lighter in dark until it
reads at 4.8:1 on the capsule (`Palette.secondaryActionLabel`). Measured on the rig in light, with
verdigris: **5.68:1**. The system does not document the bordered style's fill opacity — about 0.17
was measured — so the label is required to pass across a range of tints on both grounds a secondary
action sits on, for every accent, and to stay recognizably the accent rather than going gray.

**This leaves Liquid Glass for secondary actions**, deliberately. It is changed in the one shared
style rather than per button, because a single bordered button among five glass ones would be the
inconsistency the HIG's hierarchy rule is about.

### What stays a fixed size when text grows

`PROPOSED` — Claude, 2026-09-16, in the Dynamic Type pass.

The HIG, *Typography ▸ Supporting Dynamic Type*, read that day: "Make sure your app's layout adapts
to all font sizes", "Increase the size of meaningful interface icons as font size increases", and
"Keep text truncation to a minimum." Everything that carries meaning now scales. These do not:

- **Avatar initials.** A disc of fixed diameter with a letter or two in it, beside the person's or
  room's name in text that does scale, and hidden from VoiceOver. Growing the disc moves every row,
  bubble run and header that places things against it, for a picture of a name that is already
  written out beside it.
- **The tapback bar and the reaction chips on a bubble.** Placed by offsets from the bubble's corner
  and a bar of fixed height; the reactions are also listed, at a scaling size, in the reaction list
  tapping them opens.
- **Decorative badges and diagrams** — the pencil on an avatar, the miniature inbox layout, the large
  glyph above an explanation — all hidden from VoiceOver or accompanied by scaling text.
- **Anything iOS draws in a bar.** Navigation titles, toolbar buttons and the tab bar keep their
  size; iOS gives them the Large Content Viewer, and this app names the icon-only buttons in it.

**What it costs.** Somebody at an accessibility size sees small initials and small reaction chips.
The name and the reactions are available at full size one step away.

### A spinner is a claim, and it has to stop when the work does

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

`settleRegistration` is bounded — twenty attempts, about six seconds — and at the end of the bound it
*holds*: a device whose Keychain is empty and whose account CloudKit says is occupied stays put
rather than offering to make a second member. That refusal is right. What was wrong is what the app
drew while it held: a turning spinner over "Checking Keychain for existing registration.", with
nothing checking. A real phone sat in it indefinitely on 2026-09-03.

So the bounded wait now ends in a state that names its own outcome — `registrationStalled`, carrying
which of the four ways it got there — and a screen that says what happened and offers to ask again.
The rule about never overstating covers a spinner exactly as it covers a sentence.

**The screen stopping and the looking stopping are different things**, kept apart on purpose. The
recheck ladder still runs on a backoff, so a key that lands a minute later still rescues the device;
the screen says so, and that sentence is true because `recheckForSyncedIdentity` covers the new
state. Leaving it out would have re-created the defect that ladder was written for — it once read
`where state == .needsIdentity`, the one state a waiting device could not be in, so nothing ever
looked again.

Not `.failed`, for that same reason: `.failed` is a dead end by design, and routing here through it
would break the ordinary healthy case — a second device that opened before iCloud Keychain finished —
in order to describe the broken one.

**Cost:** three states where there were two, and a `RegistrationStall` to keep in step with the four
things that can stop the check. A fifth reason means a fifth sentence, and the compiler will say so.

**What would change it:** a signal from iCloud Keychain that an identity arrived. There is none, which
is why any of this exists.

### A wait must be able to end by itself

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Any screen the app can enter and not leave is a hang, whatever it says while waiting. Where the app
holds — for a key, for a peer, for a sync — something must keep looking, and the thing that keeps
looking must cover the state the app is actually in.

This is written down because it failed in the least visible way: the recheck ladder for a device
waiting on its identity was guarded `where state == .needsIdentity`, and a device in that situation
holds at `.checkingForRegistration`. The guard read plausibly, the code compiled, the tests passed,
and no rung ever ran. The screen said "Checking Keychain" for as long as anybody was willing to look
at it.

The correction is not a button. An escape from that particular wait can only be "create a second
member" or "erase this account", and neither is a decision to put in front of somebody who has been
staring at a spinner — the first is the silent corruption the wait exists to prevent, and the second
is irreversible. The correction is that the waiting is bounded by something that keeps looking, and
that a signal which cannot resolve is treated as a bug in the signal.

### Silence is a claim, and usually the wrong one

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

Drawing nothing is not neutral. A state that renders as absence tells the member *nothing happened*,
and when something did happen — or is waiting to — that is a lie the app is telling by omission.

Both halves of "I sent a message and it disappeared" were this. The message was on screen but below
the fold, and the message had been stored but had nobody to go to; in each case the app's answer was
to show nothing, and in each case the member correctly read that as failure.

So: a state that **cannot resolve on its own** must be drawn. `pending` may stay invisible because it
lasts seconds and ends by itself. `noRecipients` and `notReported` are drawn because they can last
days and end only when somebody else does something. The test is not how important the state is, it
is whether waiting quietly will ever stop.

### A failure the member could act on is reported to the member

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

`try?` is right where the alternative is worse than the loss — a bell that could not be rung costs a
banner, not a message. It is wrong where the thing lost is **history**, and that is where it was
being used.

`take(_:)` integrates a sibling's entries into the live replica, draws them, and then wrote them to
disk with `try?`. A failed write there means the member watches their history arrive and disappear
on the next launch.

Still not thrown: the alternative on that path is refusing entries this device has already verified.
It is **counted and said** instead. `IntegrityReport.writesFailed` is what `IntegrityView` reads, and
that screen now offers the one thing the member can act on — the entries are in memory *now*, so
freeing space still saves them.

**And every field the report counts is a field it admits to.** `feedsFromOtherMembers` was counted,
documented as "worth knowing about if it happens", and left out of `isClean` *and* off the screen —
so the one condition meaning two members share one Apple Account was reported by nothing, under a row
reading "Nothing wrong". `SilentFailureTests` holds both halves.

**Cost:** an integrity screen that can now be non-clean for a reason the member cannot fix
themselves. That is the right direction: the honesty rule would rather they see something wrong than a
convincingly empty screen.

### A post that did not go says so, the way a message does

`PROPOSED` — Claude, 2026-09-14, found while splitting `RootView`.

A room's composer takes `(String) async -> String?` and draws the reason it comes back with. The
Outpost composer took `(String) async -> Void`, so there was nowhere for a reason to go — and
`PostComposerView.post()` made it worse: on the text-only path it started the write in a detached
`Task` and dismissed the sheet in the same breath. A post that failed to append closed the composer,
lost the words and said nothing.

The photo path in the same function already did the right thing: wait, show the failure, keep the
sheet open. The text path now does what the photo path does, and `onPost` returns a reason all the
way up through `OutpostView` and `OutpostFeedView`, so the compiler will not let a caller drop it
again.

The cost is that the sheet no longer closes optimistically. It is a local log append, not a round
trip, so the wait is a disk write — and the alternative is the app telling a member their post went
out when it did not, which is the one thing this product is not allowed to do.

**The same shape twice more, found by the compiler on 2026-09-14.** A clean build's
`result of call to 'reporting' is unused` named three seams that could not carry a reason:

- **Renaming yourself** was the post bug exactly: `RenameMemberView.save()` called `dismiss()` and
  started the write in a detached `Task` in the same breath. It waits now, shows the reason in the
  section's own footer, and only dismisses when the write succeeded.
- **The blurb** is a debounced autosave, so there is no sheet to hold open; the reason goes in the
  footer that already counts the characters, in `palette.destructive`.
- **The Outpost picture** has no member-facing seam above it — `reporting` logs and there is nowhere
  to draw. That discard is now written as `_ =`, so the compiler stops offering it as a question
  somebody has to re-answer.

`reporting` returns the sentence for a reason. Anywhere its result is dropped, a member is being
told something worked on the strength of nothing.

## Accessibility and color

### An accessibility floor is measured against what is actually behind the thing

**PROPOSED by Claude** — a default, not a constraint. He has not ruled on this.

A contrast pair is only meaningful if it is the pair a reader sees. It is easy to measure a control
against the page and call it audited, when a fill sits between them.

Found by adding coverage rather than by looking: a field's border cleared 3:1 against the surface and
**2.77:1 against the field's own fill**, which is the only surface it is ever drawn on. The same
mistake in the other direction produced Ruling 13 — white measured against the accent rather than
against the fill that carries it.

So: when a token is introduced that sits *between* two others, the audit gains the new pair in the
same change. A swatch that exists only so the audit can composite it is not dead code, and deleting
it removes a guarantee rather than a line.

### A color is measured on every ground it is drawn on, in both appearances

`PROPOSED` by Claude, 2026-09-17 — a default, not a constraint. The light-mode criterion asked for
every treatment inferred during implementation to be checked against the rules. The rule applied:
every color a view draws either comes from `Palette`, where it is measured, or is written down here.
The sweep read every color a view picked for itself and measured every pairing `ContrastAuditTests`
did not already hold. What it changed:

- **Increase Contrast raised a fill to a slab.** Fills used the text rule, which moves an opacity
  halfway to one, so a card's 14% gray became 57% and gray, accent and red text on it failed — tertiary
  text on a card measured 4.02:1. iOS itself adds **0.08** to every fill, measured on the 26.5 runtime
  by resolving its colors under `UIAccessibilityContrast.high`:

  | Fill | Light | Light, high | Dark | Dark, high |
  |---|---|---|---|---|
  | `systemFill` | 0.20 | 0.28 | 0.36 | 0.44 |
  | `secondarySystemFill` | 0.16 | 0.24 | 0.32 | 0.40 |
  | `tertiarySystemFill` | 0.12 | 0.20 | 0.24 | 0.32 |
  | `quaternarySystemFill` | 0.08 | 0.16 | 0.18 | 0.26 |

  The app's fills now take the same step. Text grays keep their own rule.
- **The destructive red was one value for both appearances**, `#D1382F`, and measured 3.50:1 on a
  dark grouped row and 4.36:1 on the light background. It is now computed like the other labels: iOS's
  dark red `#FF4245` lightened, or `#D1382F` darkened, until it reads on the background, a row, an
  elevated surface and a card over each — `#B83129` light, `#FF595B` dark, darker and lighter again
  with Increase Contrast. A red button with white words on it uses `destructiveFill`, which did not
  change; the one place drawing white on the text red (the clip-trim capsule) was moved to it. A
  bordered red button's words take `destructiveActionLabel`, the same arrangement the accent's bordered
  buttons already had.
- **An unlit delivery mark was the accent at 55%**, which measured 2.17–2.95:1 against the 3:1 a
  graphic that carries meaning needs. `unlitMark` starts at 55% and rises until it clears 3:1 on every
  ground: 55–75% depending on the accent. It stays lighter than a lit mark, and the shapes still differ.
- **Four filled buttons were filled with the plain accent** — *Continue* after a device joins, *Get
  started*, and *Review* and *Confirmed* on the in-conversation cards. In dark mode every accent
  carries black text best, so white on it failed. They are filled with `accentFill`, as every other
  filled button is.
- **The accent as words on a card** — *Later*, *Change* — measured 4.11:1 on cobalt in light. Those
  buttons take `secondaryActionLabel`, which already reads on tinted grounds.
- **The anonymous face drew a white symbol on the accent**, 1.27:1 on monochrome in dark. It takes
  `textOnAccent`.
- **"Their decision" on a card was quaternary gray**, 4.31:1 in light; it is tertiary.
- **White words sat on regular Liquid Glass over a photo** — the play button and length on a clip,
  *Sensitive photo*, *Could not load*, *No longer available*. Regular glass goes near-white in light
  mode (a glass capsule measured 1.10:1 against a light screen on 2026-09-16), so the words vanished
  over a bright picture. Apple's Materials page: "Use this variant for components that float above
  media backgrounds — such as photos and videos", with a dark dimming layer beneath when the content is
  bright ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials)). They
  use the clear variant over a black layer now, as Apple's `Glass.clear` documentation shows. **The
  layer is 55%, not the 35% the page suggests**: 55% is what keeps white words at 4.5:1 over a white
  photo (4.76:1 measured; 35% gives 2.4:1). Glass has no fixed value, so the dimming is the part that
  is measured. The loading spinner lost its white tint and takes the system's.

What stays, deliberately:

- **Black and white over a photo in the composer and the crop screen** — the clip length, the remove
  button, the trim capsule, the crop frame. They sit on the picture, not on the app, so the appearance
  does not reach them. The two carrying words were on 45% black, 3.35:1 over a white picture; they
  take the same 55% as the glass.
- **The full-screen photo viewer is black in both appearances**, so a picture is judged against the
  same ground whatever the phone is set to. What it costs: in light mode it is the one screen that does
  not follow the appearance.
- **The invite's QR code sits on a white card in dark mode too**, because a scanner needs the light
  quiet zone.
- **A settings tile for a device is `Color.gray`**, iOS's own gray, with a white symbol: 3.26:1, over
  the 3:1 a graphic needs, and what Settings itself draws.
- **Quaternary gray on a chip** stays where it is an illustration — the inbox-arrangement miniatures —
  or a disabled control in the post composer, both of which WCAG exempts.

### Five accents move off the board so they can be read as text

`RULED` — Griff, 2026-09-16: "Darken the Yesterday, lighten the disk, darken our global teal. Check
all accents."

**What started it.** Apple's accessibility audit failed *I have an invite* on contrast. Measured in
the audit's own screenshot, the button's teal rendered at **4.21:1** on its pale capsule. The HIG,
read the same day, is explicit about the bar: "Accessibility Inspector uses the following values from
WCAG Level AA … Up to 17 pts, All [weights], 4.5:1."

**Why nobody had caught it.** The contrast suite measured text *on* the accent and text on the
accent's tint, and never the accent *as* text. It is drawn as text all over the app — bordered
buttons, links, the selected tab. Adding that one check found five failures at once:

| Accent | Appearance | Was | Worst ratio | Now | Worst ratio |
|---|---|---|---|---|---|
| Verdigris (default) | light | `#17877C` | 3.93 | `#14766C` | 4.90 |
| Signal Amber | light | `#B06E12` | 3.70 | `#945D0F` | 4.91 |
| Olive Drab | light | `#6C7F24` | 4.01 | `#607120` | 4.85 |
| Cobalt | dark | `#3E7BFA` | 4.39 | `#4D85FA` | 4.90 |
| Oxblood | dark | `#C6555A` | 3.93 | `#CE6C70` | 4.86 |

Each moved by the smallest hue-preserving lightness step that clears 4.5:1 on every surface with a
margin, darker in light mode and lighter in dark. The other eleven pairs already passed and did not
move. **This is a departure from the design board**, recorded because `AccentTests` pinned the
board's values and now pins these.

**One visible side effect.** Darkening the three light accents made white the stronger foreground on
them, so a selected toggle in *Edit Rooms List* and your own swatch in the accent picker now carry
white text rather than black. That is `textOnAccentSwatch` choosing the stronger pair, as designed.

**The other two changes, scoped to what was named.** The room-row time gets its own `timestampText`,
darker in light mode only (6.42:1 → 7.76:1; dark was already 9.05:1). The avatar disc gets its own
`avatarFill`, lighter in light mode only — in dark a lighter disc moves toward the light letter and
lowers the contrast (6.86:1 down to 6.09:1). It stays translucent rather than white, because the same
avatar sits on white grouped rows in settings, where a white disc would stop reading as a shape.
Neither touches `secondaryText` or `neutralFill`, which color much else.

**What Apple's own audit said afterwards**, run on every accent in both appearances
(`AccentContrastAuditTests`, one method per accent, `-theme.accent` at launch), and measured in the
audit's own screenshots rather than read off the summary:

- **Dark mode: every accent-driven failure is gone.** *I have an invite* and *Send a Solo* no longer
  appear on any accent.
- **The room time and the avatar initial rendered as intended and are still flagged.** *Yesterday*
  went from 6.47:1 to **7.93:1** — past WCAG AAA's 7:1 — and *K* from 5.61:1 to 5.97:1. No documented
  standard fails text at 7.93:1, so darkening further would be chasing the audit rather than making
  anything more readable, and has not been done.
- **In light mode, *I have an invite* is flagged on all eight accents, Monochrome included.** Its text
  measured **10.59:1** on Monochrome and **5.26:1** on the new verdigris, up from 4.21:1 — so the teal
  change worked for the text and the flag is not about the accent. The one low-contrast pair inside
  that element is the button's near-white glass capsule against the near-white screen, **1.15:1**,
  identical on every accent. The documentation read does not say the audit measures that, so this is
  a measurement, not a claim about the algorithm.
- *Send a Solo* was flagged on Cobalt and Aubergine in light mode, at 5.43:1 white on the fill.
- *Behavior* and the accent-name row are flagged on every accent in both appearances; both are rows
  underneath the floating tab bar when the audit reaches them.

**The pattern, stated once:** the audit flags elements measuring between 5.26:1 and 10.59:1 against
a documented bar of 4.5:1. Every change here was verified by measurement; nothing further is being
changed to satisfy a threshold the documentation does not describe.

### The VoiceOver walk waits for TestFlight

`RULED` — Griff, 2026-09-17: skip the walk until the app is on TestFlight; the app uses system
components everywhere, so he expects it to hold.

Every control is labeled and measured in source, Apple's audit runs on the rig, and `VoiceOverWalkTests`
lints the rendered tree. What none of those do is step through the app with VoiceOver speaking, and
on the rig that needs DeviceHub frontmost, which takes the Mac from whoever is using it. The walk is
done on a phone from the first TestFlight build instead.

**What it costs.** Reading order, grouping, and anything read twice or skipped are unheard until
then. The rig heard the first stop on each screen it tried, and every one was right.

### A view split across files declares Reduce Motion once and uses it everywhere

`PROPOSED` — Claude, 2026-09-14, forced by splitting `ConversationView`.

The motion lint asks that a file which animates either consults `accessibilityReduceMotion` or says
on the line that what it animates is a cross-fade. It checked for the string, in that file.

An extension cannot declare an `@Environment` property, so a view split across files has exactly one
file that can satisfy the old check — and the files holding the animations are never it. The rule as
written made splitting a view impossible, which is the opposite of what it is for.

It now also accepts a file that *consults* the value as `reduceMotion ?`. Matching the use rather
than a bare name is deliberate: a local variable that happened to be called `reduceMotion` would not
excuse a file. The one animation in the composer that was excused by the old file-level rule without
consulting anything — the problem notice's fade — now consults it.

## Engineering rules

### Abuse intake is a form that refuses what it cannot hold

`RULED` — Griff, 2026-09-17, after asking how a forwarded address could be stopped from receiving
material: build the form.

> **Extended the same day.** This entry left the mailbox standing beside the form, which narrowed the
> mail path without closing it. It is closed now — see
> [Every route to a person is a form](#every-route-to-a-person-is-a-form-and-no-address-is-published).
> What stands here is the reasoning about *why* verification happens by bytes; what has changed is
> that a report is pasted rather than uploaded, and there is no longer a second route in.

**The problem.** `abuse@outpostmessaging.com` is a Squarespace forwarder. A forwarder's whole job is
to accept and relay, so it cannot refuse anything, and the only controls left are at the destination
mailbox — by which point the mail has been accepted twice and the operator has it. Deleting it then
is worse than never receiving it: § 2258A puts a reporting duty on a provider who obtains actual
knowledge, and destroying the thing is not how that duty is discharged.

**Decided: publish a form as the route, and verify by the bytes.**
`outpostmessaging.com/report` posts to `microgpt-comms` (SpringBonk, port 7088, `/cms`, `cms-db`).
The service takes the app's own report plus the reporter's words, stores the report in Postgres and
mails a formatted notification.

The upload check is over content, never the content type or the extension, because both are whatever
the browser was told to send. Strict UTF-8 with control characters refused kills an image, a PDF, an
archive and a video — a PDF matters here because it opens with readable ASCII, so a check on the
first bytes alone would pass one. What survives must then carry `AbuseReport.body`'s labelled lines:
a 64-hex fingerprint, a six-hex short code, two parseable timestamps, one of exactly two kind
phrases, and the closing assurance the app always writes.

**At least one contact field, and which one is the reporter's choice.** A report nobody can be
reached about cannot be answered or passed on with its reporter attached. Insisting on an email
address would turn a safety form into an account, which is the opposite of what the rest of the app
is for.

**What it costs, and what it does not close.** `abuse@` is still published and still a forwarder, so
somebody determined can still mail it — the form narrows the path by being the published route, it
does not close it. Closing it needs the domain's mail to move to something that can reject at SMTP,
which is Griff's call and is not this decision.

**The report is a file now**, 2026-09-17. *Save a copy* on the report screen exports the body as
plain text through a `Transferable`, named from `Branding.displayName`, the sender's short code and
the day, so a member gets the file the form asks for rather than copying text into a note. Beside it
is *Open the report form*, from `APP_REPORT_FORM_URL` in the xcconfig — the URL carries the product's
name, so it belongs with the addresses rather than in Swift. Seen on the rig: the share sheet offers
*Outpost report 038E3D 2026-09-17* with Save to Files.

**Mail stays the first action on the report screen, and the form is beside it.** The form is the
better intake — it refuses material a mailbox cannot, and a report through it lands in Postgres
rather than in a third-party mailbox, which is what § 2258A(h)(3) actually asks for. It is
nonetheless *more work*: save a file, open a browser, upload. A member's own report is plain text by
construction and carries nothing dangerous, so routing a distressed person through three extra steps
buys the operator's record-keeping and costs the reporter. The risk the form answers is a third party
mailing a picture directly, and that person is not on this screen. So: *Continue in Mail* stays
prominent, *Save a copy* and *Open the report form* sit under it, and the vault answers the
record-keeping either way.

**The format is pinned on both sides, because nothing else can hold it.** The parser that reads a
report lives in a different repository, so no compiler can keep the two in step. `AbuseReport.body`'s
shape is asserted from the app's side — one of each label, 64 lowercase hex, six uppercase hex,
ISO-8601 times, one of two kind phrases — and `ReportParserTest` asserts the same grammar from the
other, with its fixture written from the app's real output. Change the wording and both fail, which
is the signal rather than a silent widening of what the intake accepts.

**Where the material is not.** There is no column for it and no code path to one. The app's report
names a message by a one-way fingerprint and carries none of its content, and the intake refuses
everything that is not that report — so the database holds an account of an event rather than the
thing complained about, which is the whole reason the form exists.

### The marketing site is photographed, not drawn

**PROPOSED** — Claude chose this on 2026-09-17. Griff asked for the site's designs to be redone
because they were not accurate to the app; this is how.

The site's screens came from a Claude Design export that was retired on 2026-08-18. Eighty-four
boards, and by September they described a Mac window, an app with no media, a six-character phrase
and a pairing flow that had been deleted. Nothing kept them honest, because a drawing does not fail
when the code changes.

So the site takes photographs instead. `CarpenterUI/Screens/SiteShots/SiteShotView.swift` — the
whole file `#if DEBUG` — answers `--site-shot <name>` and draws **one real screen** with the preview
fixtures, and `outpost-site/scripts/capture-shots.mjs` drives it on a simulator: ten screens, eight
accents, light and dark, clean status bar, straight to AVIF and a regenerated manifest.

**What it costs.** A screen only reaches the site if it has a case in the `SiteShot` enum and an
entry in the script's `SCREENS`, so adding one is two edits rather than a re-export. The host and its
launch argument are in the debug binary, which is why `site-shot` is on `check-release-leaves.sh`.
And the site can only show what the fixtures can produce.

**What would change it.** Nothing short of the app no longer building for a simulator. A redrawn
screen is a claim nobody checks; a screenshot is a claim that fails loudly.

**Which fixtures, and why not the demo conversation.** The debug `DemoConversation` uses DC and Teen
Titans character names, which cannot go on a public site. `Fixtures` — the airship club, the Carcosa
names — was written for previews and is neutral, so it is what the host draws.

### A Focus filter's preview switch reaches a post, and its room list does not

`PROPOSED` — Claude, 2026-09-17, found while making the notification extension's decisions testable.

`RoomsFocusFilter` offers two things: *Only these rooms*, and *Show what was said*. The extension
applied both to a message and neither to a post, so a Focus set to hide what was said still put a
post's body on the lock screen.

**Decided: the preview switch applies to a post; the room list does not.** The intent's own
description is "Which rooms may notify while this Focus is on, and whether **banners** show what was
said" — not whether room banners do. A post's body is what was said. The room list is a different
claim: a post belongs to no room, so a list of rooms has nothing to say about it, and letting an
empty-but-set list silence every post would silence more than the member asked for.

`FocusFilter.levelForAPost(own:)` is the one line that says so, beside `level(for:own:)`, both built
on the same private `withoutPreviews`.

**What it costs.** A member who turns a Focus on expecting silence still gets post banners, named but
wordless. The way to stop those is the Outposts notification setting, which is where the choice about
*which* posts notify already lives. Nothing here can distinguish "quiet because of this Focus" from
"quiet always", so this is the smaller of two wrong answers rather than a clean one.

### The number on the app icon is one property, and it obeys the switches

`PROPOSED` — Claude, 2026-09-17.

`BadgeCount.of(_:)` counted rooms with something unread. Always. It never read `BadgeChoices`, which
the member sets under Notifications, and it never counted Outposts at all.

`BadgeMeaningLine` states in the present tense what the number counts, and **all four of its
sentences were false**:

| Setting | What the app told the member | What the number was |
|---|---|---|
| Both | "counts unread conversations **and Outposts with something new**" | conversations only |
| Outposts only | "counts Outposts with something new, **and nothing else**" | conversations only — exactly backwards |
| Messages only | "counts unread conversations, and nothing else" | true, by accident |
| Off | "Your app icon shows **no number at all**" | the number stayed |

So two switches on the Notifications screen were dead controls, which is the defect class
`CLAUDE.md` already names three of, and the copy beside them was a claim the build did not honor.

**Decided:** `BadgeCount.of(_:outposts:choices:)` adds the two counts the switches ask for, and
`AppSession.badgeNumber` is the single property both the app and the notification extension read —
they had `BadgeCount.of(session.rooms)` written out separately, which is the two-constructions trap
waiting for one of them to be updated.

**Measured on the rig, 2026-09-17**, because this is a number a member looks at more than any other
part of the app: Quad with one unread room showed **1** on the icon; turning *Show on the app icon*
off under Messaging cleared it to nothing while the message stayed unread, and the sentence under the
switch changed itself to the Outposts-only wording. Turning it back on restored both.

**What it costs.** `badgeNumber` calls `outpostAuthorsWithUnseen()`, which walks the projection's
Outpost authors. `RootView` already called it on every render to draw the rail, so this is a second
walk on a path that had one, not a new cost on a quiet path. `ProjectionCostTests` still passes.

### What the notification extension decides is one function, and it is tested

`PROPOSED` — Claude, 2026-09-17.

The extension used to decide what a banner was inside `whatArrived(_:)`, a nested function inside a
static method inside `NotificationService`, in a target `swift test` does not run. It made five real
decisions — which of a post, a restore ask and a message wins when more than one arrives in the same
round; whether the thing found is actually new; which rung a message takes; whether to deliver
passively; and whether to attach the sender as a communication notification — and not one of them
could be reached by a test.

`WhatArrived.since(_:post:ask:message:in:)` in `CarpenterApp` is that logic as a pure function over
value types, with the filesystem and the session behind closures. The extension fetches the
sender's picture from the id it returns and does nothing else.

**The rule worth having a test for:** a banner never carries a sender unless its own words name one.
An `INSendMessageIntent` makes iOS draw the banner as a communication notification — the person's
name and face, on the lock screen — so attaching one at a rung that withholds the sender would
disclose exactly what the rung exists to withhold. The code was already right; nothing had ever
checked it, and `aSenderIsOnlyAttachedWhenItIsNamed` walks every rung for both a message and a post.
Mutation-checked by dropping the `showsSender` guard, which the test catches.

**What it costs.** `IncomingMessage`, `IncomingPost` and `RestoreAsk` gained public initialisers so a
test can build one. They are read-only value types, so the cost is API surface rather than a new way
to be wrong. What is still not proved is delivery: no push has reached the extension on this rig, and
that is on [Proofs a rig cannot run](proofs-a-rig-cannot-run.md).

### The kit takes no framework dependency

**FACT** — a property of the platform or the protocol, not a choice anybody made.

Everything platform-shaped sits behind a protocol. This is what makes the logic testable without an
account — and it carries a specific hazard that has cost this project more than once.

**A fake that is easier than the real thing proves nothing.** The in-memory mailbox moved a whole
packet by value, so a field missing from the CloudKit mapping was invisible; epoch grants were
silently stripped over a real account while the entire suite stayed green. It now goes through the
same wire mapping the real transport uses, and counts every server operation rather than only writes.

**The rule this leaves behind:** where a fake diverges from the real implementation is where the next
defect will live. Close it in the fake, not in a comment.

### The fold is kept, and the state it is derived from says when it changes

**FACT** — a property of the platform or the protocol, not a choice anybody made.

`Projection` is the fold of the whole log — `CausalOrder.sorted` over every entry, then a render
pass — and every screen is drawn from it. It was a computed property, so each *read* paid for one.
Measured, on a six-room account: **fourteen folds of the entire log to send one message**, on the
path the conversation screen runs every five seconds. Four reads with nothing written between them
cost four folds. `refresh()` was the worst of it — it folded for its own summaries, again inside
`introduceEstablishedMembers`, and then twice more per room.

It is kept now, and invalidated by `didSet` on the two stored properties it derives from
(`replica`, `chains`) rather than by call sites remembering. Mutating a struct property — including
through a mutating method like `replica.integrate(_:)` — is a get-modify-set, so that fires on every
mutation there is. The same signal drops a cached entry index that `roster(of:)` had been rebuilding
per call.

Sending one message into a six-room account now folds once. The package suite, which does almost
nothing but write and read, went from ~19.5s to ~12.4s.

**The same index closed a worse one.** `openPayload` — the function that reopens an entry so a
receipt or a notice can be read out of it — did `replica.allEntries.first(where:)`, which builds a
fresh array of the member's whole history and then walks it. It is called *once per entry opened*:
once per read receipt in `readPositions`, once per policy in `reportingMembers`, once per notice in
a transcript. Drawing one screen was quadratic in the length of the log, in allocations as much as
in comparisons. Measured on a 167-entry log with sixty read receipts in it: twenty reads of
`messages(in:)` took **4.21s before and 0.19s after** — 211ms to 9.7ms each, and the gap widens with
the log. Both callers now take one opener over the kept index.

**Cost:** a cache, and a stale fold would be the worst possible failure of it — a member's own
message not appearing. `ProjectionCostTests` holds both halves: the fold count, *and* that a write
is visible to the next read.

**What would change it:** nothing foreseeable. If a third piece of state ever feeds the fold, it
needs the same `didSet`, and the tests will not notice on their own.

### A nil check does not survive an `await`, and an actor is reentrant

**FACT** — a property of the platform or the protocol, not a choice anybody made.

`guard engine == nil else { return }`, two `await`s, then `engine = …` at the end. Between the check
and the assignment the actor is free — that is what an `await` means — so a second caller walks
straight past a check that is about to stop being true, and both bring the whole thing up. For
`CloudKitEntrySync` that is two `CKSyncEngine`s, two delegates, two subscription saves, and
`self.engine` overwritten: the first engine orphaned but alive, still holding a delegate that calls
back into the actor.

The callers are concurrent in the ordinary case. `AppSession.syncDevices` starts the engine in one
task while `AppRootView`'s first `syncNow()` reaches `refresh()` in another.

The shape that works is to hold the in-flight bring-up as a `Task` and have the second caller
**await it** rather than skip. That way "start returned" means "the engine is up" for every caller,
which is what `send` and `refresh` both assume on their next line. A bare `isStarting` flag would
make the second caller return early and then use an engine that is not there yet.

**Found by reading, not by measurement.** The device log shows `subscribed for priority pushes`
twice per launch, which looks like the symptom and is not — `start()` saves the subscription
deliberately at both ends of bring-up. What is certain is the shape, and the shape is a race whether
or not it has been caught happening. `Scripts/lint/reentrancy.py` fails the lint on any nil check
separated from its assignment by an `await`; a site that has thought about it says
`reentrancy considered`.

### Main-actor state is never copied across an `await`

**FACT** — a property of the platform or the protocol, not a choice anybody made.

`AppSession` is main-actor isolated, and the actor is **free** while an `async` call is suspended. So
the copy-modify-write shape — take a copy of the replica, hand it to a network call, assign it back —
is not a value-type convenience, it is a lost update with a network round trip's worth of window in
it. What ran on the actor during that window was a member pressing send: their entry went into the
live replica and onto disk, and the stale copy then took it back out of memory. Nothing threw, nothing
logged, and the entry was no longer in `unsentEntries()` either, so it was never written to the
mailbox.

What that looks like is a message that appears, disappears, and is back in its right place hours
later — because the next launch rebuilds the replica from the log, where it had been the whole time.
That last part is why it read as a delivery problem and was not one.

The fix is shape, not care: `SyncSession` fetches and opens packets in one `async` call and applies
them in a **synchronous** one, so there is no suspension point between reading the replica and writing
it. `ReplicaRaceTests` fails against the old code with exactly the two symptoms.

**Cost:** the convenience `receive(as:into:)` still has the old shape and survives for tests, whose
replicas are reached from nowhere else. Nothing in the app calls it.

### Two processes, one container

**FACT** — a property of the platform or the protocol, not a choice anybody made.

The app and the notification service extension share the log and the state file over an App Group.
The app's writes are taken under a cross-process lock. A Swift actor serializes within a process and
does nothing across two: without the lock, concurrent appends lost 118 of 200 entries and left the log
unreadable. Since 2026-09-17 the extension writes nothing at all; see
[the entry](#the-notification-extension-writes-nothing-to-the-container-it-shares).

When the App Group is unavailable, an extension's fallback directory is inside its **own** container.
That is a second private copy that is permanently behind, and it looks exactly like slowness. Both
processes log which container they resolved.

### Stored shapes are read forward, never assumed

**FACT** — a property of the platform or the protocol, not a choice anybody made.

Anything written to disk or sent between devices decodes field by field, with a default for every
field that has one. Swift's synthesised `Codable` conformance does not do this: it ignores default
values and demands every key, so **adding a property retroactively invalidates every value written
before it existed.**

This has now cost twice. The second time, a notification setting nobody had chosen yet made the
whole state file unreadable, and the app opened onto "something is wrong with this device's data"
with the identity, rooms and log all sitting intact behind it. The blast radius is the file, not the
field — one nested value fails and everything fails with it.

The rule is that a property added to a persisted or wire type comes with a line in that type's
`init(from:)`. `ForwardCompatibilityTests` enforces it without anyone having to remember: it drops
each key from a real encoding in turn and requires the rest to still decode, so the check grows with
the type instead of aging beside it.

Two failures are worth separating. A file that cannot be read strands one member until they update,
which is recoverable — nothing is overwritten, because the load failure path only sets the error
state. A packet that cannot be opened is worse: it strands the *sender's* messages on every peer
running an older build, and no amount of updating the receiver fixes it.

### The fake is held to the real mailbox's contract

`RULED 2026-09-13 by Griff`: "we need the fake to be as hard as the real thing… we should be testing
real functionality and we need to make sure everything is built as if it were the final version."

**Why there is a fake at all.** 1,305 tests ran in two minutes on 2026-09-13, with no account, no network and no
entitlements. The live CloudKit tests cost about three seconds each and need a signed-in device. That
is a speed argument and nothing else — it buys no license for the fake to be *easier*, and where it
was, it was only lying faster.

**The rules now live in one place.** `MailboxRules` in the kit holds `recordByteCeiling` and
`sweepAge`, and both `CloudKitMailbox` and `InMemoryMailbox` read them. The constant used to be
private to the CloudKit implementation, which is how the fake came to ignore it.

**Three divergences closed**, each of which had made a passing test meaningless:

- **No record ceiling.** The fake accepted a packet of any size. `SyncSession.packetByteBudget` was
  the only thing keeping packets under the ceiling and nothing checked that it was enough. The fake now
  refuses, and a test pins the budget below the ceiling. The ceiling turned out to be the app's own
  rather than CloudKit's; see
  [The record ceiling is the app's own](#the-record-ceiling-is-the-apps-own-and-cloudkit-never-asked-for-it).
- **No age on an upload.** The fake had no notion of when a record was written, so
  `sweepableAttachments` could not be exercised at all — which is how the bug above shipped.
  `InMemoryMailbox` takes a `Clock` and applies the same hour.
- **`download` ignored who a photo was for.** The fake handed the bytes to any caller; the real
  mailbox resolves a zone from the recipient's address and finds nothing. A test could have "proved"
  a stranger could collect a photo. The bytes are sealed either way, but a test that cannot tell the
  difference is the one that lets a seal slip.

**A protocol default hid a real implementation.** `MediaMailbox` had an extension default for
`sweepableAttachments`. `InMemoryMailbox`'s own method never ran — the default won at the call site,
silently, and the new test failed while the code looked right. The default is gone: every conformer
implements it, and a missing one is a compile error. Removing it immediately surfaced two conformers
that had never been considered. **Do not add a protocol extension default to this seam again** — a
default is exactly how a fake drifts from the thing it stands in for.

### Choosing what was already the default is still an answer

`PROPOSED` — Claude, 2026-09-14, found on the rig taking *Familiar and open* on a fresh account.

Several preference setters guarded on the derived value — `guard isReportingDisplaying != reports`
— and a preference that has never been set reads as its default. So taking a preset that leaves a
setting off wrote **nothing**: `toldAboutRestores`, `holdsHistoryForRestores` and
`reportsDisplaying` were all still absent after the check-up said they had been decided.

That matters because preferences are `Stamped` and merge across the member's own devices by stamp.
An absent value loses every merge against a device that has one — so a member who takes *Familiar
and open* on a new phone has that choice silently overruled by an older *Locked down* on a device
they still own. "Never answered" and "deliberately off" have to be different things.

The setters now write when there is no stamp yet, even if the value matches, and still skip a
genuine no-op so a check-up does not churn the feed. `setRequiresSoloCheck` never had the guard,
which is why it was the only one on disk after a preset — the inconsistency was the clue.

**Three more of the same, found on 2026-09-14 by walking all sixteen questions on an erased
device and then reading the file.** Fixing the nine single setters was not the whole job:

- `AppRootView.setShowsPhotoOnOutpost` is a *wrapper* around the fixed setter, and it carried the
  old guard — so it returned before the session was ever asked. A fixed setter is no use behind an
  unfixed caller.
- `AppSession.setFocusSharing` takes the whole `FocusSharing` struct and compared each field against
  its derived value, with an outer `guard before != wanted` on top. Answering "leave it as it is"
  wrote neither `sharesFocus` nor `showsOthersFocus`.
- `setNotificationLevel` and `setMuted(_:for:)` had the same shape one screen over, and were fixed
  with it.

`hasAnswered` is generic over `Stamped<Value>` now, and `hasAnsweredMuted(_:)` answers the same
question for a room. Measured after the fix, on an erased device driven through the whole check-up:
all fourteen settings on disk, none missing.

### One writer for the state file, and it reads the state when its turn comes

`PROPOSED` — Claude, 2026-09-14, found reading `updateOrganisation` during the big review.

Twenty-two places wrote `PersistedState` with `try await storage.documents.save(persisted)`. Twenty-one
of them `await` on the main actor, so they are ordered against each other. The twenty-second —
rearranging the rooms list, which is called from a drag handler and cannot be `async` — captured the
whole state and handed the copy to a detached `Task`.

That is the copy-modify-write trap one layer down. The value handed to `save` is a snapshot taken
before the call; the store's own `await` frees the main actor; and anything written in that window —
a sync round's frontier, an acknowledgment, a preference — is overwritten when the older write
lands. Measured with a store that holds its first write: the nickname set during the window was gone
from the file.

Every site now calls `saveState()`, which chains each write behind the one before it and reads
`persisted` **when its turn comes** rather than when it was asked for. So the last write always
carries the newest state, whatever order the callers arrived in. `ArrangingRoomsDoesNotRollBackTests`
is the guard, and it fails three times out of three without the chain.

The cost is that a save waits for the save before it, which on a file this size is nothing, and that
a failing write now delays the next one rather than racing it.

### Every route to a person is a form, and no address is published

`RULED` — Griff, 2026-09-17: "I delete the abuse email. You can only submit through the site."

`abuse@` and `info@` are gone from the site and from the app. The app writes a report, copies it,
and opens `outpostmessaging.com/report` in the member's browser after telling them that is what will
happen. The website's eleven `mailto:` links now point at `/contact`, which is a form with a
product, a category, a title, a description and an optional email address.

**Why a form beats a mailbox, stated once.** A mailbox has to receive whatever is sent to it and
decide afterwards; a form decides first. `ReportParser` reads the bytes — strict UTF-8, no control
characters, then the app's own labelled grammar — and there is no file input anywhere on either
page, so an image cannot be offered in the first place. That matters legally and not only
practically: under § 2258A, receiving material and then deleting it is a worse position than never
having received it.

**Why the app stopped composing mail.** It never sent anything itself and never will, but a mail
composer is a mailbox by another route, and keeping one would have meant keeping a published address
for it to open. The confirmation before leaving the app is not decoration — a member who taps
*Report* on a message they were upset by should be told they are about to be handed to Safari,
rather than discovering it.

**What it costs, and this is real.** Somebody who cannot use a web form has no way through. The
phone number on `/support` and `/accessibility` is the deliberate exception and is the reason those
two pages keep it. App Store Connect still wants a contact address, and that one is Griff's own and
has never been the app's.

**What the app still keeps.** *Save a copy* and *Copy the report* both remain, under a heading that
now says *Keep it yourself* — a report names a message by a fingerprint, and the fingerprint only
means anything while the message is still on the reporter's device.

### A category decides where a report goes, and the routing is published first

`RULED` — Griff, 2026-09-17, for the category; `PROPOSED` — Claude, same day, for publishing the
routing: "Would it be smart to include a button on the form which shows links … showing
outpostmessaging.com/resources".

Yes, and not as a button. A disclosure widget that reveals a link is two taps to reach one, and a
form is the worst place to hide something. The category selector carries one sentence about the
category chosen and a link to `/resources`, which opens in a new tab so the half-filled form
survives.

`/resources` lists every category with who a report of that kind is taken to and what is left here
afterwards. Publishing it is worth it for a reason beyond transparency: nearly every organization on
it can be contacted by the reporter directly, today, without us, and several of them can do more
with the reporter's own account than with a referral.

**What it costs.** It is also a map for somebody working out which category attracts the most
attention. That is a real cost and it is smaller than the alternative, which is a reporter who
cannot find out where their own report went.

**Three sentences on that page exist because the alternative was untrue.** A report of sexual content
involving a child is *held for a year*, not deleted on handling — 18 U.S.C. 2258A(h), as amended by
the REPORT Act in 2024, and the ninety days that number used to be is why it is worth writing the
year down. "Deleted" means gone from the database and gone from the nightly backups up to three days
later, because `pg_dumpall` keeps three. And a report is passed to an authority *where it belongs
there*, not always — "all reports will be passed along" would have promised every question about a
display name to the FBI.

### The Mac icon is an Icon Composer document, and iOS keeps its own

`PROPOSED` — Claude, 2026-09-18.

The Mac was compiling the iOS icon set's 1024-point square: opaque, full-bleed, hard-cornered. iOS
masks that shape itself and macOS does not, so the Dock was handed a square. `AppIconMac.icon` is an
Icon Composer document — the same full mark, framed the way `make-app-icons.py` frames it, on white
with the near-black glyph, and a dark appearance that inverts both. It is the format this Xcode
compiles into a correctly shaped macOS icon, and the dark appearance is the mechanism macOS actually
has, which the ticket asked for by name.

It is scoped with `ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]`. iOS keeps `AppIcon` and its 26
alternates untouched, because they were approved and nothing about iOS was wrong.

**How it was checked.** Rendered with `ictool` for both appearances, and extracted back out of the
built `.icns` at 16, 32, 128 and 256: transparent corners, a margin all round, no dark ring against
a dark ground. **Not** seen in the Dock itself — the display was asleep.

**What it costs.** At 16 points — Finder's list view — the full mark is grey noise. That is the
drawing and not the build, and a simpler small-size mark is a design decision, not a code one. The
build also still emits an unused `AppIcon.icns` on the Mac, because Xcode compiles every icon set in
the catalog; `CFBundleIconFile` names the new one, so nothing reads it.

### The desktop wall is an inspector, open by default and hideable

`PROPOSED` — Claude, 2026-09-18.

The ticket asked for "a permanent audience rail in the third column". It is SwiftUI's `.inspector`
beside your own Outpost, holding the same *Who sees your Outpost* screen the iPhone pushes — the same
sentences, the same *Change* actions, the same warning about a key that has not turned yet. No new
copy was written for it, because that screen's copy is already reviewed and true.

Read from the HIG before choosing, not remembered: a split-view pane may hold "functionality that
supplement[s] the primary view", with Keynote's inspector as Apple's own example; "consider letting
people hide a pane… provide a toolbar button or a menu command — including a keyboard shortcut — that
people can use to restore a hidden pane"; and "when your app launches, show people the most pertinent
information". So it opens by default and hides with a toolbar button or **⌥⌘I**, Keynote's shortcut.

**The deviation from the ticket's word.** "Permanent" became "open unless you close it". The HIG's
answer to a supplementary pane is that it can be hidden, and a rail nobody can dismiss is a worse
Mac citizen than one that starts open.

**What it replaced.** On the Mac the toolbar's push-to-screen button for the same view is gone, so
there are not two ways to reach one thing. iPhone and iPad keep it. The screen is now built in two
places, so both go through `OutpostAudienceView(_ audience:)` — the drift in CLAUDE.md's traps is a
second construction quietly losing an argument.

**Not seen.** It builds for both platforms and nothing more is known: the Mac's display was asleep
all night, and with it asleep every window counts as occluded and SwiftUI draws no scrolling content.

### The Mac toolbar's mailbox carries a hand-drawn count, and only when badges are on

`PROPOSED` — Claude, 2026-09-18. The mailbox itself, its count and the filled mark are what Griff
asked for; how the count is drawn and when it shows are Claude's.

Griff asked for "the little mailbox guy" in the Mac toolbar "where it has notification badges". The
system has no badge for a toolbar item: in the macOS 27 and iOS 27 SDKs, `badge(_:)` exists on a
`View` — drawn only in list rows and tab bars — and on `TabContent`, and not on `ToolbarContent`.
So the count is drawn by `WaitingButton` itself, a red capsule anchored at the glyph's top-trailing
corner that grows outward.

**This departs from the HIG, and it was read first.** *Notifications ▸ Badging*: "Avoid creating a
custom image or component that mimics the appearance or behavior of a badge. People can turn off
notification badges if they choose, and will become frustrated if they have done so and then see what
appears to be a badge." The request is Griff's, so it is built; the objection is honoured where it
bites. The count shows only when the system says badges are on for this app (`badgeSetting` and
authorization, read with the rest of the permission as `systemShowsBadges`), and it is the Dock's
number exactly: the same `BadgeCount.of`, moved into `CarpenterKit` so the UI reads one rule rather
than a second copy of it, under the member's own *Badges* choice. Turn badges off anywhere and the
mailbox is plain. The popover still lists what is waiting, because a list is not a badge.

**What it costs.** It is a component to keep looking like the system's badge when the system's badge
changes, and nothing will say when that happens. Measured in an offscreen window: the count is not
clipped by the toolbar at 3, 12 or 99+. **Not** seen against real Liquid Glass — an offscreen render
does not draw it — nor in dark mode for the same reason.

### The Mac has a Settings window, built from the same pages

`PROPOSED` — Claude, 2026-09-18. Griff asked for the Mac to get "some HIG love" and agreed to the
Settings window when it was proposed; its shape is Claude's.

Read from the HIG, *Settings*, before building: a Mac app's settings live in their own window,
opened with ⌘, from the app menu, with a toolbar of panes; the window's title is the pane's name,
and it reopens on the pane last seen. SwiftUI's `Settings` scene holding a `TabView` does all of that
itself, so that is what it is. The last pane is `@AppStorage("settings.pane")`.

**The panes are the iPhone's pages, not copies of them.** Each page You pushes — Appearance, Behavior,
Notifications, Privacy & Safety, Outpost settings, Devices — is now one `var` on `YouView`, and both
the row that pushes it and the pane that holds it call that `var`. Storage, the recovery key, the
history check, hidden messages and *Erase everything* share a *Data* pane. The Settings window is
`YouView` itself, `presentedAsSettings()`, built by the one `youScreen` construction. CLAUDE.md's trap
about two constructions drifting is the reason for all of it.

**The pane is called *Outposts*, not *Outpost*.** The feature and the product share the word, and
the branding lint refuses the product's name as a Swift literal. The sidebar's section already says
*Outposts*.

**What it moved.** A `Settings` scene belongs to the app, not to a window, and everything You reads
lived in `AppRootView`'s `@State` — one copy per window. The session, the mailbox, the preference
stores and the state a sync round or a pairing writes now live in `AppShell`, which the app owns and
both scenes share; `AppRootView` forwards to it, so its extensions did not change. `RootView` takes
the theme, icon and list-preference stores the way it already took `safety`, because a second
`ThemeStore` would let the Settings window change the accent without the main window noticing.
The window runs the sync loop and push; the Settings surface runs neither.

**What it costs.** Every pane is a fixed 580 × 540: a `List` has no natural height, and a Settings
window sizes itself to its pane. **Not seen** — built for both platforms and green, and nobody has
opened it.

### On the Mac, a settings page is the system's grouped form

`PROPOSED` — Claude, 2026-09-18. Griff, on the first look at the Settings window: "clean up the UI.
Are you using the documentation and system setup, liquid glass, like iOS does?" It was not: the Mac
drew the iPhone's pages — the app's own backgrounds, row surfaces, colored tiles on every row and a
large header card — and only the window's toolbar was the system's.

Read from the HIG before choosing. *Materials*: Liquid Glass "forms a distinct functional layer for
controls and navigation", and "don't use Liquid Glass in the content layer"; standard components
"pick up the appearance and behavior of this material automatically". *Settings*: a settings window
"accommodates the size of the current pane". *Toggles*: a switch or checkbox belongs in the window
body. So the answer to "liquid glass like iOS" is to stop painting over the system rather than to add
glass: the toolbar, the switches and the menus are the system's, and the content is the system's
grouped form.

**What changed, all in the shared pieces.** `SettingsPage` is a `List` on iPhone and a
`Form` with `.formStyle(.grouped)` on the Mac, and it replaced `List` at 36 places in 34 files. `SettingsRow`
drops its icon tile on the Mac, `SettingsToggle` is a plain labelled switch, the header card is a
compact icon, title and paragraph, `groupedRowSurface()` and the pages' own backgrounds step aside, and
`sectionHeading()` leaves the font to the form. The iPhone runs the same code it ran before, by
construction: every Mac difference is behind `#if os(macOS)`, and the two modifiers that replaced
`.scrollContentBackground(.hidden)` and `.background(palette.background)` sit where those did.

**What changed per page.** Color is a row of eight swatches in the pane, the way the Mac's own
Appearance settings show an accent color, instead of a page to push into. Devices has a *…* menu and a
context menu for renaming and removing, because swipes and an edit mode are the iPhone's, and *Add a
device* is a button in the form rather than in the Settings window's toolbar, which the HIG keeps to
the panes. *Erase everything…* is a push button. A row that performs an action is drawn in the accent
color, as it is on the iPhone.

**What the Mac no longer offers.** *Haptics*: the app's cues are impact, warning and error, and
`sensoryFeedback` plays none of them on a Mac, so the switch changed nothing. A setting that does
nothing is a claim the app cannot keep. *Inbox* was taken off the Mac for the same reason and came
back the same day as a pop-up, once the wide layout gave Solos and Rooms their own sidebar rows.

**Pane height.** Each pane takes the height of what it holds, up to 620 points, and scrolls beyond
that — Privacy & Safety and Outpost settings are both taller than a laptop's screen.

**How it was checked.** A throwaway harness outside the repository links the package, builds the
Settings window from the preview fixtures, and draws each pane into an offscreen window, in both
appearances; one window switched through all eight panes without a layout cycle and resized to each.
**Not seen:** the real Settings window's toolbar with these panes, and the main window's sheets,
which now use the same form and were not drawn.

### The Mac's menu bar carries the app's commands

`PROPOSED` — Claude, 2026-09-18. Griff: "Do it", of the menu bar queued as the next feature.

Read from the HIG, *The menu bar* and *Keyboards*, before choosing: support the standard menus in
their order; put app-specific menus between View and Window; "always show the same set of menu
items" and disable one that cannot act rather than hide it; a show/hide item's title says what it
will do; keep the standard shortcuts. Option-Command-I is the standard "display an inspector window",
which is why the audience inspector already had it.

**What is there.** *File*: New Room… ⌘N, New Solo… ⇧⌘N, Join with an Invite… — replacing New Window,
because the app is one window over one session. *View*: the system's Show/Hide Sidebar, and Show or
Hide Who Sees Your Outpost on ⌥⌘I, enabled only beside your own Outpost. *Go*: the sidebar's areas on
⌘1 onward, the way Mail numbers its favourite mailboxes, and a *Conversations* submenu. *Conversation*:
Mark as Read ⇧⌘U (Mail's), Pin, Silence, Leave… and Delete…, for the room that is open, each disabled
when it cannot act. *Help*: How This Works, in a window of its own, on the Mac only — an iPad has no
such window. The same commands reach an iPad's menu bar and keyboard. Menu titles are title case, as
the Mac's are; labels inside windows stay sentence case, as the app's are.

*Go* first numbered the rooms, ⌘1–⌘9 as Messages does; it moved to the areas the same day, when the
wide layout made the areas the sidebar and put the rooms one column in.

**What it found.** The Mac had no way to start a room, start a solo or join with an invite: those
lived in the iPhone's rooms list, which the Mac's sidebar does not use. The menu commands and a compose
button in the sidebar's toolbar now reach the same three sheets, which moved into one modifier,
`StartingConversations`, so the iPhone's list and the Mac's window present the same construction.

**How it was checked.** A windowless probe linking the package dumped the menu bar it builds — every
item above, in that order, with those shortcuts, disabled with no window in front — and the frontmost
app did not change while it ran. **Not seen:** the items enabled against a real window, the compose
button, and the help window.

### The Mac and an iPad at full width share one layout: areas, a list, and what is open

`PROPOSED` — Claude, 2026-09-18. Griff: "Do literally everything for the mac… make sure it looks good
for an iPad, horizontal and vertical."

Read from the HIG before choosing. *Sidebars*: "show no more than two levels of hierarchy in a
sidebar. When a data hierarchy is deeper than two levels, consider using a split view interface that
includes a content list between the sidebar items and detail view." *Tab bars* and *Sidebars* for
iPadOS: consider a tab bar first, and "to display a sidebar only, use `NavigationSplitView`". The
app's hierarchy is three deep — an area, a conversation or an Outpost, what is in it — so the wide
layout is a three-column split: the areas (Solos and Rooms, or Messages; Outposts; Search; You) with
their unread counts, the list for the area, and what is open.

**The list column is the iPhone's list, not a copy of it.** The Mac's old sidebar had drifted far
behind `RoomsListView`: no unread marks, no pins or tags, no *Waiting to be let in*, no *Nothing is
going out*, no search, no context menu, no way to start a room at all. The middle column is now
`RoomsListView` itself, built by the one `roomsList(_:)` the iPhone's two tabs also use, inside a stack
whose path is bound to `openRoom` — the binding a notification tap already drives — so choosing a room
opens it in the detail column. Search is the iPhone's `SearchTabView`; You is `YouView`, whose pages
open in the detail column. `StartingConversations` builds the three start sheets for both.

**Where it applies.** The Mac, and an iPad whose width is regular. An iPhone in landscape can report a
regular width too, and keeps its tabs: the check is the iPad idiom first. An iPad in Slide Over or a
narrow split keeps the tabs.

**At an accessibility text size** an iPad uses the tabs instead: at the largest size three columns
break words mid-word — *So / los*, *Ou / tposts* — and the tabs were already walked at that size.
Below it the sidebar and list widths grow with the text (`@ScaledMetric`), and at
extra-extra-extra-large every label still fits.

**Upright on an iPad** the sidebar sits behind its button and gets out of the way once an area is
chosen, and the *Who sees your Outpost* inspector starts closed, because upright it covers the Outpost
it describes. On its side, all three columns show.

**A defect it found.** A sidebar's selection can pass through `nil` while the search keyboard closes,
and `nil` meant "the default area": choosing You from Search opened Rooms. The binding ignores `nil`
now, and `WideAreaTests` holds the rules for which area a room lives in and what an area becomes when
the inbox is merged or Outposts are turned off.

**A selected row is white on `accentFill`.** A list with selection draws its chosen row in the tint,
with white text, and the dark palette's accent is a light teal that white does not read on — the
iPad's Outposts list, and every selection on a Mac. Those lists are tinted with `accentFill`, the fill
the palette already computes to carry white. The iPad's glass sidebar draws tinted text on grey
instead, and keeps the brighter accent.

**How it was checked.** `WideLayoutTests` walks the fixture app on an iPad Air 11-inch in both
orientations — rooms, a room open, the sidebar, Outposts, your own Outpost with its inspector, Search,
You, Appearance — screenshotting each and running Apple's audit on each. Two of the audit's findings
were real and are fixed: the *3 comments* link and the *Post to your Outpost* prompt were under 44
points tall, on every platform. What remains is the known Dynamic Type and avatar-initial findings, the
system's own search clear button and keyboard suggestion cells, and *Text clipped* on the Liquid Glass
sidebar's labels, whose text draws whole — the audit measures the label's frame from the icon's edge.
**Seen on a Mac afterwards**, in a real window on screen, captured from the process that owned it:
rooms with a room open, an empty detail, Outposts, your Outpost with its inspector, Search and You, in
both appearances. One defect, fixed: on a Mac a sidebar row carrying `.badge` — even an empty one —
lost its selection value and never showed as chosen, so each row now carries an explicit `.tag`.

### Copy names the device, says click on a Mac, and a hint never names a gesture

`PROPOSED` — Claude, 2026-09-18, in the Mac and iPad pass.

Sentences that told a member "your phone makes a key", "this is a setting on your phone" or "it has
not left this phone" were true only on an iPhone, and the honesty rules put a false present-tense
sentence on the same footing as a missing feature. They say *device* now, on every platform, the way
*Photos and clips you receive stay on this device* already did.

Visible instructions follow the platform's verb: *Tap to show* is *Click to show* on a Mac, and the
reaction sheets and lists say *click* there. Two screens whose only actions were swipes — Blocked
People and the rooms list's *Edit list* — also have a context menu now, and on a Mac their footers
say *Control-click* instead of *Swipe*, because a Mac has no swipe a member would discover. The Outposts
list's *Tell me* and *Mark read* moved into `OutpostPersonActions`, used by its swipes and by a context
menu on both lists.

VoiceOver hints no longer say *Double-tap to…*: Apple's guidance for a hint is to describe the
result and leave the gesture to VoiceOver, which knows the platform and the member's settings. A
photo's label used to carry its instruction; the label says what it is and a hint says what happens.

### Keyboard and pointer: the menu's shortcuts reach an iPad, and a sheet's cancel says Escape

`PROPOSED` — Claude, 2026-09-18, in the Mac and iPad pass.

*Designing for iPadOS* asks for a physical keyboard and a trackpad to be first-class. Measured on the
iPad simulator by `WideLayoutTests.testTheKeyboardReachesTheMenuCommands`: ⌘N opens *New room*, ⇧⌘N
opens *New solo*, and ⌘4 and ⌘5 open Search and You, from a keyboard, through the same commands the
Mac's menu bar shows.

Every sheet's cancel button declares `.keyboardShortcut(.cancelAction)`, SwiftUI's documented
binding for Escape. **Measured, it changes nothing today**: on the Mac, Escape leaves *New room* with
or without it, even with the cursor in the name field, and on the iPad ⌘. does the same — the system
handles both. A lint that required it was written the same day and removed once the Mac was measured,
because a rule that fails a build must stand for a difference somebody can see.

The Mac's composer was measured the same way, by sending keys to the real field: Return sent,
Shift-Return also sent, Option-Return wrote a second line — the system field's behavior, and what
Apple documents for Messages. See the next entry for what Shift-Return does now.

⌘F opens Search on the Mac, from the Edit menu, as *Keyboards* lists it. On the iPad it was measured
not to reach the command — the system keeps ⌘F — so there Search is ⌘4 with the other areas. The
window reopens on the area last used (`@SceneStorage`), as a Mac and an iPad restore where a person
was.

A photo in a conversation is a tap gesture rather than a button, so it had no pointer effect on an
iPad; it takes the system's highlight when it can be opened, shown or retried.

### A draft is kept per conversation, per post and per comment, sealed on this device, never synced

`RULED` — Griff, 2026-09-19: "do draft that survives", then "do the drafts for outpost comments, new
posts. In outpost settings add a button to wipe all drafts." The rest is `PROPOSED` by Claude the same
day.

One draft per conversation, one for the new post, and one per post being commented on, written down
as the member pauses, when the screen closes and when the app leaves the foreground. A conversation's
shows in the rooms list as **Draft**. They are sealed on disk under a random key kept in this device's
keychain rather than stored as plain JSON. The state file is only protected by iOS file protection,
and it is the file a backup carries. Each is bound to its place, so a comment's draft cannot be opened
as another comment's. They stay on the device they were written on, as iMessage drafts do; following
the member to their Mac would mean putting unsent words in the sibling feed.

**Delete drafts, in Outpost settings, deletes the Outpost's drafts only**: the new post and every
comment. It asks first and says it cannot be undone. A conversation's draft goes when it is sent or
emptied. That scope is Claude's reading of "wipe all drafts" placed in Outpost settings, and one
line widens it.

**What it costs.** A draft started on the iPhone is not there on the Mac. Photos staged on a new post
are not kept, only its words. Whether a draft survives a restore from a backup onto a new device has
not been measured.

### The Return key says what it does, and every field can put the keyboard away

`PROPOSED` — Claude, 2026-09-19, from Griff's report that the Outpost blurb's key said one thing, did
another, and left no way to close the keyboard short of leaving the page. Read against the HIG's
*Virtual keyboards*, *Text fields* and *Text views*.

- **A field that is one line of meaning ends on Return**, even when it wraps: the blurb (*A line
  about you*) and the three pasted codes (their code, the invite, the recovery key). The key says
  *done*, and pressing it saves and puts the keyboard away. A typed Return is taken back out; a paste
  that carries line breaks is left alone. `returnIsDone`.
- **A field for prose writes a line on Return**, with the key left as *return*, and a **Done** button
  in the standard bar above the keyboard puts it away: a report, a new post, editing a message, and
  *New tag*, whose Return (*next*) keeps the keyboard up for the next tag. `doneAboveKeyboard`, one
  construction for all of them.
- **Short fields** keep `.submitLabel(.done)` or `.next` with the action it names. Emoji search says
  *search*.
- **The composers** are unchanged: the arrow in the field sends, Return writes a line, and dragging the
  conversation down puts the keyboard away, as in Messages.

Measured on an iPhone 17 Pro Max with the software keyboard, every field the demo reaches, by
`KeyboardChecks`. Editing a message, joining with an invite, restoring from a key and onboarding are
not reached by the demo and share a measured modifier.

**What it costs.** A blurb or a code cannot hold a line break typed on the keyboard.

### Shift-Return writes a line on the Mac

`RULED` — Griff, 2026-09-18: "shift return should add a new line."

In the conversation composer and a post's comment field on the Mac, Return sends, Shift-Return and
Option-Return write a second line at the cursor. Shift-Return is caught with `onKeyPress` and the line
is written into the draft through the field's `TextSelection`, by `LineBreak.inserted`, rather than by
sending the field editor an AppKit action: the first attempt at that reached a window that could not
take it and crashed. `LineBreakTests` holds the insertion at a caret, over a selection, beside an emoji,
and with a selection left over from a longer draft — the case that trapped before it was clamped.
Measured on the real Mac field after the change: Return sent, Shift-Return and Option-Return each wrote
a line. On iPhone and iPad nothing changed; Return already writes a line there, measured again on the
iPad by `WideLayoutTests.testTheComposerStillTypesAndReturnWritesALine`.

### A photo or clip dragged onto a conversation or a new post is attached, never pasted as its path

`PROPOSED` — Claude, 2026-09-18. Griff: "Drag and drop go."

*Designing for iPadOS* names drag and drop among the things iPad people value most, and a Mac person
drags a photo from Finder without thinking. A photo or a clip dropped anywhere on a conversation, or
on the new-post sheet, is staged exactly as if the picker had handed it over — `DroppedMedia` imports
it as the picker's `PickedMedia`, and from there it takes the same path: `ImagePreparer` redraws it and
strips every tag before it is sealed. It is accepted only where *Add a photo* would be — attachments
on, the member still in the room, no solo check holding the composer shut — and a drop highlights the
conversation with an accent outline while it hovers. A post keeps its own limit of ten, and says how
many did not fit.

**A defect found while measuring it, and why the fix is where it is.** Dropped on the post's text, a
photo arrived as its **file path** — `/private/…/Users-…/drop.png` in the body of a post, which would
have published the member's username and folder to every reader. The conversation's field does the
same while it is being typed in: AppKit's text views accept file names, and a text view registered for
a drag's types is found before the drop target around it. Stripping those types from the text views
was tried and does not hold — a text view registers them again when it takes focus. So the composers
watch their own text instead: when an edit inserts nothing but the paths of existing image or video
files, the edit is taken back and those files are staged. `DroppedPathsTests` holds that typing, a
missing file, a path to a document and deletions are never taken for a drop.

**How it was checked.** `DroppedMediaTests` imports a PNG, a QuickTime file and plain text the way a
drag delivers them. On a Mac, a real conversation window on screen was handed a real PNG through its
drag destination, and captured: the hover outline, then the photo staged. The same file handed to the
post's text view and to the field being typed in came out staged, with no path in the text. **Not
done:** a drag by a real pointer from Finder or Photos on a Mac or an iPad — the harness hands the
drop to a destination it chose, and AppKit's own choice of destination was not measured.

### ⌘V with a photo on the clipboard attaches it, and words still paste as words

`PROPOSED` — Claude, 2026-09-19. Griff: "Do it", of pasting a photo into the composer.

On the Mac, in the conversation composer and a new post. Measured on the real fields, with the
harness's clipboard swapped for a private one in its own process so Griff's was never read or written:
before the change, ⌘V with an image on the clipboard did nothing — the field's Paste is disabled for
anything that is not text — and a file copied in Finder pasted as its **name**. SwiftUI's
`pasteDestination` on the field was tried and is never consulted while the field has focus, and a
key handler on the field never sees ⌘V, because the menu bar takes the key even when Paste is
disabled (measured: `performKeyEquivalent` returns true for a disabled item).

What works is a ⌘V shortcut on an invisible button inside the composer, present only while its field
has focus: a window's views are offered a key equivalent before the menu bar. With a copied photo or
media file on the clipboard it stages them exactly as a drop does; otherwise it hands Paste to the
field in its own window, so words paste as they always did. Copied writing that happens to carry an
image stays writing; an image that carries only its link is the image. A file name pasted by any other
route — Edit ▸ Paste clicked — is still turned back into the file when it names a media file on the
clipboard.

**Measured** with AppKit's own order, the window first and a standard Edit menu second: a photo and a
Finder-copied file are staged in both composers, and words paste into both. `ClipboardMediaTests` holds
the clipboard rules on private pasteboards. **Not done:** the same on an iPad — SwiftUI's paste
destination needs iOS 27 and the app targets iOS 26 — and Edit ▸ Paste chosen with the pointer, which
stays disabled for a photo because the field decides that.

### Product updates are a blog on the site, and the app links to it

`RULED` — Griff, 2026-09-19: "Instead of the You screen having a mail thing — we'll do updates for a
blog." The shape of the blog, its tags and where it is written are `PROPOSED` by Claude the same day.

**What's new** in Outpost settings opens `https://outpostmessaging.com/blog`, replacing a `mailto:`
that asked to be added to an update list. That link was the last address in the app, and an address
asks somebody to hand over theirs before they can read anything.

The URL is configured, not written: `APP_BLOG_URL` in `Config/Branding.xcconfig` reaches the app as
`BlogURL` in Info.plist and is read through `Branding.blogURL`, which is the pattern
`reportFormURL` and `contactFormURL` already use. The row does not draw when the URL is empty.
`APP_CONTACT_FORM_URL` was referenced by Info.plist and defined nowhere, so the contact link on
Privacy and Safety had never drawn in a real build; it is set the same way now.

**Where a post is written.** In the desk that already reads abuse reports and contact messages
(`akira-ng`, `/desk`, the Posts tab), against `microgpt-comms`. A post carries a title, a byline the
writer types, tags, an optional summary and a markdown body. It is a draft until it is published, and
the service never serves a draft. Its address is made from its title, and stops following the title
once it is published, because by then somebody may have linked to it.

**The tags are a fixed list** — release notes, roadmap, articles, security, Outpost, bullet — so the
site can offer them as filters. They are spelled in three places with no compiler between them:
`BlogTag` in comms, `BLOG_TAGS` in the desk, and `src/data/blog.ts` on the site. `BlogTagTest` pins
the service's side.

**What it costs.** The site now reads from the comms service at runtime, where every other page is
static — an unreachable service is a blog page that says so, and it is the first page here that can
fail that way. Nobody is notified of a post: this replaces an update list with something a reader
has to visit.

### A member on the bundled list is locked out of the app, list switch or not

`RULED` — Griff, 2026-09-19: "regardless of whether it's on or not, the block list, if it detects YOU ARE AN
ABUSER, should lock the app entirely." The screen, the wording of the button and where the appeal goes are his
too. How it is checked, and what it does to a round, are `PROPOSED` by Claude the same day.

`DenyList.contains` already answered "is this person on the list" for everybody else's entries. Asked about the
member's own identity it answers the same way, and when it says yes the app draws one screen: the mark in white
on the app's own red, the sentence Griff wrote, and an outlined button to the contact form with *A mistaken ban*
already chosen. `RootScreen.for(_:bannedSelf:)` takes the answer beside the session's state, so **every** state
maps to that screen rather than only the ready one — there is no path through onboarding, a stall or a restore
that reaches the app.

**It ignores `enforcesDenyList` on purpose.** That switch is the member's own choice about whose words they are
shown, and it was never meant to be a choice about whether the app applies its own list to them. Reading it here
would have made the lock opt-out with one toggle.

**It is checked when an identity arrives, not only at launch**, because the identity is what is on the list and
it can arrive twice: `load()` restores one from the keychain, and a recovery key restores one from twelve words.
Both end in the same check because the check is computed rather than stored.

**No round runs while it holds.** `AppSession.sync` returns an empty report before it builds a session, so a
locked device stops offering entries and stops collecting them. A lock that only covered the screen would have
left the log going out.

**What it costs, and what it is not.** This is a local check against a list that ships inside the build, so it is
worth exactly what that list is worth: it reaches a member when they take the update, and never before. Somebody
who wants around it can decline the update, clear the account and start again, or build the source themselves —
Griff's answer, 2026-09-19, is that clearing the account costs them every contact and every message they hold,
which is the price. It is not a claim that a banned member cannot use a phone. The list names nobody: it holds
SHA-256 fingerprints, so the build cannot say who anybody is, only whether this identity is one of them.

**Still open**: the notification extension is a second process with its own session, and it has not been taught
the check — a banned member's device would still draw a banner for something already collected. Nothing more is
collected, so the window is what is already on disk.

### The Supporter badge is two switches: one draws it for you, one tells everybody else

`RULED` — Griff, 2026-09-19: "They should have a setting to show it on their own profile, and a
separate setting to display it to other users." The wording of both rows is Claude's and is a
placeholder until Griff writes it.

It was one switch until today, and that switch did two unrelated things: it drew the mark on the
member's own picture, and it wrote a `supporterBadge` entry into every room and Outpost they are in.
`showsSupporterBadge` now does only the first and touches nothing on the network;
`sharesSupporterBadge` is the one that announces, and it is the only one a peer can observe.
`announceSupporterBadge` reads the second, so a member can wear it privately, show it to everybody
without seeing it themselves, or neither.

**One answer still becomes two.** The question a new Supporter is asked has not been split — answering
it sets both, through `answerSupporterBadge`. Two questions in a welcome sheet for one mark would be
worse than the thing this fixed.

**A state file written before today keeps its meaning.** `isSharingSupporterBadge` reads
`sharesSupporterBadge ?? showsSupporterBadge`, so a member who had said yes under the old single
switch goes on being seen, rather than silently disappearing from everybody's avatars on the update.
The pair merges across a member's own devices the way every other preference does, last write per
field.

**What it costs.** Two switches for one mark is more settings surface than the thing deserves, and the
second one's effect is invisible from the device that sets it — the proof that it worked is on
somebody else's phone. `SupporterBadgeTests` holds both directions: showing without sharing reaches
nobody, sharing without showing reaches a peer and not your own avatar.

## Superseded

Kept briefly so nobody re-derives them.

- **The badge theory.** A badge on a subscription was believed to buy push priority. It makes the push
  *visual*, which stops it waking the app. Both silent subscriptions are silent; the badge is unset.
- **"A notification extension cannot suppress a push."** True by default and incomplete: it can, with
  `com.apple.developer.usernotifications.filtering`, which needs Apple's approval. Not pursued —
  scoping the subscription removed the need.
- **"Spurious notifications cannot be fixed without going silent."** False. `recordType` scopes a
  subscription, including on the shared database, and nothing was using it.
- **`pushingOutgoing: false` means the extension does not write.** It skipped the send and left the
  receive path acknowledging, which is a write. Replaced by `SyncMode.readOnly`.

- **A consensus purge opens the room and shows a passing notice.** Ruled 2026-09-13; replaced on
  2026-09-15 by [a permanent line in the transcript](#a-deletion-leaves-a-line-in-the-transcript-not-a-notice-that-fades),
  after the HIG's Alerts page pointed away from a notice that fades. Opening the room the purge
  happened in still stands.

#### ~~A search is scoped to its screen, and says so where it stands~~

**Decided and reversed 2026-09-12**, within hours, and replaced by
[Search is a tab at the trailing end](#search-is-a-tab-at-the-trailing-end-and-the-inline-field-is-for-sub-views).
Kept in full because it is wrong in an instructive way: it reads Apple's guidance carefully, quotes
it accurately, and answers the wrong question about this app.

The three search fields drop `.searchToolbarBehavior(.minimize)` and stand inline under their
screen's title.

**What it costs.** The collapsed magnifier, and a field's height on every launch of those three
screens. That is the trade Apple describes as the point rather than the price: a field under the
title, next to the content it filters, is what tells somebody they are searching this list and not
the app.

**The discriminator is not "is this a list".** Every screen in this app is a list — rooms, solos,
posts, people — and Mail, the app the bottom-toolbar search is named for, is a list too. Being
list-first is not what decides it, and reading it that way is the mistake this paragraph exists to
stop. Apple's two questions are *how do people navigate this app* and *what is the scope of this
search*, and both answer against the bottom toolbar here:

- **What is at the bottom edge.** Mail's is a toolbar, so a search field can live in it, "adjacent
  to other primary actions". Ours is a tab bar. The session treats the two as alternative
  navigation models and never puts a search field in a toolbar underneath a tab bar.
- **How many searches there are.** The session addresses a tabbed app whose tabs each hold a list
  directly, and lands on inline-per-tab rather than one search tab: the pattern "is particularly
  useful if your app has more than one Search Field and when location plays a critical role in the
  scope of your Search." Three fields, and searching solos, rooms and posts are three different
  questions — that is this app, quoted.

**What would change it.** A single search over everything. That is a dedicated search tab, and it
is a different feature — not a modifier. It would also be the right call if the tab bar went away.
