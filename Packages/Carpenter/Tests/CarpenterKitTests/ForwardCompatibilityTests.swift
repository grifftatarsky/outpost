import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterApp
@testable import CarpenterKit

@Suite struct ForwardCompatibilityTests {
    @Test func preferencesDecodeFromBeforeNotificationLevelsExisted() throws {
        let old = Data(#"{"hidden":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(MemberPreferences.self, from: old)
        #expect(decoded.notificationLevel == nil)
        #expect(decoded.roomNotificationLevel.isEmpty)
        #expect(decoded.mutedRooms.isEmpty)
    }

    @Test func preferencesDecodeFromBeforeAnyFieldExisted() throws {
        let decoded = try JSONDecoder().decode(MemberPreferences.self, from: Data("{}".utf8))
        #expect(decoded.hidden.isEmpty)
        #expect(decoded.reportsDisplaying == nil)
    }

    @Test func persistedStateSurvivesAPreferencesBlobFromAnOlderBuild() throws {
        let old = Data(#"{"preferences":{"hidden":[]}}"#.utf8)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(decoded.preferences.mutedRooms.isEmpty)
    }
}

extension ForwardCompatibilityTests {
    private func eachKeyIsOptionalToDecode<T: Codable>(_ value: T) throws {
        let full = try JSONEncoder().encode(value)
        let object = try #require(
            try JSONSerialization.jsonObject(with: full) as? [String: Any])
        for key in object.keys {
            var reduced = object
            reduced.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: reduced)
            #expect(throws: Never.self, "decoding without '\(key)' — a build predating that field") {
                try JSONDecoder().decode(T.self, from: data)
            }
        }
    }

    @Test func memberPreferencesToleratesAnyOneFieldBeingAbsent() throws {
        try eachKeyIsOptionalToDecode(MemberPreferences())
    }

    @Test func persistedStateToleratesAnyOneFieldBeingAbsent() throws {
        try eachKeyIsOptionalToDecode(PersistedState())
    }
}

extension ForwardCompatibilityTests {
    private static func populated() throws -> PersistedState {
        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 1_786_635_000),
            device: DeviceID(rawValue: WideID.of([7])))
        let room = RoomID(rawValue: UUID(uuidString: "8B0B4B36-51F1-4C4F-9C0E-4A2E9C7D1A55")!)
        let entry = EntryHash(rawValue: Data([1, 2, 3]))

        var state = PersistedState()
        state.organisation.rooms[room] = RoomOrganisation(pin: Stamped(1.0, stamp: stamp))
        state.knownRooms = [room]
        state.greetedRooms = [room]
        state.readThrough = [room: entry]
        state.answeredDepartures = [entry]
        state.epochs = [room: [0, 1]]
        state.syncedFrontier[
            FeedKey(author: ParticipantID(rawValue: WideID.of([9])), device: DeviceID(rawValue: WideID.of([7])))
        ] = 4
        state.publishedEntryCount = 3
        state.knownSiblings = [DeviceID(rawValue: WideID.of([7]))]
        state.outstandingPackets = [PacketID(): [entry]]
        state.packetsWritten = [
            PacketID(): WrittenPacketRecord(recipients: [RecipientTag(rawValue: Data([4]))], digest: Data([5]))
        ]
        let feed = FeedKey(author: ParticipantID(rawValue: WideID.of([9])), device: DeviceID(rawValue: WideID.of([7])))
        var heads = VectorClock()
        heads[feed] = 4
        let request = RepairRequest(
            id: RepairID(rawValue: UUID(uuidString: "2C1D6F0A-7B3E-4E9B-9F7C-1A2B3C4D5E6F")!),
            authors: [ParticipantID(rawValue: WideID.of([9]))], heads: heads,
            gaps: [FeedGap(feed: feed, spans: [SequenceSpan(2, 2)])])
        var repair = HistoryRepair(
            id: request.id, room: room, startedAt: stamp.at, request: request,
            asked: [ParticipantID(rawValue: WideID.of([9]))])
        repair.sent = [ParticipantID(rawValue: WideID.of([9]))]
        repair.answers = [
            ParticipantID(rawValue: WideID.of([9])): RepairAnswer(
                request: request.id, unheld: [FeedGap(feed: feed, spans: [SequenceSpan(2, 2)])],
                heads: heads)
        ]
        state.repairs = [repair]
        state.repairDuties = [RepairDuty(request: request, from: ParticipantID(rawValue: WideID.of([9])))]
        state.unverifiable = [FeedGap(feed: feed, spans: [SequenceSpan(7, 7)])]
        state.spentEntries = [SpentEntry(feed: feed, seq: 3, hash: entry, room: room)]
        state.uploadsLeftForOthers = [AttachmentID()]
        state.attachmentsSent = [
            AttachmentID(): SentAttachmentRecord(
                people: [ParticipantID(rawValue: WideID.of([9]))], collectedBy: [DeviceID(rawValue: WideID.of([7]))],
                sentAt: stamp.at)
        ]
        state.photosAsked = [
            AttachmentID(): AskedPhoto(
                author: ParticipantID(rawValue: WideID.of([9])), entry: entry, askedAt: stamp.at, sent: true)
        ]
        state.addressAnnounced = [
            ParticipantID(rawValue: WideID.of([9])): AnnouncedAddress(
                salt: Data(repeating: 3, count: 32), packet: PacketID(), confirmed: true)
        ]
        state.photoAsks = [
            PhotoAskRecord(
                from: ParticipantID(rawValue: WideID.of([9])), entry: entry, attachment: AttachmentID(), at: stamp.at)
        ]
        let link = PairLink(account: "_them", url: URL(string: "https://icloud.invalid/share/a")!)
        var paired = PairBookEntry(theirs: link)
        paired.joinedSpace = link.url
        paired.announced = link.url
        paired.gone = [URL(string: "https://icloud.invalid/share/gone")!]
        paired.shut = true
        state.pairBook = [ParticipantID(rawValue: WideID.of([9])): paired]
        state.codeLink = try SignedPairLink.sign(link, by: Identity.generate())
        state.codeClaims = [CodeClaim(url: link.url, peer: ParticipantID(rawValue: WideID.of([9])))]
        state.holesNoticed = [room: stamp.at]
        state.askedAutomatically = [room: stamp.at]
        state.keyRotationsOwed = [room]
        state.outpostMediaOwed = [ParticipantID(rawValue: WideID.of([9]))]
        state.reviewsPostponed = [room: [ParticipantID(rawValue: WideID.of([9]))]]
        state.outpostSeenThrough = [ParticipantID(rawValue: WideID.of([9])): stamp.at]
        state.wantsOutpostBell = [ParticipantID(rawValue: WideID.of([9]))]
        let inviter = Identity.generate()
        state.acceptedInvitations = [
            AcceptedInvitation(
                attestation: try TestInvite.issue(
                    joining: room, joinerKeys: Identity.generate().publicKeys, by: inviter,
                    at: stamp.at),
                confirmedAt: stamp.at)
        ]
        state.phraseNonces = ["Y29tbWl0bWVudA==": Data(repeating: 9, count: 32)]
        state.wantsWhatWasSaid = true
        var mail = SiblingMail()
        let sibling = DeviceID(rawValue: Data(repeating: 0x5B, count: 32))
        mail.noteState(from: sibling, cursors: [], at: Date(timeIntervalSince1970: 1_786_635_000), me: DeviceID(rawValue: Data(repeating: 0x5A, count: 32)))
        mail.took(mail: 2, from: sibling)
        state.siblingMail = mail
        let other = Identity.generate()
        state.otherRevocations = [
            try DeviceRevocation.issue(
                for: DeviceKeys.generate().id, by: other, at: stamp.at, from: DeviceKeys.generate())
        ]
        state.authorityStored = [Data(repeating: 0x5D, count: 32): stamp.at]
        state.authorityIsLegacy = true
        state.authorityPublished = [Data(repeating: 0x5E, count: 32)]
        state.authorityAnnounced = Data(repeating: 0x5F, count: 32)
        state.restoredWithTheRecoveryKey = true
        state.rekeyBeforeWriting = [RoomID()]
        state.resend = [EntryHash(rawValue: Data(repeating: 0x61, count: 32))]
        state.restoreAsks = [
            RestoreAskRecord(request: RepairID(), from: ParticipantID(rawValue: WideID.of([7])),
                room: room, at: stamp.at, hold: .held)
        ]
        state.preferences.setHidden(true, for: entry, stamp: stamp)
        state.preferences.setMuted(true, for: room, stamp: stamp)
        state.preferences.setReportsDisplaying(false, stamp: stamp)
        state.preferences.setBlocked(true, ParticipantID(rawValue: WideID.of([9])), stamp: stamp)
        state.preferences.setNotified(
            true, about: ParticipantID(rawValue: WideID.of([9])), stamp: stamp)
        state.preferences.setDisplayName("Cassilda", stamp: stamp)
        state.preferences.setSharesName(true, stamp: stamp)
        state.preferences.setSharesAvatar(true, stamp: stamp)
        state.preferences.setShowsOthersNames(true, stamp: stamp)
        state.preferences.setShowsOthersAvatars(true, stamp: stamp)
        state.preferences.setPrivacyCheckedUp(true, stamp: stamp)
        state.preferences.setNickname("Cass", for: ParticipantID(rawValue: WideID.of([9])), stamp: stamp)
        state.preferences.setSharesFocus(true, stamp: stamp)
        state.preferences.setShowsOthersFocus(true, stamp: stamp)
        state.preferences.setUsesCustomFocusMessage(true, stamp: stamp)
        state.preferences.setFocusMessage("Heads down", stamp: stamp)
        return state
    }

    private static let unpopulated: Set<String> = ["knownKeys", "certificates", "revocations"]

    @Test func everyPersistedFieldThisTestCanFillIsActuallyFilled() throws {
        let full = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(try Self.populated()))
                as? [String: Any])
        let empty = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(PersistedState()))
                as? [String: Any])

        for key in empty.keys where !Self.unpopulated.contains(key) {
            #expect(
                !NSDictionary(dictionary: [key: full[key] ?? NSNull()])
                    .isEqual(to: [key: empty[key] ?? NSNull()]),
                """
                '\(key)' is still at its default in `populated()`, so the round trip below cannot \
                tell whether the decoder reads it. Give it a value, or name it in `unpopulated` \
                with a reason.
                """)
        }
    }

    @Test func aStateFileFromTheBuildBeforeTheRenameStillOpens() throws {
        let inviter = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: RoomID(), joinerKeys: Identity.generate().publicKeys, by: inviter,
            at: Date(timeIntervalSince1970: 1_786_635_000))

        var old = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(PersistedState()))
                as? [String: Any])
        old.removeValue(forKey: "acceptedInvitations")
        old["awaitingJoin"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([attestation]))

        let decoded = try JSONDecoder().decode(
            PersistedState.self,
            from: try JSONSerialization.data(withJSONObject: old))

        #expect(
            decoded.acceptedInvitations.map(\.attestation) == [attestation],
            "an invitation confirmed on the build before the rename was dropped on upgrade")
    }

    @Test("A contact's link written by the build before links were weighed still opens, and is joined again")
    func aPairBookEntryFromTheBuildBeforeStillOpens() throws {
        let json = Data(#"{"theirs":{"account":"_them","url":"https://icloud.invalid/share/a"},"joined":true,"announced":"https://icloud.invalid/share/b"}"#.utf8)
        let entry = try JSONDecoder().decode(PairBookEntry.self, from: json)
        #expect(entry.theirs?.account == "_them")
        #expect(entry.announced?.absoluteString == "https://icloud.invalid/share/b")
        #expect(entry.joinedSpace == nil)
        #expect(entry.gone.isEmpty)
    }

    @Test("A key rotation owed under the old field name is still owed after the upgrade")
    func owedKeyRotationsSurviveTheRename() throws {
        let room = RoomID()
        var old = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(PersistedState()))
                as? [String: Any])
        old.removeValue(forKey: "keyRotationsOwed")
        old["epochTurnsOwed"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([room]))

        let decoded = try JSONDecoder().decode(
            PersistedState.self,
            from: try JSONSerialization.data(withJSONObject: old))

        #expect(
            decoded.keyRotationsOwed == [room],
            "a removal whose key rotation had not happened yet was forgotten on upgrade, so the removed member keeps reading")
    }

    @Test func decodingPersistedStateKeepsEveryFieldItWasGiven() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let written = try encoder.encode(try Self.populated())
        let readBack = try encoder.encode(
            try JSONDecoder().decode(PersistedState.self, from: written))

        #expect(readBack == written, "a field the encoder writes is not read back by init(from:)")
    }
}
