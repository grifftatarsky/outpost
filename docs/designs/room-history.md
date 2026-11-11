<!-- COPY BEGIN 51b36694 [NEEDS HUMAN REVIEW] -->

# A room setting for how much a newcomer can read

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../part-b-plan.md).

## For Griff, on one page

**What it promises** (your rulings of 2026-09-19 and 2026-11-10):
1. Someone let in *from when they join* cannot open anything written in the room before the key
   made when they were let in. That holds whatever app they run, on every device they add, after a
   restore, and whoever they ask.
2. Their phone works out who is in the room from the room's own entries, by the same rules as every
   other phone, and gets the same list.
3. Nobody can give a newcomer an earlier start than the room's setting allows, than their inviter's
   own start, or than the start of the member who records it. Nobody outside the room can give
   anyone a start or change the setting.
4. Changing the setting changes only what people let in after the change are handed. It takes
   nothing back.

**What a member sees.** The founder picks *What new members can read: Everything / From when they
join* when making the room, and can change it later from the room's menu. Other members can see the
setting but not change it. The invitation says which one applies. A newcomer's first screen says what
they can read. Their room starts with "You can read this room from here." and shows nothing from
before that. If somebody wrote a message just after the join under the old key, it shows as "Not
readable on this device."

**Decisions that are yours** (more detail in §9).
1. **May a member who joins part way see the room's membership history from the beginning?** That
   is who was invited, who voted, who was removed, and who left, but never what was said. Each
   membership entry also carries a visible mark, so a phone knows when it is missing one.
   *Recommend yes.* Cost: anyone holding the room's sealed entries can tell which entries are about
   membership and when they were written. A member running a modified app can stall key hand-outs
   in a room until they are removed.
2. **Does a start name one exact key, rather than just a key number?** *Recommend yes.* Cost:
   messages written on a phone that was offline during the join, under a key iCloud had not seen,
   show as "Not readable" for the newcomer.
3. **Should read receipts and Solo checks become membership entries?** Without that, a remover
   running a modified app can make a part-way member's list differ from everyone else's.
   *Recommend yes.* Cost: a part-way member running a modified app can see who read which message,
   and when, back to the beginning. They still cannot see what the messages said.
4. **What does a new room start with?** *Recommend From when they join.* Cost: every test and rig
   step where a newcomer reads old history has to name Everything.
5. **What about a message written right after a join, by a phone that had not collected the new
   key?** The newcomer cannot read it. *Recommend* showing it as "Not readable on this device" and
   measuring how often it happens on the rig before the tester build. Cost: the newcomer is told the
   message exists but never reads it.
6. **Should old messages be kept off a part-way member's phone entirely?** Today they arrive sealed.
   *Recommend shipping without this, and doing it before the tester build if you want it.* Cost: a
   modified app can see who wrote each old message, when, and how long it was.

**Time windows, plainly.** "The last 30 days" exactly cannot be done. One key covers everything
written while it was current, so the start has to fall on a key change. What can be promised honestly
is "up to 30 days": a newcomer reads back to the first key change inside the window, or from when
they join if there was none. With no scheduled key change this costs nothing extra, and a busy room
changes its key at every join and removal anyway. A daily key change brings it closer to 30 days, at
the cost of 9 or more extra grants per day in a room of ten. Grants are sent again after every launch,
and each one carries every link. Either way it is a third choice, so it has to be decided before the
tester build, and key changes would be dated by when iCloud stored them, not by a phone's clock.
*Recommend:* leave it out of the first tester build, or if you want it, use the version with no
scheduled turn.

**Fixed on 2026-11-11 (§0):** two faults in the Outpost "from now" path let a reader let in from now
read the owner's earlier posts. Each was shown by a failing test first
(`WhatAnOutpostReaderIsHandedTests`, `AKeyChangeIsSealedUnderTheKeyItsLinkOpensTests`) and then
fixed. Neither has run on two accounts. A review then showed the first fix is a trade, for the reason
decision 2 below exists: [the question](../open-questions.md#a-reader-let-in-from-now-when-the-owner-posts-from-two-devices).

---

Design for branch `overnight-2026-10-31`. Read-only work: nothing was built, run or changed in the
repository. Path shorthand: `Kit/` = `Packages/Carpenter/Sources/CarpenterKit/`, `Session/` =
`Packages/Carpenter/Sources/CarpenterApp/Session/`, `UI/` = `Packages/Carpenter/Sources/CarpenterUI/`.
A code fact carries the file and line I read it at. How the new design behaves is a design claim,
marked **inferred** where it matters; none of it has run. **Not verified** means I could not check it.
This version answers a review; §11 lists the findings not taken.

## 0. Two faults in today's Outpost path, to fix before anything else

Both read in the code on 2026-11-11, **not run**. Each is its own commit with its test first.

### 0.1 A rival key below a reader's floor is handed over

**The fault.** `keysToPassOn` returns the newest keys plus `straysBelow`
(`Session/AppSession+Peers.swift:202-209`, `247-266`). The target loop applies the floor to `link`
and `links` only (`:156-159`); `secret` goes out whatever its number (`:177-178`). The receiving side
does not check: `EpochGrant` adopt calls `reaches`, true for any number at or below the top, then
`hold` (`Kit/Crypto/EpochGrant.swift:131-149`), which stores the key when no secret is held there
(`Kit/Crypto/EpochChain.swift:152-158`).

**How it happens.** Owner devices A and B are both on wall key 3. A allows R1 from now while offline
and makes a4. B, unaware, allows R2 from now and makes b4. They sync. A allows Y from now and makes
a5 from a4, so Y's floor is 5. In `straysBelow`, b4 is not reachable from a5, so it is a stray, and
it is trusted because the owner wrote its key change. Y gets b4 with no link and reads B's posts from
before Y was let in.

**The failing test** (`WhatAnOutpostReaderIsHandedTests`,
`aReaderLetInFromNowIsNotHandedARivalKeyBelowWhereTheyCameIn`):
1. Owner session A, and a second device B made with `keychain.sibling()` and `approveNewDevice(_:)`.
   Reader sessions R1, R2, Y. Sync until A and B agree on wall key 3.
2. Without syncing between them: A `allowOutpost(R1, everything: false)`; B
   `allowOutpost(R2, everything: false)`; B posts "before Y" to the wall.
3. Sync A and B. A `allowOutpost(Y, everything: false)`. Run A's round and B's round.
4. Read every grant addressed to Y out of the `InMemoryMailbox` with the app's own unpack. Assert
   that none carries a key numbered below Y's `sinceEpoch` or a link at or below it. Then sync Y and
   assert that Y's wall shows no "before Y".

Expected to fail on today's code (inferred).

**Smallest fix.** One line in the target loop, before the receipt:
`if let floor, epoch < floor { continue }`, straight after the floor is computed
(`Session/AppSession+Peers.swift:156`). The check on the
receiving side (§3.1) comes later, with the shared lookup.

### 0.2 A key change can be sealed under a key its own link does not open

**The fault.** `advanceEpoch` reads `writing` and works out the new key and its link
(`Session/AppSession+Membership.swift:650-656`), then calls `append` (`:658-659`). `append` runs
`rekeyBeforeWriting` if the room is flagged (`Session/AppSession.swift:394`), which runs a nested
`advanceEpoch` (`Session/AppSession+Outpost.swift:473-483`) that makes a rival key at the same
number. `append` then reads `writingKey` again inside `oneWriteAtATime` (`Session/AppSession.swift:404`,
`412-413`) and seals the outer key change under that rival. A concurrent `advanceEpoch` that adopts
first during an `await` does the same. This is the CLAUDE.md trap "never copy main-actor state
across an `await`".

**How it happens.** An owner restores with the recovery key. The first grant for their own wall
flags it (`Session/AppSession+Peers.swift:451-455`). Their first write to the wall is
`allowOutpost(Y, everything: false)` (`Session/AppSession+Outpost.swift:363-371`). The outer turn
makes sE+1 with a link that wraps sE. The nested turn makes s'E+1. The outer key change is sealed
under s'E+1 at E+1. Both E+1 keys are trusted, and both reach Y at the floor. Y opens the outer key
change with s'E+1, records the link, and unwraps sE with sE+1. `unwindEpochs` does exactly this on
an honest phone (`Session/AppSession+Membership.swift:674-700`). Y reads the owner's posts under key
E.

**The failing test** (`AKeyChangeIsSealedUnderTheKeyItsLinkOpensTests`, two tests):
1. `aFlaggedWallStillSealsEachKeyChangeUnderTheKeyItReplaces`: put the owner's wall in
   `persisted.rekeyBeforeWriting`, the way a restore does (**not verified** whether `TestSession`
   has a restore helper; inserting the flag directly does what `:451-455` does). Post "before Y".
   `allowOutpost(Y, everything: false)`. For every `epochChange` in the wall, assert that the secret
   that opens it is the one its link unwraps to under the key it makes.
2. Sync Y, and assert that Y's wall shows no "before Y".

**Smallest fix.** `append` gains a parameter for the key to seal under. `advanceEpoch` passes the
`writing` key it read, so the key change is sealed under exactly the secret its link wraps, whatever
else happens before the lock (`Session/AppSession.swift:412-413`). It cannot take `oneWriteAtATime`
itself, because that lock queues tasks (`:429-435`) and nesting it would deadlock. `advanceEpoch`
also runs `rekeyBeforeWriting` before it reads `writing`, so a restored phone turns from a key no
removed device holds. Two concurrent turns then make two rivals that each wrap sE, sealed under sE,
which the chain already allows (`Kit/Crypto/EpochChain.swift:147-169`).

---

## 1. What it must guarantee

Griff confirms these before code is written (CLAUDE.md, "Before building", rule 1). The first tests
try to break exactly these sentences.

**G1. Nothing said before.** A member let in *from when they join* cannot open anything written in
the room before the key named in their start record. Messages written under a rival key made before
the join count as before. This holds whatever app they run, on every device they add, after a
recovery-key restore, and whoever they ask.

**G2. The same room.** Their phone shows the room everybody else's shows: its name, its rule, who is
in, who was removed, who left. It works that out from the room's own entries by the rules every
phone uses, and nobody restates the room for them. It depends on one condition that goes to Griff:
the members whose standing links it follows are honest (§9, Q10).

**G3. Nobody starts anybody earlier.** A newcomer's start is no earlier than the narrowest of three:
what the invitation says, what the room's setting allows, and their inviter's own start. A start
record also counts only from a member whose own start is no later than it. Somebody outside the room
cannot give anybody a start, and cannot change the setting.

**G4. The setting changes only what later newcomers are handed.** It takes nothing from anybody and
gives nothing to anybody already in.

Who each sentence must stop:

| Adversary | What they try | What stops them |
|---|---|---|
| The newcomer, modified app | ask members, repair, a restore or a new device for older keys | Every honest phone reads the start from the room's entries each time it hands a key (§3.1). Repair hands entries, never keys (`Session/AppSession+HistoryRepair.swift:29-32`, `356-365`). |
| The newcomer, modified app | invite a second identity and give it an earlier start | G3: the term is capped by the inviter's start, and a record below its author's start does not count (§3.3). |
| The newcomer, modified app | write a membership entry under a message key, or a post under a standing key | A standing type counts only when a standing key opened it, and any other type only when a message key did (§3.4). |
| A removed member | hand over an older key, write a start, change the setting | Their keys are refused (`Session/AppSession+Peers.swift:394-406`); every new entry type needs an author the room shows as in at that point (§3.3). |
| A member's phone that is behind | hand the newcomer every link | No setting entry means *from when they join* (§2.2). Every admission needs a start record, and a missing one means hold (§3.1). A phone holds until it has every entry the admission's clock names (§3.1). |
| A rival key made offline before the join | reach the newcomer at or above the start number | The start names one key. At the start number, only that key is handed; above it, only keys whose links lead down to it (§3.1). |
| The newcomer's second device, or a restore | get every link because it is a new device | Peers key the start on the member, read from the room's entries; the member's own device can pass on only what it holds (`Session/AppSession+DeviceSync.swift:308-314`). |
| A superseded invitation | an older invitation that said *everything* answered after a narrower one replaced it | A confirmation counts only against the invitation the room holds for that person (`Kit/Membership/RoomRoster.swift:311-316`). |

---

## 2. The setting

### 2.1 Values

```swift
public enum HistoryForNewcomers: String, Hashable, Sendable, Codable {
    case everything
    case fromJoining
}
```

Two cases, both written by the first build. "Nothing reads a form that no build writes" (RULED
2026-11-10, `docs/decisions.md:6507-6510`) makes a third case free before a tester build and a
format change after it. So a time window is decided before that build.

### 2.2 Where it is stored

- **In the room:** a new entry `roomHistory` (payload type 27; 25 and 26 are taken,
  `Kit/Log/Payload.swift:52-53`) with body `RoomHistoryBody { newcomers: HistoryForNewcomers }`.
  The roster applies it only from the founder, and only while the founder is in, the same as
  `roomAccess` (`Kit/Membership/RoomRoster.swift:217-220`, `293-295`).
- **No entry means `fromJoining`.** A phone that has not received the founder's entry under-shares
  instead of over-sharing. `createRoom` writes the entry when the choice is *Everything*.
- **A Solo is always `everything`.** The other person joins after the founder may have written
  (`Session/AppSession+Messaging.swift:24-27`). The roster knows the kind from the founding entry
  (`Kit/Membership/RoomFounding.swift:26-30`).
- **In each invitation:** `MembershipAttestation.history: HistoryForNewcomers`, a required field
  inside the inviter's signature (the signed list is at
  `Kit/Membership/MembershipAttestation.swift:92-110`). The inviter's phone collects from the room's
  members first, then copies the room's setting. Nothing treats a missing field as *everything*.

### 2.3 What a newcomer gets

`term = narrowest of (the invitation's term, the room's setting for this admission, the inviter's own start)`.
*From when they join* is narrower than *everything*. A start at key 7 is narrower than *everything*
and wider than a start at key 9.

**The room's setting for this admission** is decided by causal position, never by the `wallTime`
that `CausalOrder` uses to break ties (`Kit/Log/CausalOrder.swift:40-43`, `130`). It is *everything*
only if the entry that establishes the joiner causally follows a founder's *everything* entry, and
every *from when they join* entry this phone holds causally precedes that *everything* entry. A
narrowing concurrent with the admission narrows it on every phone that holds the narrowing. What a
phone that does not hold it yet does is in §3.1 (the wait) and Q8.

**The inviter's own start** closes the second-identity case (review finding, G3). J joined from key 7.
The founder switches to *Everything*. J invites J2. J2's term is J's start, key 7, not *everything*.
Every phone can work this out because the inviter is established when the `joinRequest` counts
(`Kit/Membership/RoomRoster.swift:297-300`).

### 2.4 Who may change it, and what a change does

- The founder, while in the room, the same as "Who gets in"
  (`Session/AppSession+Membership.swift:502-508`). If the founder has left, nobody can change either
  setting (Q9).
- A change applies to admissions that causally follow it (§2.3).
- People already in are untouched. A member's start is fixed when the room lets them in and lasts
  that membership.
- **A widening does not reach invitations already out.** An invitation issued under *from when they
  join* keeps that term, because the term is the narrowest of the invitation and the room. The
  setting screen says so (§5.1). Re-issuing open invitations on a widening is Q6.
- A narrowing reaches invitations already out (§2.3).

### 2.5 Time windows

**Why exactly N days cannot be promised.** A start has to be a key, because a key covers everything
sealed while it stood (`docs/decisions.md:2479-2506`, FACT, per research-here §11). Keys change when
somebody is let in, removed, leaves, or removes a device (`Session/AppSession+Membership.swift:471-474`,
`643-647`; research-here §2).

**What can be promised:** "A newcomer reads back to the first key change in the N days before they
were let in, and from when they join if there was none." That is an upper bound, and it is honest
only if the start names a key (§3.1). A key number alone could include a rival key made earlier.

**Two versions for Griff (Q7):**

| | No scheduled turn | Daily turn by `RoomRoster.keyRotator` (`Kit/Membership/RoomRoster.swift:418-421`) |
|---|---|---|
| Extra cost | none | room of ten: per day, one key change, 9 grants from the rotator, up to 72 more as members pass it on (`Session/AppSession+Peers.swift:151-183`, inferred). Each grant carries every link (`:158-159`), so 365 links a year in, re-sent after launches because receipts are in memory (`Session/AppSession.swift:195`). The 2,048-link cap (`Kit/Crypto/EpochChain.swift:95`) is reached in 5.6 years. Bytes not measured. |
| How close to N | in a busy room, back to the latest join or removal inside N days; in a quiet room, from when they join | N−1 to N days when the rotator's phone runs daily, less when it does not |

**Dating.** A key change would be dated by when iCloud stored it, not by the `wallTime` its maker
chose (CLAUDE.md, "A date a device writes is not an order"). **Not verified:** whether iCloud's
stored time for an entry's packet reaches the roster today. If it does not, that is part of the
cost.

**If built:** a third case `.recent(days: UInt16)`, bounded to 1...3650, and an entry outside the
bound is dropped. The settler writes the start key for the earliest key change iCloud stored inside
the window. G3 still holds.

**Recommendation:** leave it out of the first tester build. If Griff wants a window, the version
with no scheduled turn costs nothing and its label is "Up to N days". "Time windows" may also have
meant access that ends on a date, the way an Outpost has periods
(`Kit/Model/OutpostAccess.swift:3-5`). That is a different feature: somebody's phone has to turn the
key on that date.

---

## 3. How it is enforced

### 3.1 Which keys a newcomer is handed

Every member's `grantsOwed` runs for every member of every room (`Session/AppSession+Peers.swift:127-187`).
Today the room branch has no floor (`:142-145`, `:156`). After §0.1:

```swift
let starts = readsFrom(in: room)                 // wall: the owner's access entries; room: the roster
for passing in keysToPassOn(in: room) {
    for target in targets {
        switch starts[target] ?? (isWall ? .beginning : .owed) {
        case .owed: continue
        case .beginning: floor = nil
        case .at(let number, let key): floor = (number, key)
        }
        guard reachesTheStart(passing, floor, in: chain) else { continue }
        let link = …                              // as today: no link at or below floor.number
        let links = chain.everyLink.filter { … }  // as today
        …
```

- **A missing start means hold, for rooms.** Every admission writes a start record, including
  *Everything* ones (§3.2), so no room target should be missing from the lookup. If one is, it gets
  nothing. Walls keep `.beginning`, where an access entry always exists for a reader.
- **`reachesTheStart`.** At `floor.number`, only the named key goes. Above it, only a key whose links
  walk down to the named key, using `chain.unwrapping` as `straysBelow` does
  (`Session/AppSession+Peers.swift:255`). Below it, nothing. The walk visits only numbers this phone
  holds (`EpochChain.heldNumbers`), never a range a peer chose.
- **The wait.** A phone treats a newcomer as `.owed` until it holds every entry named by the clocks
  of the entries that let them in and of the start record. That is the same rule
  `holdsWhatItsMakerSaw` applies to keys (`:189-196`; RULED 2026-09-29, `docs/decisions.md:920-946`).
  It means a phone that holds the admission but not the narrowing it followed hands nothing.
- **A phone holding a membership entry it cannot open holds keys for that room.**
  `withholdsKeys` (`:123-125`) fires today only when something did not verify and somebody is out.
  It also fires when this phone holds an entry marked as standing (§3.4) that it cannot open. Such an
  entry may be a removal, and the type is inside the seal (`Kit/Log/LogRenderer.swift:138-146`).
- **The start is read from the room's entries every time.** Grant receipts are in memory
  (`Session/AppSession.swift:195`), so a start remembered once would be gone at the next launch.
- **Receiving side.** `EpochChain.adopt` (`Kit/Crypto/EpochGrant.swift:131-144`) takes the phone's
  own start, if it has one, and drops any key below it and any link at or below it. That protects an
  honest newcomer from a faulty phone. G1 does not rest on it.

### 3.2 Who records the start, and what the record is

New entry `historyStart` (payload type 28, a standing type):

```swift
public struct HistoryStartBody: Hashable, Sendable, Codable {
    public let joiner: ParticipantID
    public let invitation: Data                    // the attestation's signature, as AdmissionBody names it
    public let start: Start                        // .beginning, or .at(EpochNumber, keyFingerprint: Data)
    public let heads: [EntryHash]                  // what the new key's maker had seen
    public let proof: Data                         // as EpochChangeBody.proof, for key `start`
}
```

**Recorded in the same call that lets them in.** The design no longer waits for a later round.
- **Open room:** `relayJoinConfirmations` already runs inside the round after collecting
  (`Session/AppSession+Sync.swift:398-407`) and turns the key there (`Session/AppSession+Membership.swift:471-474`).
  Straight after that turn, it appends the record.
- **Room with a rule:** `decide` (`Session/AppSession+Membership.swift:621-648`) collects from the
  room first, as a send does (`Session/AppSession+Messaging.swift:37`, `48`). It then appends the
  admission. If that establishes the joiner, it turns the key and appends the record.
- **One write:** the turn and the record go in one sequence. The key change is sealed under the key
  its link wraps (§0.2). The record is sealed under the new key's standing key, so its number equals
  the start.
- **Everything:** the record says `.beginning` (or the inviter's start, §2.3) with no extra key turn.
  Today's inline turn for those admissions is unchanged.

**Who may write it:** the inviter, any member whose vote for this invitation counts, and
`RoomRoster.keyRotator` when none of those is still in. A phone retries in its round
(`settleHistoryStarts`, placed after `settleOwedKeyRotations` at `Session/AppSession+Sync.swift:406`)
for any joiner it let in who is still `.owed`. Whether `keyRotator` should also step in when the
person who let them in is still in but their phone never runs again is Q11. The "a day has passed"
fallback is dropped, because it measured a date a device chose.

**The proof lets the newcomer pass the key on.** `EpochChangeBody.isAuthentic` is an HMAC over the
heads, under a key derived from the new secret, the room and the number. It does not use the
link's wrapped bytes (`Kit/Crypto/EpochChain.swift:67-77`). So the record can carry heads and proof
without the link, and `holdsWhatItsMakerSaw` (`Session/AppSession+Peers.swift:189-196`) can accept it
for key `start`. That removes the extra key turn the earlier draft needed for each newcomer.

**First key.** A newcomer takes a first key only from their inviter today
(`Session/AppSession+Peers.swift:322-329`). Now they also take it from the author of a counting
`historyStart` that names their invitation and that the key itself opens. A waiting grant is tried
that way, and `adoptGrantsThatWaited`, which skips rooms with no chain (`:347`), handles a room with
no chain yet.

### 3.3 The roster rules (`Kit/Membership/RoomRoster.swift`)

- `history: HistoryForNewcomers`, set by `roomHistory` from the founder (§2.2).
- `establish(_:)` (`:363-367`) records, the first time a person is established in this membership,
  `.owed(invitation:, term:)` with the term from §2.3. A person already established is left alone.
  Removal and departure clear it (`:369-388`, `:402-416`). It is keyed by person because it is set and
  cleared with `established`, which is keyed the same way.
- A `historyStart` counts only when all of these hold at that point of the replay:
  1. a standing key opened it (§3.4);
  2. its author may write it (§3.2), is established, is not the joiner, and has a settled start of
     their own;
  3. the joiner is established under that invitation;
  4. its start agrees with the term: `.beginning` only for a term of *everything*. Otherwise
     `.at(n, k)` with `n` above the number the establishing entry is sealed at, `n` no higher than
     the number the record is sealed at, `n` no lower than the inviter's start and the author's
     start, and `k` a key at `n` that the record's own standing key comes from.
- **Which record wins:** the lowest `n` among records that count. A later record cannot raise a
  start, so the late-raise and two-devices cases cannot take keys away. It cannot lower one below the
  join either, because of rule 4. The "can read from here" notice is drawn only at the record that
  wins. Ties in the replay never decide it.
- `RoomRoster.rosterShaping` (`:276-279`) gains `roomHistory` and `historyStart`.
- `RenderedEntry` gains the entry's key number and whether a standing key opened it
  (`Kit/Log/LogRenderer.swift:15-49` carries neither today).

### 3.4 How the newcomer learns who is in the room: standing keys and standing links

**The problem.** The member list is a replay from the founding entry (`Kit/Membership/RoomRoster.swift:281-361`).
An entry that does not open is not a roster entry (`Kit/Log/LogRenderer.swift:138-146`). A newcomer
without the old keys has no room at all (`Kit/Log/Projection.swift:28-35`).

The old branch restated the room in a `roomState` entry that it trusted while the list was empty
(research-desktop §2.3). That is a claim beside the roster, and it misses removals sealed under an
older key. This design seals the entries that decide who is in under a second key.

- **The standing key.** For key number *n* with secret *S*, the standing key is one more HKDF output
  of *S* under its own domain, beside the message key and link key (`Kit/Crypto/EpochChain.swift:248-305`;
  domains at `Kit/Crypto/Identity.swift:287-289`). It gives nothing toward *S*.
- **Standing types:** `RoomRoster.rosterShaping` plus `removalNoted`, `readReceipt`, `soloCheck`,
  `roomHistory`, `historyStart`, `standingLink` (Decision 3 adds `readReceipt` and `soloCheck`).
  `epochChange` is never one: its link opens the previous key.
- **The mark.** `SealedPayload` gains a field outside the seal: `standing: Data?`, the standing
  key's fingerprint, also bound into the associated data (`Kit/Crypto/SealedPayload.swift:4-6`,
  `36-54`). The opener picks the key family by the mark. After opening, a standing type counts only
  if the mark is present, and any other type only if it is absent. Anything else is unopened on
  every phone. That replaces the earlier "try the message keys, then the standing keys" fallback,
  which would have let a modified app split member lists. Decision 1.
- **Standing links, in the log, not in grants.** Each key turn appends a `standingLink` entry beside
  the `epochChange`. It is sealed under the new key's standing key and carries:
  - the standing keys of every key the maker held at the previous number (at most
    `EpochChain.mostRivals + 1`, `Kit/Crypto/EpochChain.swift:89`), wrapped under a key derived from
    the new standing key;
  - the same `heads` the key change names.

  A newcomer derives the standing key at their start from the secret they hold and walks down,
  inside the same fixed-point loop `unwindEpochs` runs (`Session/AppSession+Membership.swift:674-700`).
  That walk is linear in the entries the phone holds. Nothing new goes in grants, the keychain,
  `PersistedState` or the sibling feed: the walk runs again each launch.
- **A rival found later.** A phone whose `straysBelow` (`Session/AppSession+Peers.swift:247-266`)
  holds a key that no standing link in the log wraps writes one re-wrap `standingLink` under its
  newest standing key, after checking the log.
- **Which standing links count on a newcomer's phone:** one at its start written by the author of
  the winning `historyStart`; one above its start written by the maker of that key (the newcomer can
  open those key changes); one below its start only if it was reached by the walk; a re-wrap only from
  a current member. Per number, at most `mostRivals` standing keys are kept, counted across all
  givers.
- **Why every room writes them:** a room set to *Everything* can be narrowed later, and the next
  newcomer then needs links back to the founding entry.

**Why the newcomer can trust the result.** Their phone opens the same entries every phone opens and
applies the same rules. The founder is proved by the room ID in the invitation they checked
(`Kit/Membership/RoomFounding.swift:7-18`). Every later step needs an author already established. A
missing standing key makes the phone hold keys (§3.1), so it does not quietly treat a removed person
as still in.

**Cost, plainly (Decision 1).** A from-joining member's phone can open every membership entry from
the beginning, and every read receipt and Solo check if Decision 3 is yes. The app shows none of the
part before they joined (§5.4), but a modified app could.

**The removal line (Decision 3).** When a removal names fewer of the removed person's entries than
the remover held, the line is extended from what the remover's earlier read receipts, key changes
and Solo checks named (`Kit/Log/Projection+Standing.swift:25-34`, `198-212`; PROPOSED,
`docs/decisions.md:4186-4200`). It skips any entry that does not open (`:205`). None of those types
is standing today, so a from-joining phone would draw a shorter line and cut more. That is a
different member list, read, not run. The fix: read receipts and Solo checks become standing types,
and the extension reads heads from `standingLink` instead of `epochChange` on every phone. Every
phone then extends the line from the same entries.

### 3.5 What stops older keys reaching them by any other path

| Path | Today | With this design |
|---|---|---|
| A grant from any member | newest key and every link (`Session/AppSession+Peers.swift:156-159`) | §3.1, read from the entries on every phone |
| A phone without the start record | — | holds (`.owed`) |
| A phone without the setting | — | no entry means *from when they join*; the invitation carries the term; the wait (§3.1) |
| History repair | hands entries to members and invitees, never keys (`Session/AppSession+HistoryRepair.swift:29-32`, `356-365`) | unchanged |
| The links in the log | each `epochChange` sealed under whatever key `append` picks (§0.2) | sealed under exactly the key its link wraps (§0.2), pinned by a test |
| The newcomer's own second device | every key the first holds (`Session/AppSession+DeviceSync.swift:308-314`) | the same, which is nothing below the start |
| A removed member | key refused (`Session/AppSession+Peers.swift:394-406`) | unchanged |
| Attachments | the key is inside the sealed `MediaBody` (`Kit/Crypto/SealedAttachment.swift:24-29`; `Kit/Log/Bodies/MediaBodies.swift:21`), so the message key covers it | unchanged. **Not verified:** the blob delivery path |

**The sealed entries still reach the newcomer** (Decision 6). Repair hands a room's entries to
anybody shown as in or invited (`Session/AppSession+HistoryRepair.swift:29-32`, `325-330`). Two rules
need them there. A removed person's entries count only if the chain reaches them
(`Kit/Log/RoomChains.swift:19-31`). A phone passes a key on only when it holds every entry the maker
named (`Session/AppSession+Peers.swift:189-196`). Keeping them off the phone needs an entry whose body
can be left behind while its signature is still checked (`Kit/Log/Entry.swift:60-76`). That is a
format change: Part B.

### 3.6 Second device, restore, and being let in again

- **A second device** gets the first device's keys in the catch-up record, and walks the standing
  links itself. Peers cut what they send it at the same start.
- **A restore** is a new device with nothing. Peers hand it keys from the start onwards
  (research-here §6).
- **Removed, then let in again.** The start belongs to the membership, and the second membership
  gets its own. The member keeps the keys they held the first time, so the new start closes only the
  stretch they were out.
- **No notes for old removals.** A phone does not append `removalNoted` for a removal that causally
  precedes its own admission or start record. The `earliest` notes feed the conflict order on every
  phone (`Kit/Log/Projection+Standing.swift:142-178`). Today `noteRemovals` notes anything it times
  (`Session/AppSession+TellingLast.swift:125-156`), so a newcomer's notes could reorder an old
  conflict. Read, not run.

---

## 4. One model for rooms and Outposts

| Today | After |
|---|---|
| `grantsOwed` computes a floor for a wall and `nil` for a room (`Session/AppSession+Peers.swift:142-145`, `156`) | one lookup, `readsFrom(in:)`, returning `beginning`, `owed` or `at(number, key)` |
| `Projection.outpostFloors` returns `[ParticipantID: UInt64?]` (`Kit/Log/Projection+Outpost.swift:23-31`) | returns the roster's type; an Outpost access entry also names the start key |
| `walkStopsShort(in:)` knows only walls (`Session/AppSession.swift:638-645`) | asks the shared lookup |
| `allowOutpost` turns the key and writes the new number (`Session/AppSession+Outpost.swift:363-371`) | one helper that turns a key and returns its number and key, sealed as §0.2 |
| A wall hides what it cannot open; a room shows "Not readable on this device." (`Kit/Log/Projection.swift:102-106`) | both hide what is causally before the start (§5.4) |

The entry types stay separate. Standing keys and links are for rooms only.

---

## 5. What a member reads

Every string below is copy. Each chunk gets a new pair of markers, with an id from
`python3 Scripts/copy-review.py new-id` and the status `NEEDS HUMAN REVIEW`. Any existing chunk whose
words change goes back to that status. All `Text` carries `bundle: .module`. The words follow
Griff's 2026-11-10 terms. Components are the ones `RoomAccessView` uses
(`UI/Screens/Membership/RoomAccessView.swift:39-143`). **The HIG pages for menus and sheets are read
before step 9**. I have not read them for this design.

### 5.1 The setting

A toolbar-menu item under "Who gets in" (`UI/Screens/Messaging/ConversationView+Menu.swift:113-119`)
opens a sheet like `RoomAccessView`. It never appears in a Solo. Every member can open it; only the
founder's rows are enabled (PROPOSED).

| Where | Words |
|---|---|
| Menu item and sheet title | What new members can read |
| Choice 1 | **Everything** — The whole room, back to its first message. |
| Choice 2 | **From when they join** — Only what is said after they are let in. |
| Section header | This is for people let in from now on. Invitations already sent keep what they said, and nobody already here loses anything. |
| Section footer | Someone who was here can still show or tell a new member what was said. New members' phones receive the record of who was invited, voted on, removed or left, but not what anyone said. |
| Not the founder | Only \(founder) can change this. |
| Alert title, on choosing Everything | New members will read everything |
| Alert message | Anyone let in while this is on receives the whole room, including what was said before they join. You can change it back, but not take back what they received. |
| Alert buttons | Let new members read everything · Cancel |

The "Only what is said after they are let in" line holds only if Decision 2 is yes. If it is no, the
words become "Mostly what is said after they are let in; messages written on a phone that had not
heard of it may be included." The symbol `clock.arrow.circlepath` is **not verified** against the
catalogue; `SymbolNameTests` and the lint check it. The same two choices go on the new-room screen
after the "who has to agree" section (`UI/Screens/Membership/NewRoomView.swift:110-176`).

### 5.2 The invitation

| Where | Words |
|---|---|
| Inviter, footer under "How long it stays good" (`UI/Screens/Membership/InviteView.swift:288-298`) | They will be able to read everything said in this room. / They will be able to read only what is said after they join. |
| Invited person, offer card (`UI/Screens/Membership/RedeemInviteView.swift:249-259`) | This invitation offers the whole room, back to its first message. / This invitation is for what is said after you join. |

All three places that issue an invitation go through `attest`
(`Session/AppSession+Membership.swift:113-125`), so the term is set there once.

### 5.3 The newcomer's first screen

`JoinPromptView` (`UI/Screens/Membership/JoinPromptView.swift:60-123`) shows the start that actually
applies, from `RoomGreeting` (`Kit/Model/ReadModel.swift:345`; built at
`Session/AppSession+Membership.swift:580-600`). It does not show what the invitation offered.

| Where | Words |
|---|---|
| Heading | What you can read |
| From joining | What has been said since you joined. |
| Everything | Everything said in this room. |

### 5.4 The top of the room

- **What is hidden is decided by position, not key number.** An entry is hidden if the winning
  `historyStart` causally follows it (`start.clock[entry.feedKey] >= entry.seq`, the test `hadSeen`
  uses at `Kit/Log/Projection+Standing.swift:162-164`). Anything later or concurrent is shown.
  Readable entries are shown normally. Unreadable ones show as "Not readable on this device."
  (Decisions 2 and 5). A removal written after the join under an older key is shown with its notice.
  The set feeds the same `outOfRoom` / `undrawn` inputs (`Kit/Log/Projection+Conversation.swift:6-19`;
  `Session/AppSession.swift:540-551`), behind `cached(_:_:_:)`.
- One new notice, at the winning record: "You can read this room from here." for the newcomer, and
  "\(name) can read this room from here." for everybody else.
- A rename after the join is still shown. `named` is set only when the founding entry is drawn
  (`Kit/Log/Projection+Conversation.swift:25-44`), so it is also set when that entry is passed over.

### 5.5 Names, and who reports reading

A member says again their name, photo, Focus, badge, **and read-receipt policy** when somebody in
the room has a start above the key their last announcement was sealed under. `reportingMembers`
keeps the last `readPolicy` each member wrote (`Kit/Log/Projection+Conversation.swift:144-155`),
and a policy is written only when it changes (`Session/AppSession+Notifications.swift:195`, `220`).
Without this, read marks from older members would never show on a newcomer's phone. It is one check
in the round, with no new entry type. The founder says theirs again under the same rule, which
covers "Only \(founder) can change this". The names of departed members stay unreadable, which
matters only to the hidden stretch.

### 5.6 A sentence that becomes untrue

`docs/TESTFLIGHT_LICENCE.txt:103`: "Admitting someone to a room gives them that room's entire history
from its first message." Replace with: "Admitting someone to a room gives them what the room's
setting allows: its entire history from its first message, or only what is said after they join.
Either way their phone receives the record of who was invited, removed or left."

---

## 6. Tests written first

Package suite, `InMemoryMailbox`, sessions from `TestSession.make()`, joined the way
`WaitingToBeLetInTests` does. A second device is `keychain.sibling()` + `approveNewDevice(_:)`.
Tests 0a and 0b are §0. Tests 1 to 13 are the guarantees.

`JoiningFromWhenTheyJoinTests`
1. A newcomer reads what is said after the join and nothing before, with two earlier members
   writing on both sides of it.
2. Their member list, name, rule and founder match the founder's.
3. **No grant to them from anybody carries a key below the start, a rival key at it, or a link at
   or below it.** Every grant is read out of the mailbox with the app's unpack, in a room of three
   where one phone is a round behind.
4. A phone that holds the admission but not the start record, or not an entry the admission's clock
   names, sends them nothing.
5. A phone without the founder's *everything* entry treats the room as *from when they join*.
6. Their second device reads the same, and what peers send it is cut at the same start.
7. After a recovery-key restore, the same.
8. Repair gives them nothing that opens below the start, and their phone is not left asking.
9. Changing the setting after they join changes nothing for them, in either direction.
10. Removed and let in again: they read what they held before and from the second join, and not the
    stretch between.

`WhoCanStartSomebodysHistoryTests`
11. A from-joining member invites a second identity, while the room is *from when they join* and
    again after it is switched to *Everything*, and writes its start at key 0. Its start is never
    below the inviter's.
12. A member offline at key 9 turns to m10, writes, turns to m11. The newcomer is settled at s10.
    The newcomer gets neither m10 nor m11 and cannot read the three messages. The same with the
    rival at F+1.
13. A removal sealed under a message key counts on no phone; a post sealed under a standing key
    shows on no phone.
14. A removed member's start record, setting change and older key are refused; a non-founder cannot
    change the setting.
15. An older *everything* invitation answered after a narrower one replaced it: from joining.
16. Two settlers at 10 and 11: the start is 10, and a later record at 12 from any member changes
    nothing. The inviter's two devices settling at 7 and 8: the start is 7, with one notice.
17. A record naming a number above the one it is sealed at, or at or below the establishing entry's,
    does not count.
18. A narrowing concurrent with an admission narrows it on every phone, whatever the `wallTime`s.

`TheStandingKeyTests`
19. The layout of a sealed membership entry and its mark, written out by hand, as `SealBindingTests`
    pins a payload.
20. Holding only the standing key for a number opens no message, key change or link at that number.
21. A walk of standing links reaches the founding entry from the start; a forged link from somebody
    who did not make that key is not followed; a rival found later reaches the newcomer by re-wrap.
22. A removal sealed under a rival standing key the newcomer lacks: the newcomer sends the removed
    person no key.
23. A removal naming fewer entries than the remover held: a from-joining member and a full-history
    member agree on who is in (a guarantee test, given Decision 3).

Others
24. The inviter leaves after inviting into a rule room; the founder admits; the newcomer gets a first
    key from whoever recorded the start.
25. A from-joining member sees every current member's name and the read marks of members who report
    them after one round.
26. A rename after the join is shown; notices before are not; a removal written after the join under
    an older key is shown.
27. A newcomer's `removalNoted` entries leave an earlier conflict's order unchanged.
28. `ProjectionCostTests` still holds with the mark and the standing walk.

---

## 7. Build order

One step at a time, each finished before the next, tests first. A cleanup is its own commit.

| # | What | Files | Proven by |
|---|---|---|---|
| 0 | Griff confirms §1 and the six decisions | — | — |
| 1 | §0.1: no key below a reader's floor | `Session/AppSession+Peers.swift:156` | test 0a |
| 2 | §0.2: a key change sealed under the key its link wraps | `Session/AppSession.swift:367-420`, `Session/AppSession+Membership.swift:650-664` | test 0b |
| 3 | The standing key, the mark, strict opening | `Kit/Crypto/EpochChain.swift`, `Kit/Crypto/SealedPayload.swift`, `Kit/Crypto/Identity.swift`, `Kit/Log/Payload.swift`, `Kit/Log/LogRenderer.swift` | 13, 19, 20 |
| 4 | Standing links and the walk; read receipts and Solo checks become standing; the line reads `standingLink` heads | `Kit/Log/Bodies/MembershipBodies.swift`, `Session/AppSession+Membership.swift:674-700`, `Kit/Log/Projection+Standing.swift:25-34` | 21, 23 |
| 5 | The setting, the term, the start in the roster | `Kit/Membership/MembershipAttestation.swift`, `Kit/Membership/RoomRoster.swift`, `Kit/Log/Payload+Making.swift` | 11, 14-18 at roster level |
| 6 | Handing keys from the start, the hold, the wait, the receiving side | `Session/AppSession+Peers.swift:120-200`, `322-352`, `Kit/Crypto/EpochGrant.swift:131-144`, `Session/AppSession.swift:638-645` | 3-8, 22 |
| 7 | Recording the start inline, the invitation's term, making and changing the setting | `Session/AppSession+Membership.swift:113-125`, `441-480`, `621-648`; `Session/AppSession+Sync.swift:398-407`; `Session/AppSession+Messaging.swift` | 1, 2, 9, 10, 12, 24 |
| 8 | What is shown, said again, and not noted | `Kit/Log/Projection+Conversation.swift`, `Kit/Model/RoomNotice.swift`, `Session/AppSession+Etiquette.swift`, `Session/AppSession+TellingLast.swift:143-156` | 25-28 |
| 9 | Screens and copy, after reading the HIG pages | `UI/Screens/Membership/*`, `UI/Screens/Messaging/ConversationView+Menu.swift` | lint, `copy-review.py report`, simulator with the software keyboard on |
| 10 | Docs | `docs/decisions.md` (Griff's sentences RULED with dates; the mechanism PROPOSED), `docs/crypto-brief.md`, `docs/open-questions.md`, `docs/roadmap.md`, `docs/TESTFLIGHT_LICENCE.txt:103` | read through |
| 11 | The rig | below | below |

**Bytes already written.** No reader of the old form. Fixtures that build attestations, grants,
sealed payloads or membership entries by hand are rewritten. Join tests that expect history name
*Everything*. Rig simulators start from fresh rooms by deleting the app. That means not using
`--reset-account`, which damages the Apple Account. `SealBindingTests` gains test 19's layout.

**On two Apple Accounts** (`docs/simulator-rig.md`): (1) a from-joining room: B shows only what
came after the join, the room's name and both members; (2) relaunch both: B's room is still there,
and A's re-sent grants carry nothing at or below the start; (3) how often a message lands under the
old key just after a join (Decision 5); (4) an *Everything* room and an Outpost from now still work.
Until these run, every sentence in §1 is "passes in the package suite, not run over iCloud". A third
member, a second identity, a rule room, a second device and a restore stay "package suite only"
until three accounts or hardware exist.

---

## 8. What the setting cannot change

- Somebody who was there can pass on what they read.
- It does not take anything back.
- A newcomer's phone receives the room's membership record from the beginning and holds the older
  messages sealed (Decisions 1 and 6).

---

## 9. Questions for Griff, each with a recommendation

Q1 to Q6 are the six on the first page: membership visible plus the mark; a start names one key;
read receipts and Solo checks become standing; the default; the message just after a join; old
messages kept off the phone.

**Q7. Time window** (§2.5). *Recommend:* not in the first tester build. If wanted, use the version
with no scheduled turn, labelled "Up to N days", and decide before that build.

**Q8. A narrowing concurrent with an invitation.** If the founder narrows while another member's
phone, not yet knowing, relays an *everything* confirmation, a third phone that has not received the
narrowing can hand everything before it does. The wait (§3.1) does not help here, because the
narrowing is not in the admission's clock. *Recommend:* require that an *Everything* start record be
written by the founder. Cost: an everything-joiner waits for the founder's phone, and a room whose
founder has left cannot admit them. The alternative is to accept this case, and the copy would have
to say so.

**Q9. If the founder has left, nobody can change the setting**, the same as "Who gets in"
(`Kit/Membership/RoomRoster.swift:217-220`). *Recommend:* decide both together later.

**Q10. A forged standing link.** A member can give a newcomer an invented standing key for an old
number, through a re-wrap, and seal their own membership entries under it. Only the newcomer's phone
opens those entries, so its member list differs. This gives the member no read power they lack
already. *Recommend:* accept re-wraps only from the maker of the key they wrap, where the newcomer
can check that. Otherwise reword G2 to "as long as the members whose links it follows are honest".

**Q11. The member who let somebody in never runs the app again.** The newcomer waits. *Recommend:*
`keyRotator` also settles after a day, measured by iCloud's stored time for the admission. **Not
verified** whether that time is available.

**Q12. Re-issue open invitations on a widening?** *Recommend:* no. The setting screen says
invitations keep their term.

**Q13. A departure does not end the invitations the person who left had made**
(`Kit/Membership/RoomRoster.swift:402-416`; a removal does, `:384`). This predates the design.
*Recommend:* end them on departure, in its own commit.

**Q14. May an inviter narrow one invitation, or may a part-way member be given everything later?**
*Recommend:* no screen for either yet.

---

## 10. What was and was not checked

- Read at the lines cited, on 2026-11-11: `advanceEpoch`, `append`, `oneWriteAtATime`,
  `rekeyBeforeWriting`, `grantsOwed`, `keysToPassOn`, `straysBelow`, `trustedKey`, the first-key rule,
  `adoptGrantsThatWaited`, `relayJoinConfirmations`, `decide`, `noteRemovals`, `EpochGrant.adopt`/`issue`,
  `EpochChain.hold`/`isAuthentic`, `SealedPayload.sealed`/`opened`, `LogRenderer.step`,
  `CausalOrder`, the roster's apply/removal/departure, `Projection+Standing` (claims, the line, notes,
  order), `reportingMembers`, `MediaBody`/`AttachmentReference`, `docs/decisions.md:4186-4200` and
  `6507-6510`.
- From the research files without re-reading: the old branch, the Outpost walk-through beyond the
  lines above, and the outside sources.
- **Inferred, not run:** both faults in §0, every behaviour of the new design, the member-list split
  in §3.4.
- **Not verified:** a restore helper in `TestSession`; iCloud's stored time reaching the roster; the
  symbol name; the blob delivery path; packet size with a standing-link entry per key turn.

---

## 11. Findings not taken, and why

Every blocker and major finding was checked against the code. They are taken above, except as
follows.

- **"The remover writes heads plus the hashes it saw into `RemovalBody.heads`" (finding on test 22,
  first fix).** Not taken. The extension exists because a modified remover can write `heads: []`
  (`docs/decisions.md:4186-4200`). It uses the remover's earlier signed statements, which the remover
  cannot take back. Moving the line into the removal hands it back to the remover. The other fix
  offered was taken instead: read receipts and Solo checks become standing, and the line reads heads
  from `standingLink` (§3.4, Decision 3).
- **"A newcomer's start is fixed by the first record that counts, in replay order."** Taken in part.
  Replay order breaks ties by `wallTime` (`Kit/Log/CausalOrder.swift:40-43`), a date a device chose.
  Taking the lowest valid start from the members who may write one does the same job, with no tie
  involved (§3.3).
- **"The inviter's own admission sits causally after the narrowing, so Q7's second gap closes."**
  Taken in part. The wait was adopted (§3.1), and the inviter's start cap closes the second-identity
  case (§2.3). The claim is not true in general: an inviter established before the narrowing has no
  such dependency. A narrowing concurrent with an admission remains, and it goes to Griff as Q8.
- **"Standing keys handed in grants" (the earlier draft's §3.4).** Replaced by standing links in the
  log, as the review proposed. That brings no grant, keychain, `PersistedState` or sibling-feed
  changes, and no re-sending of keys after every launch.
- **"Settle in the same call; drop 'a day'."** Taken, but dropping it leaves a newcomer waiting if the
  person who let them in never runs the app again. That is Q11, not an accepted limit.
- **"Measure the gap on the rig before it goes to Griff."** The measurement is rig step 3, which
  cannot run in a read-only job. The question goes to him now as Decision 5, with the measurement
  as its condition.

<!-- COPY END 51b36694 -->
