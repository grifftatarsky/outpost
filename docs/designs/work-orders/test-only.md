<!-- COPY BEGIN 98cdfe17 [NEEDS HUMAN REVIEW] -->

# Work order: plan step 10, what only tests call, and the name of the pair's base secret

> **A working design, written by agents on 2026-11-10 and 2026-11-11 and kept so the work need not be
> done again.** Nothing in it is a ruling. Where it names a file under `scratchpad/`, that was a
> working file and was not kept. Line numbers are from the commit it names and will drift.
> What is waiting on Griff is in [the Part B plan](../../part-b-plan.md).

Plan text, `docs/pre-testflight.md:129-130`: "Move the accessors only tests call out of the app, about
twenty of them. Rename `legacySecret(with:)`: it is the pair's base secret and in daily use."

The count is low. `CarpenterApp` has 30 members only tests call. The whole of
`Packages/Carpenter/Sources` has about 115. This order covers all of them in parts, so the work
can stop after any part and still be whole.

## How the list was made, and what it is worth

- Line numbers are from HEAD `9af603a` (branch `overnight-2026-10-31`). No Swift file under
  `Packages/Carpenter/Sources` or `App/Carpenter` was modified in the working tree when this was
  written. Four test files were being edited by another process at the time
  (`App/CarpenterTests/LivePairTests.swift`, `App/CarpenterTests/LivePairSendTests.swift`,
  `SealedWhileLockedTests.swift`, `TestScratch.swift`), so **find each line by the quoted text, not
  by its number**, and delete bottom-up within a file.
- Candidates came from two index stores, read without building:
  `Packages/Carpenter/.build/out` (macOS, written 2026-11-10 17:03, covers every file under
  `Sources` and `Tests`) and Xcode's store for the old checkout path (iOS, 2026-11-06, covers
  `App/Carpenter`, `App/CarpenterNotificationService`, `App/CarpenterTests`, `App/CarpenterUITests`).
  A member was kept as a candidate when no reference to it, or to anything it overrides, sat in app
  code outside another candidate.
- Every candidate was then checked by `grep` against the working tree: `Packages/Carpenter/Sources`
  minus `CarpenterKitTesting`, plus `App/Carpenter` and `App/CarpenterNotificationService`. A second,
  text-only pass over the working tree (declared names with no other token in app code) found 40
  uniquely named members. 39 were already on the list. The 40th, `forgetOwnContribution`, showed
  the index pass was skipping protocol requirements whose fake lives in `CarpenterKitTesting`; with
  that fixed it also turned up `HardwareKeys.publicKey(of:)`. Both are in E2.
- Not verified: nothing was compiled. A caller missed here fails the build, which is the safe way to
  be wrong. Members with common names (`isEmpty`, `count`, `entries(in:)`, `canonicalBytes`) rest on
  the two indexes, because text cannot tell one type's `isEmpty` from another's.
- The scripts and their output are in
  `/private/tmp/claude-501/-Users-grifftatarsky-projects-outpost/f313c3e3-558d-46ba-9bcc-c43ae72ae298/scratchpad/design/step-test-only-work/`
  (`q-all.txt` holds every reference the indexes know for each candidate).

Where a moved member goes: an extension in the package's test target, the way
`Packages/Carpenter/Tests/CarpenterKitTests/NameOptIn.swift:3-8` already extends `AppSession`.
`CarpenterKitTesting` is the wrong home for almost all of them: it imports `CarpenterKit` without
`@testable` (8 files, plain `import CarpenterKit`) and does not depend on `CarpenterApp`
(`Packages/Carpenter/Package.swift:30-34`), so it cannot reach `AppSession` or anything internal. The
one thing that does go there is `SentAttachment` (Part C).

---

## Part A. Rename `legacySecret(with:)` to `baseSecret(with:)`

What it is: `PairwiseSecret.derive(mine:theirs:)` with no address salts
(`AppSession+Addresses.swift:58-66`). `pairwiseSecret(with:)` is the salted one
(`AppSession+Membership.swift:68`).

Name: **`baseSecret(with:)`**, the plan's own words. Verified absent: `grep -rli baseSecret` over the
iPhoneSimulator27.2 SDK's `CryptoKit.framework`, `Foundation.framework` (headers and Swift
interface), `Security.framework`, `SwiftUI.framework`, the Swift standard library interface and
`usr/include` returns nothing, and `git grep -i baseSecret -- '*.swift'` returns nothing.

Every use (17 in code, 2 in docs, and one test helper named after it):

| File | Line | Change |
|---|---|---|
| `Sources/CarpenterApp/Session/AppSession+Addresses.swift` | 58 | `func legacySecret(with` → `func baseSecret(with` |
| same | 60, 64 | `cachedLegacySecrets` → `cachedBaseSecrets` |
| same | 138 | `let legacy = legacySecret(with: peer.them)` → `let base = baseSecret(with: peer.them)` |
| same | 143 | `Peer(secret: legacy,` → `Peer(secret: base,` |
| `Sources/CarpenterApp/Session/AppSession.swift` | 131 | `cachedLegacySecrets` → `cachedBaseSecrets` (the declaration) |
| same | 356 | `legacySecret(with: owner)` → `baseSecret(with: owner)` |
| `Sources/CarpenterApp/Session/AppSession+Attachments.swift` | 400, 404, 418, 423, 436 | `legacySecret(with:` → `baseSecret(with:` |
| `Sources/CarpenterApp/Session/AppSession+Pairs.swift` | 48, 195, 208 | same |
| `Tests/CarpenterKitTests/AnEntryOpensOnlyInItsOwnRoomTests.swift` | 67, 111 | same |
| `Tests/CarpenterKitTests/ChangingYourHiddenAddressTests.swift` | 77 | same |
| same | 76, 84, 85, 279 | the file's own helper `legacy(_:with:)` → `base(_:with:)`: the declaration and its three calls |
| `Tests/CarpenterKitTests/EachPairHasASpaceOfItsOwnTests.swift` | 80, 82, 102 | same |
| `Tests/CarpenterKitTests/MediaTests.swift` | 293 | same |
| `docs/style.md` | 48 | `` `legacySecret(with:)` `` → `` `baseSecret(with:)` ``. The chunk is `91a604a1`, already `NEEDS HUMAN REVIEW`; leave the marker as it is. |
| `docs/pre-testflight.md` | 129-130 | the plan line itself; see "When finished" |

(All paths under `Packages/Carpenter/` unless they start with `docs/`.) After the edit,
`git grep -n -i legacy -- 'Packages/*.swift' 'App/*.swift'` should return only the six lines in
`DeviceEnrolmentTests.swift:350-358` (`legacyDevice`, `legacySibling`), which are a different thing
and stay.

---

## Part B. `CarpenterApp`: 27 members move to the test target, 2 are deleted

### B1. New file `Packages/Carpenter/Tests/CarpenterKitTests/SessionPeeks.swift`

Exactly this. Bodies are the app's, with `public` dropped; `hasAnsweredSoloCheckQuestion` reads the
stored field so that `MemberPreferences.requiresSoloCheckAnswer` can go too (B2), and
`close(pairWith:through:)` drops its log line so the file needs no `import os`. The 30th member,
`PushArrivals.isListening`, reads a private field and is in E1.

```swift
import Foundation

@testable import CarpenterApp
@testable import CarpenterKit

extension AppSession {
    var entryCount: Int { replica.entryCount }

    func epochsHeld(in room: RoomID) -> Int { chains[room]?.knownEpochs.count ?? 0 }

    func epoch(of room: RoomID) -> EpochNumber? { chains[room]?.highestKnownEpoch }

    func knowsIdentity(of person: ParticipantID) -> Bool {
        replica.registry(for: person)?.identity != nil
    }

    func hasMet(_ person: ParticipantID) -> Bool {
        projection.met?.contains(person) ?? true
    }

    func holdsAttachment(_ id: AttachmentID) async -> Bool {
        (try? await storage.media.sealed(for: id)) != nil
    }

    func isBlocked(_ person: ParticipantID) -> Bool {
        persisted.preferences.isBlocked(person)
    }

    var hasAnsweredAboutRestores: Bool {
        persisted.preferences.hasAnswered(\.toldAboutRestores)
    }

    var answerStampAboutRestores: Date? { persisted.preferences.toldAboutRestores?.stamp.at }

    var sharesName: Bool { persisted.preferences.isSharingName }
    var showsOthersNames: Bool { persisted.preferences.isShowingOthersNames }

    func setSharing(_ sharing: NameAndAvatarSharing) async {
        await setShowsOthersNames(sharing.showsOthersNames)
        await setShowsOthersAvatars(sharing.showsOthersAvatars)
        await setSharesAvatar(sharing.sharesAvatar)
        await setSharesName(sharing.sharesName)
    }

    func deviceName(_ device: DeviceID) -> String? {
        persisted.preferences.name(of: device)
    }

    func revoke(_ device: DeviceID) async throws {
        try await revoke([device])
    }

    var hasAnsweredSoloCheckQuestion: Bool {
        persisted.preferences.requiresSoloCheck != nil
    }

    func ownInvitation(to room: RoomID) -> AcceptedInvitation? {
        persisted.acceptedInvitations.last { $0.attestation.room == room }
    }

    func announcedName(of author: ParticipantID, in room: RoomID) -> String? {
        projection.announcedName(of: author, in: room)
    }

    func announcedPhoto(of author: ParticipantID, in room: RoomID) -> AttachmentReference?? {
        projection.announcedPhoto(of: author, in: room)
    }

    func removal(from room: RoomID) -> RoomRoster.Removal? {
        guard let enrolment else { return nil }
        return roster(of: room).removal(of: enrolment.identity.id)
    }

    func post(_ media: PreparedMedia, through mailbox: any MediaMailbox) async throws {
        try await post([media], through: mailbox)
    }

    func lastFocusStatus(of author: ParticipantID, in room: RoomID) -> FocusStatusBody? {
        projection.lastFocusStatus(of: author, in: room)
    }

    func isReportingDisplaying(in room: RoomID) -> Bool {
        persisted.preferences.isReportingDisplaying(in: room)
    }

    func publishedTally(on post: OutpostPost) -> Int? {
        projection.commentTally(
            for: post.id.entry, by: post.author.id, opening: payloadOpener())
    }

    func wantsOutpostBellFrom(_ person: ParticipantID) -> Bool {
        persisted.wantsOutpostBell.contains(person)
    }

    func isNotified(about person: ParticipantID) -> Bool {
        persisted.preferences.isNotified(about: person)
    }

    var pairsJoined: Set<ParticipantID> {
        Set(persisted.pairBook.compactMap { peer, entry in
            entry.joinedSpace != nil && entry.joinedSpace == link(for: peer)?.url ? peer : nil
        })
    }

    func close(pairWith peer: ParticipantID, through mailbox: any Mailbox) async {
        guard let pairs = pairs() else { return }
        do { try await mailbox.close(peer, in: pairs) } catch { return }
        persisted.pairBook[peer] = nil
    }
}
```

Everything the file touches is internal or public today: `persisted` (`AppSession.swift:99`),
`replica` (:100), `chains` (:108), `storage` (:96), `projection` (:302), `payloadOpener()`
(`AppSession+Membership.swift:21`), `link(for:)` (`AppSession+Pairs.swift:159`), `pairs()`
(`AppSession+Pairs.swift:43`).

### B2. Delete from the app

Delete each range and one of the blank lines beside it. No test call site in the package changes.

| # | File (`Sources/CarpenterApp/…`) | Lines | First line of the range | Package tests that call it (17:03 index) |
|---|---|---|---|---|
| 1 | `Session/AppSession.swift` | 94 | `public var entryCount: Int { replica.entryCount }` | EntrySync, OutpostReview, PerDeviceKeys, ReadReceipt, SyncFromTheApp (13) |
| 2 | `Session/AppSession.swift` | 338-340 | `public func hasMet(_ person: ParticipantID) -> Bool {` | AnonymousComment (2) |
| 3 | `Session/AppSession+Attachments.swift` | 43-45 | `public func holdsAttachment(_ id: AttachmentID) async -> Bool {` | 8 files (27); also the live suite, B3 |
| 4 | `Session/AppSession+Etiquette.swift` | 58-60 | `public func isBlocked(_ person: ParticipantID) -> Bool {` | Media (2) |
| 5 | `Session/AppSession+Etiquette.swift` | 104-108 | `var hasAnsweredAboutRestores: Bool {` through `var answerStampAboutRestores…` | TheFakeIsNoEasier (5) |
| 6 | `Session/AppSession+Identity.swift` | 359-360 | `public var sharesName: Bool {…}` and `public var showsOthersNames: Bool {…}` | Blurb, PrivacyCheckup, Sharing (8). Keep `sharing`, `sharesAvatar`, `showsOthersAvatars`: the shell reads them. |
| 7 | `Session/AppSession+Identity.swift` | 404-409 | `public func setSharing(_ sharing: NameAndAvatarSharing) async {` | BeingToldAboutARestore, PrivacyCheckup (4) |
| 8 | `Session/AppSession+Identity.swift` | 513-515 | `public func deviceName(_ device: DeviceID) -> String? {` | NamingYourDevices (13) |
| 9 | `Session/AppSession+Identity.swift` | 560-562 | `public func revoke(_ device: DeviceID) async throws {` | 12 files (24). Keep `revoke(_ devices: [DeviceID])` at 564: `App/Carpenter/AppRootView+Ready.swift:525` calls it. |
| 10 | `Session/AppSession+Membership.swift` | 11-15 | `func epochsHeld(in room: RoomID) -> Int {…}` and `func knowsIdentity(of…` | 4 files (15); InvitationInvariant (1) |
| 11 | `Session/AppSession+Membership.swift` | 356-358 | `public var hasAnsweredSoloCheckQuestion: Bool {` | SoloVerification (2) |
| 12 | `Session/AppSession+Membership.swift` | 437-439 | `public func ownInvitation(to room: RoomID) -> AcceptedInvitation? {` | PhraseCommitment, SoloVerification, WaitingToBeLetIn (11) |
| 13 | `Session/AppSession+Membership.swift` | 482 | `public func epoch(of room: RoomID) -> EpochNumber? {…}` | Leaving, Removal, SilentFailure, SyncFromTheApp (25); live suite, B3 |
| 14 | `Session/AppSession+Membership.swift` | 486-492 | `public func announcedName(of…` and `public func announcedPhoto(of…` | SyncFromTheApp, WallIsNotARoom, PhotoSharing (11) |
| 15 | `Session/AppSession+Membership.swift` | 611-614 | `public func removal(from room: RoomID) -> RoomRoster.Removal? {` | Removal (1) |
| 16 | `Session/AppSession+Messaging.swift` | 100-102 | `public func post(_ media: PreparedMedia, through…` | OutpostAudience, OutpostEditing, OutpostPhoto (9). Keep the array form at 104: `App/Carpenter/AppRootView+Media.swift:45` calls it. |
| 17 | `Session/AppSession+Messaging.swift` | 586-590 | `public func reveal(_ message: MessageID) async {` | SoftDelete (1). **Deleted, not moved**: see B4. |
| 18 | `Session/AppSession+Notifications.swift` | 61-63 | `public func lastFocusStatus(of…` | FocusStatus, WallIsNotARoom (3) |
| 19 | `Session/AppSession+Notifications.swift` | 205-207 | `public func isReportingDisplaying(in room: RoomID) -> Bool {` | WhoHasReadIt (10) |
| 20 | `Session/AppSession+Outpost.swift` | 250-253 | `public func publishedTally(on post: OutpostPost) -> Int? {` | AnonymousComment (2) |
| 21 | `Session/AppSession+Outpost.swift` | 263-269 | `public func wantsOutpostBellFrom(_…` and `public func isNotified(about…` | OutpostUnseen (6) |
| 22 | `Session/AppSession+Pairs.swift` | 153-157 | `public var pairsJoined: Set<ParticipantID> {` | BlockingInARoomOfTwo, EachPairHasASpaceOfItsOwn (3); live suite |
| 23 | `Session/AppSession+Pairs.swift` | 260-269 | `public func close(pairWith peer: ParticipantID, through…` | EachPairHasASpaceOfItsOwn:140 (1); live suite |
| 24 | `Session/RootDecisions.swift` | 61 | `public var messageForMember: String? { nil }` | RootDecisions (1). **Deleted**: see B4. |
| 25 | `Sources/CarpenterKit/Sync/MemberPreferences.swift` | 126 | `public var requiresSoloCheckAnswer: Bool? { requiresSoloCheck?.value }` | reached only through #11; no test names it |

App-side evidence for all of them: `git grep -nwE '<name>'` over the three app paths returns only the
declaration, or lines that call a different thing with the same name
(`persisted.preferences.isBlocked(` at `AppSession+Etiquette.swift:46,53,72`;
`projection.announcedName(` at `AppSession+Etiquette.swift:38`; `projection.lastFocusStatus(` at
`AppSession+Notifications.swift:78`; `wanted.sharesName` at `App/Carpenter/AppRootView+Privacy.swift:72`;
`AppRootView.deviceName` at `App/Carpenter/HardwareName.swift:12,16`).

### B3. The live suite, `App/CarpenterTests`, is a different target and cannot see that file

It already has `@testable import CarpenterApp`. Change the call sites to read what the peek read:

| File | Now | Becomes |
|---|---|---|
| `LivePairSendTests.swift:56`, `:60` | `try #require(ann.epoch(of: room))` | `try #require(ann.chains[room]?.highestKnownEpoch)` |
| `LivePairSendTests.swift:109` | `ben.epoch(of: room) == held` | `ben.chains[room]?.highestKnownEpoch == held` |
| `LivePairTests.swift` (line 93 at time of writing) | `alice.pairsJoined.contains(bobID)` | `alice.persisted.pairBook[bobID].map { $0.joinedSpace != nil && $0.joinedSpace == alice.link(for: bobID)?.url } == true` |
| `LivePairTests.swift` (117) | `await alice.close(pairWith: bobID, through: cloud)` | `try? await cloud.close(bobID, in: pairs)` (`pairs` is Alice's, declared at line 103 of the same test) |
| `LivePairTests.swift` (152) | `{ await bob.holdsAttachment(photo) }` | `{ (try? await bob.storage.media.sealed(for: photo)) != nil }` |

Both files are being edited by another process. Read them fresh before touching them.

### B4. The two that are deleted

- **`AppSession.reveal(_:)`**. No screen can show one hidden message again; the app offers
  `revealHidden(in:)` and `revealAllHidden()` (`App/Carpenter/AppRootView+Ready.swift:85,123`). In
  `Tests/CarpenterKitTests/SoftDeleteTests.swift:47` change `await alice.reveal(target.id)` to
  `await alice.revealHidden(in: room)`. One message is hidden in that room, so the two assertions
  after it hold unchanged (inferred from lines 36-50; run the test).
- **`SyncRound.Outcome.messageForMember`**. It returns `nil` always. Delete the test
  `failuresAreNotMemberFacing` (`Tests/CarpenterKitTests/RootDecisionsTests.swift:110-117`), which
  asserts only that.

---

## Part C. `CarpenterKit`, `CarpenterMedia`, `CarpenterUI`: 38 members move

None of these has a caller in app code. Each uses only public or internal members, so it moves
verbatim: cut the range, drop `public`, paste inside an extension of the named type.

### C1. New file `Packages/Carpenter/Tests/CarpenterKitTests/KitPeeks.swift`

Header: `import Foundation`, then `@testable import CarpenterKit`. One `extension` per type, in this
order. "→" marks the three bodies that must change because the original reads private state.

| Type | Member | Cut from (`Sources/CarpenterKit/…`) | Package tests that use it |
|---|---|---|---|
| `AppLock` | `func remainingWait(at:)` | `Crypto/AppLock.swift:102-106` | AppLock (1) |
| `AppLock` | `mutating func unlock(with:at:)` | `Crypto/AppLock.swift:130-135` | AppLock (20). See "For Griff" 3. |
| `DeviceCertificate` | `static func issue(for device: DeviceKeys, by:at:approvedBy:)` | `Crypto/DeviceCertificate.swift:60-67` | 17 files (65). Keep the `for devicePublicKey: Data` form at 40: `AppSession+Approval.swift:26` calls it. |
| `DeviceRegistry` | `func storedAt(_:)` | `Crypto/DeviceRegistry.swift:113` | WritingOldDates (2). → body becomes `storedTimes[digest]` (`stored` is private; `storedTimes` at :111 is public) |
| `DeviceRegistry` | `mutating func admit(_:)` | `Crypto/DeviceRegistry.swift:144-146` | 5 files (16) |
| `DeviceRegistry` | `mutating func revoke(_:)` | `Crypto/DeviceRegistry.swift:161-163` | DeviceApproval, DeviceTrust (8) |
| `VaultKeeper` | `func create(code:usingBiometrics:recovery:)` | `Crypto/Vault.swift:247-249` | TheLockSealsWhatThisPhoneKeeps (2) |
| `Entry` | `static func append(to:…payload: SealedPayload…)` | `Log/Entry.swift:83-96` | 6 files (21) |
| `Entry` | `static func append(to:…payload: Payload, at:sealedWith:…)` | `Log/Entry.swift:129-146` | 11 files (15). The app calls the `after:` forms (`AppSession.swift:406`). |
| `RenderedEntry` | `var isEdited` | `Log/LogRenderer.swift:48` | EditingAndWithdrawing, LogRenderer (4) |
| `LogRenderer` | `static func render(_:using:)` | `Log/LogRenderer.swift:70-72` | 19 files (58) |
| `LogRenderer` | `static func render(_:opening:)` | `Log/LogRenderer.swift:74-78` | reached only through the one above. The app calls `render(_:reading:)` (`AppSession.swift:307`). |
| `PayloadType` | `static let allKnown` | `Log/Payload.swift:55-60` | 4 files (5) |
| `Replica` | `var hasDiverged` | `Log/Replica.swift:73` | Convergence, MultiDevice, Replica (5) |
| `Replica` | `mutating func admit(_:)` | `Log/Replica.swift:93-95` | 8 files (16) |
| `Replica` | `mutating func revoke(_:)` | `Log/Replica.swift:108-110` | HistoryRepair, MultiDevice, Replica (4) |
| `Replica` | `func entries(in:)` | `Log/Replica.swift:466-468` | 5 files (12). Keep `entries(in:after:)`: `AppSession+Sync.swift:444`. |
| `Replica` | `func ordered()` | `Log/Replica.swift:470-472` | Convergence, Storage, Sync (12) |
| `VectorClock` | `var isEmpty` | `Log/VectorClock.swift:31` | AppSession, Entry, WhatARepairRequestCanCost (3). → body becomes `positions.isEmpty` (`frontier` is private, :16; `positions` at :29 is public) |
| `InvitationLifetime` | `var isIndefinite` | `Membership/InvitationLifetime.swift:36-42` | InvitationLifetime (4) |
| `RoomRoster.PendingInvitation` | `var isIndefinite` | `Membership/RoomRoster.swift:176` | InvitationLifetime (2) |
| `Connection` | `var isOnlyByOutpost` | `Model/Connection.swift:16` | Connection (1) |
| `OutpostAccess` | `func standing(for:)` | `Model/OutpostAccess.swift:119-121` | AccessWindow (2) |
| `ReciprocalAccess` | `var isOneSided`, `var yourStanding` | `Model/ReciprocalAccess.swift:22`, `:24` | ReciprocalAccess (7) |
| `RoomsListOrganisation` | `func organisation(of:)` | `Model/RoomOrganisation.swift:140` | RoomOrganisation (1) |
| `SearchResults` | `var isEmpty` | `Model/SearchResults.swift:68-70` | Search (4) |
| `PersonAvatarStore` | `func loadShared(for:)` | `Storage/AvatarStore.swift:138` | Nickname (3) |
| `TestProfileStore` | `var setAsideURLs` | `Storage/TestProfiles.swift:113-120` | TestProfiles (2) |
| `SyncSession` | `static func recentTags(for:at:)` | `Sync/SyncSession.swift:207-209` | BlockingInARoomOfTwo, EachPairHasASpaceOfItsOwn, WhoCanTellYouWhereToReadSomebody (4); live suite, C4 |
| `SyncSession` | `func receive(as:into:meeting:at:signing:alreadyTaken:)` | `Sync/SyncSession.swift:620-632` | Sync (6). The app calls `collect`, `integrate` and `acknowledge` itself. |

### C2. New file `Packages/Carpenter/Tests/CarpenterKitTests/MediaPeeks.swift`

Header: `import AVFoundation`, `import Foundation`, `import ImageIO`, `import CarpenterMedia`.

| Type | Member | Cut from (`Sources/CarpenterMedia/…`) | Tests |
|---|---|---|---|
| `ImagePreparer` | `static let harmlessExif` | `ImagePreparer.swift:119-123` | used only by the next row |
| `ImagePreparer` | `static func identifyingMetadata(of:)` | `ImagePreparer.swift:125-139` | ImagePreparer, VideoPreparer (5) |
| `ImagePreparer` | `static func size(of:)` | `ImagePreparer.swift:141-148` | ImagePreparer, VideoPreparer (4) |
| `VideoPreparer.FitPlan` | `func expectedBytes(over:)` | `VideoPreparer.swift:95-97` | VideoPreparer (1) |
| `VideoPreparer` | `static func identifyingMetadata(of:)` | `VideoPreparer.swift:372-394` | VideoPreparer (8) |

`CLAUDE.md:284` and `docs/epics/content-and-composer.md:86` name `identifyingMetadata(of:)` as the
contract a test holds the preparer to. Both stay true: the function is the test's.

### C3. `WCAG.passes(_:on:at:)` and `SentAttachment`

- `Sources/CarpenterUI/Theme/Contrast.swift:72-76`: move into
  `Tests/CarpenterKitTests/ContrastAuditTests.swift` as `extension WCAG { static func passes… }` at
  the end of the file (its only user, lines 461-463; the file has `@testable import CarpenterUI`).
- `Sources/CarpenterKit/Platform/MediaMailbox.swift:57-65`, `public struct SentAttachment`: move the
  whole struct, still `public`, to the end of `Sources/CarpenterKitTesting/Fakes.swift`. Its only users
  are that file (lines 193-223) and `NobodyButTheSenderClearsAPhotoTests.swift`, which imports
  `CarpenterKitTesting` (line 3).

### C4. The live suite again

| File | Now | Becomes |
|---|---|---|
| `App/CarpenterTests/LivePairTests.swift:3` | `import CarpenterKit` | `@testable import CarpenterKit` |
| `App/CarpenterTests/LivePairTests.swift` (180) | `SyncSession.recentTags(for: bob.peers()[0], at: Date())` | `Set(SyncSession.recentWindows(for: bob.peers()[0], at: Date()).keys)` |
| `App/CarpenterTests/LiveSiblingFeedTests.swift:225-226` | `DeviceCertificate.issue(for: newcomer, by: identity, at: Date(), approvedBy: existing)` | `DeviceCertificate.issue(for: newcomer.publicKey, sealingKey: newcomer.sealingPublicKey, by: identity, at: Date(), approvedBy: existing)` |
| `App/CarpenterTests/LiveSiblingFeedTests.swift:330` | `DeviceCertificate.issue(for: tablet, by: identity, at: Date(), approvedBy: phone)` | `DeviceCertificate.issue(for: tablet.publicKey, sealingKey: tablet.sealingPublicKey, by: identity, at: Date(), approvedBy: phone)` |

---

## Part D. Deleted, with the test lines that go with them

Each is either unused by the app and trivially replaced in its test, or tested for a promise the app
never makes.

| # | Delete | Test change |
|---|---|---|
| 1 | `Sources/CarpenterKit/Crypto/ShortAuthenticationString.swift:63`, `public static let nonceBytes = 32`. `nonce()` on the next lines does not use it. | `VerificationPhraseTests.swift:108`: `JoinCommitment.nonceBytes` → `32` |
| 2 | `Sources/CarpenterKit/Presentation/AccessWindowsCopy.swift:4-6`, `lines(for:)` | `AccessWindowTests.swift:193-195`: `let lines = [AccessWindow(from: march, until: july), AccessWindow(from: july)].map(AccessWindowsCopy.line(for:))` |
| 3 | `Sources/CarpenterUI/Components/Messaging/EmojiCatalogue.swift:49`, `public var count` | `EmojiCatalogueTests.swift:14`: both `catalogue.count` → `catalogue.all.count` |
| 4 | `Sources/CarpenterUI/Screens/Membership/InviteScanning.swift:58-72`, the whole `enum ScanAttempt`. No view uses it. | delete the test `theSystemIsAskedOnce`, `InviteScanningTests.swift:47-53` |
| 5 | `Sources/CarpenterKit/Log/Payload.swift:91-100` (`Payload.canonicalBytes`), `:71-73` (`PayloadType.canonicalBytes`), and `Sources/CarpenterKit/Crypto/Identity.swift:278` (`static let payload = "carpenter.payload.v1"`). Nothing seals or signs over these bytes: `Entry.swift:74` uses `SealedPayload.canonicalBytes`. `docs/` does not mention the domain string. | delete the test `absentIsNotEmpty`, `EntryTests.swift:169-175` |
| 6 | `Sources/CarpenterKit/Membership/MembershipAttestation.swift:194-207`, the whole `extension IdentityPublicKeys` (`encoded()`, `decoded(from:)`). `encoded()` has no caller at all since `5006c43`; `decoded(from:)` has only the test. | `PastedCodeTests.swift:49-53`: the three `IdentityPublicKeys.decoded(from:` → `JoinerCode.decoded(from:`, which is what the app decodes (`AppSession+Membership.swift:185`). Not verified that all three still throw; run the test. |
| 7 | `Sources/CarpenterKit/Presentation/PostTags.swift:48-56`, `index(of:)` | delete the test `indexing`, `PostTagsTests.swift:28-39` |
| 8 | `Sources/CarpenterKit/Log/VectorClock.swift:46-53`, `happensBefore(_:)` and `isConcurrent(with:)` | delete the tests `happensBefore`, `irreflexive`, `concurrency`, `VectorClockTests.swift:53-85` |
| 9 | `Sources/CarpenterCloudKit/CloudKitRecords.swift:18-20`, `PacketRecord.read(_:)`. The mailbox calls `PacketWire.packet(from:)` itself (`CloudKitMailbox+Packets.swift:53, 97`). | `CloudKitPacketRecordTests.swift:33`: `PacketRecord.read(record)` → `PacketWire.packet(from: PairIndex.Cached(record).fields)`. The file already has `@testable import CarpenterCloudKit`. |

---

## Part E. Left where it is in this step

### E1. Reads private state, so it cannot move without widening something

Moving these means turning `private` into `internal` in the app, which is worse than the accessor.
Leave them, or take "For Griff" 1.

| Member | Where | Private thing it reads | Tests |
|---|---|---|---|
| `PushArrivals.isListening` | `Sources/CarpenterApp/Push/PushArrivals.swift:30` | `handler` (:8) | PushArrivals (2) |
| `Replica.entryCount` | `Sources/CarpenterKit/Log/Replica.swift:66-68` | `feeds` (:51). `ReplicaTests.swift:328,334` use it to check `allEntries` against the feeds. | 5 files (11), plus `SessionPeeks.entryCount` |
| `SignatureChecks.count` | `Log/SignatureChecks.swift:13` | `passed` (:9) | SignatureChecks (5) |
| `Identity.withoutRecovery` | `Crypto/Identity.swift:132-135` | `signingKey`, `agreementKey` (:183, :187) | ARecoveryKey, DeviceApproval (2) |
| `RoomRoster.refusals`, `invited`, `wasRescinded(_:)`, `confirmed`, `hasRefused(_:by:)`, `isUnanimous(_:)` | `Membership/RoomRoster.swift:20, 80, 85, 89, 131, 255` | `refusalsByInvitation` (:14), `rescinded` (:42), `established` (:38), `confirmations` (:40), `refusers(of:)` (:28), `admitters(of:)` (:24). `wasRescinded` is public-only but `confirmed` calls it. | 10 files (26) |
| `ReadEvidence.isEmpty` | `Model/ReadEvidence.swift:32` | `marks` (:14) | ReadEvidence (1) |
| `PersonAvatarStore.load(for:)`, `removeAll()` | `Storage/AvatarStore.swift:49-51, 140-143` | `url(for:)` (:37), `directory` (:29) | Nickname (7) |
| `MemoryMediaStore.count` | `Storage/MediaStore.swift:75` | `files` (:66) | Media (1) |
| `LocalPairStore.forgetPacket(_:)`, `change(_:_:at:)`, `allRecords`, `everySentPacket`, `everyStoredCopy` | `Platform/LocalPairStore.swift:169, 177, 202, 354, 374` | `spaces` and `packetOrder` are `public private(set)` (:21-22); `counterpart(of:)` is private (:349) | Called only by the fakes, `Sources/CarpenterKitTesting/Fakes.swift:164-368`. |

### E2. Logic that only tests run

These are not accessors. Each is a piece of behaviour with tests and no caller, or a second way of
doing something the app does differently. Moving them would hide that. See "For Griff" 2.

| Member | Where | What the app does instead | Tests |
|---|---|---|---|
| `FileLogStore.compact()` | `Storage/LogStore.swift:240-246` | nothing calls it. `docs/decisions.md:1398` says `append` rewrites a damaged log itself; that was read in the doc, not re-checked in the code. | Storage, WhatIsWrittenDownStaysReadable (5) |
| `RoomsListOrganisation.merged(with:)`, with `RoomOrganisation.merged(with:)` and `RoomTag.merged(with:)` | `Model/RoomOrganisation.swift:233-243, 112, 89` | no caller found: `organisation` is read from and written to `persisted` (`AppSession.swift:596`, `AppSession+Membership.swift:737-738`) and does not appear in `AppSession+DeviceSync.swift` | RoomOrganisation (12) |
| `OutpostAccess.merged(with:)`, and the case `Origin.inherited` | `Model/OutpostAccess.swift:145-151, 71` | no caller; access is rebuilt from entries (`Log/Projection+Outpost.swift:17`) | OutpostAccess (6) |
| `ComparisonCode.between(_:_:)` | `Crypto/ShortAuthenticationString.swift:95-100` | `AppSession.comparisonCode(with:)` builds and sorts the two halves itself (`AppSession+Verifying.swift:35-42`) | ComparisonCode "Both phones show the same two halves, in the same order" (2) |
| `RoomUpdateLevel.namesThePerson`, `namesTheRoom`, `namesWhatHappened` | `Presentation/MessagingNotificationChoices.swift:30-32` | no caller | WhatTheAppIconMeans (6) |
| `MembershipAttestation.encoded()`, `decoded(from:)` | `Membership/MembershipAttestation.swift:209-222` | the app encodes and decodes `Invite` and `JoinerCode` only | Membership, four tests at 410-463 titled as promises about "an invite" (8) |
| `EntrySync.forgetOwnContribution()` | requirement `Sync/EntrySync.swift:13`; `Sources/CarpenterCloudKit/CloudKitEntrySync.swift:256`; fake `Sources/CarpenterKitTesting/InMemoryEntrySync.swift:162` | no caller in the app | live suite only, `App/CarpenterTests/LiveSiblingFeedTests.swift`, 8 calls that clean the zone up |
| `HardwareKeys.publicKey(of:)` | requirement `Crypto/Vault.swift:31`; `Sources/CarpenterKeychain/SecureEnclaveKeys.swift:46`; `App/Carpenter/OnDiskStorage.swift:82`; fake `FakeHardwareKeys.swift:41` | no caller in the app | `OutpostsOwnLockSealsThisPhoneTests.swift:140` (1). Belongs with the lock work, plan step 4. |

---

## Part F. Looked test-only in the indexes, is not. Do not touch.

The indexes are older than today's commits. `grep` on the working tree shows a caller for each:

- `AppSession.invite(_:joining:through:lasting:)` (`AppSession+Membership.swift:195`):
  `App/Carpenter/AppRootView.swift:588`. `publicKeys(of:)` (:85) is called from it at :199.
- `AppSession.send(_:to:after:)` (`AppSession+Messaging.swift:36`): `App/Carpenter/AppRootView+Ready.swift:135`.
- `SessionStorage.sealed(by:)` (`AppSession.swift:31`), `SealedDocumentStore`, `SealedKeychainStore`:
  `App/Carpenter/OnDiskStorage.swift:39`, `App/CarpenterNotificationService/NotificationService.swift:68`.
- `VaultKeeper.init(keychain:hardware:vault:rounds:checksBiometricsItself:)` (`Vault.swift:217`):
  `App/Carpenter/OnDiskStorage.swift:61, 65`.
- `AppLockController.onKeptChanged`, `onReopened`, `vaultRecoverySecret`:
  `App/Carpenter/AppRootView+Lock.swift:75-77`.

No property is written only by tests.

---

## Order of work, and commits

One commit per part, in this order: A, B, C, D. A is a rename and nothing else. B, C and D are each a
cleanup with no change to what a member sees; say so in the message. E is not part of this step.

## Done looks like

1. `git grep -n legacySecret` and `git grep -n cachedLegacySecrets` return only this plan line in
   `docs/pre-testflight.md`, until that line is ticked.
2. For every name in B2, C1, C2, C3 and D, `git grep -nw <name> -- Packages/Carpenter/Sources
   App/Carpenter App/CarpenterNotificationService` returns no declaration. (`SentAttachment` shows in
   `Sources/CarpenterKitTesting/Fakes.swift` only. `isEmpty`, `isIndefinite`, `admit`, `revoke`,
   `issue`, `append`, `render`, `entries`, `post`, `close` and `canonicalBytes` are names other
   things have; check those by opening the line ranges above.)
3. Three new files exist in `Tests/CarpenterKitTests`: `SessionPeeks.swift`, `KitPeeks.swift`,
   `MediaPeeks.swift`. No file under `Sources` gained a line except `CarpenterKitTesting/Fakes.swift`.
4. No test call site in `Tests/CarpenterKitTests` changed except the lines named in B4 and D.
5. The package suite, the lint, the iOS build and the app-bundle suite all pass (below), and the
   build log has no new warning.

## Tests to run

While working, filtered. After A: `swift test --filter 'AnEntryOpensOnlyInItsOwnRoomTests|ChangingYourHiddenAddressTests|EachPairHasASpaceOfItsOwnTests|MediaTests'`.
After B: add `PrivacyCheckupTests|SoftDeleteTests|RootDecisionsTests|NamingYourDevicesTests|SoloVerificationTests|OutpostPhotoTests|WhoHasReadItTests`.
After C: `AppLockTests|DeviceTrustTests|ReplicaTests|LogRendererTests|SyncTests|ImagePreparerTests|VideoPreparerTests|ContrastAuditTests|NobodyButTheSenderClearsAPhotoTests`.
After D: `VerificationPhraseTests|AccessWindowTests|EmojiCatalogueTests|InviteScanningTests|EntryTests|PastedCodeTests|PostTagsTests|VectorClockTests|CloudKitPacketRecordTests`.

Before each commit, all four from `CLAUDE.md`:

```bash
cd Packages/Carpenter && swift test
./Scripts/lint-branding.sh
xcodebuild -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' build
xcodebuild test -workspace Carpenter.xcworkspace -scheme Carpenter -destination 'platform=iOS Simulator,id=5A43F953-128D-4FE6-9135-0D26520E02B6' -only-testing:CarpenterTests
```

The fourth is what compiles `App/CarpenterTests`, where B3 and C4 land. The live tests in it need two
Apple Accounts and are not proven by compiling; say "compiled, not run on the rig" unless they were.
Use a fresh derived-data folder for the iOS build: the trap in `CLAUDE.md` about a deleted member
binding to something else shows only as a warning an incremental build does not reprint.

## Risks

- **A caller the indexes and `grep` both missed.** It fails the build. The one way it could pass
  silently is a call that rebinds to another member of the same name once ours is gone. Checked by
  hand for the names where that is possible: `revoke`, `post`, `admit`, `entries(in:)`, `isBlocked`,
  `isEmpty`. None found. The iOS build is the real check, because code under `#if os(iOS)` was
  covered by `grep` and a four-day-old index only.
- **`SessionPeeks.swift` knows the session's insides** (`persisted`, `chains`, `replica`,
  `projection`, `storage`). Renaming one of those breaks the file at compile time, which is the
  point of having one file.
- **B3 and C4 change live-suite lines that this step cannot run.** Three of them now read
  `persisted` and `chains` directly.
- **`PayloadType.allKnown` becomes a list in the test target.** A new payload type has to be added
  to it by hand, as before.
- **D5 deletes a domain string from the crypto file.** It is unused, but read
  `docs/crypto-brief.md` for `payload.v1` once more before committing; it was not there on
  2026-11-10.
- **D6 changes what a test asserts on.** If `JoinerCode.decoded` accepts one of the three strings,
  that is a finding about the app, not a reason to put `IdentityPublicKeys.decoded` back.
- **Coverage drops.** Seven tests are deleted (B4: one; D4: one; D5: one; D7: one; D8: three). Each
  tested a thing the app does not run.
- **Another process is editing test files in this tree.** Rebase the line numbers on what is there.

## When finished

- `docs/pre-testflight.md:129-130`: mark item 10 done in that doc's own way, with the real count.
  The chunk is `57f41d12`, `NEEDS HUMAN REVIEW`; leave the marker.
- `docs/epics/rooms-and-membership.md:240` says the two wire cases are "both in `allKnown` and
  `plumbing`". After C1 `allKnown` is the tests' list; reword to "both in `plumbing`" and set that
  chunk to `NEEDS HUMAN REVIEW`.
- E1 and E2 go to `docs/open-questions.md` as the questions below, if Griff has not answered them.

## For Griff

1. **The 19 members in E1 read private state.** Leave them in the app, or make the fields internal
   so they can move, or delete them with their assertions. Recommendation: leave them. Widening
   `RoomRoster` and `Replica` to move a test's question is the worse trade.
2. **Each row of E2 is behaviour with tests and no caller.** Connect it or delete it with its tests,
   row by row. The ones that claim something about the product: pins and tags have a merge with 12
   assertions and no caller was found (whether they reach a member's other devices some other way
   was not checked); `compact()` has 5 and no caller;
   four `MembershipTests` promise things about "an invite" on a form the app never sends; the
   comparison-code ordering test does not run the app's ordering. Recommendation: delete
   `compact()`, `OutpostAccess.merged`, the three `RoomUpdateLevel` properties and
   `ComparisonCode.between`; rewrite the four invite tests and the ordering test against `Invite`
   and `AppSession.comparisonCode(with:)`; and decide on purpose whether pins and tags should travel.
3. **`AppLockTests` drives the lock through `AppLock.unlock(with:at:)`, 20 times, and the lock
   screen does not call it.** `AppLockController.unlock(with:)` runs `charge`, `matches`,
   `afterAWrongCode` and `succeeded` in its own order (`AppLockController.swift:138-195`). C1 moves
   the helper to the tests, which keeps them green and keeps them one step away from what the screen
   does. Say whether to rewrite them against the controller (it sits with plan step 4).
4. **Two test helpers do a thing the app does differently.**
   `close(pairWith:through:)` clears the pair's entry; the app marks it shut
   (`AppSession+Pairs.swift:70-79`). `setSharing(_:)` sets the four switches in a different order
   from `AppRootView.applySharing` (`App/Carpenter/AppRootView+Privacy.swift:70-75`). B1 moves both
   as test helpers. Say if they should instead be deleted and the tests driven through blocking and
   through the four setters.
5. **The step is five times the size the plan says.** Parts A and B are the plan's "about twenty".
   Say whether C and D ride along now or wait.

<!-- COPY END 98cdfe17 -->
