import CarpenterKit
import Foundation

struct WrittenPacketRecord: Codable, Equatable, Sendable {
    var recipients: Set<RecipientTag>
    var digest: Data?
}

struct SentAttachmentRecord: Codable, Equatable, Sendable {
    var people: Set<ParticipantID>
    var collectedBy: Set<DeviceID> = []
    var sentAt: Date
}

struct PersistedState: Codable, Equatable, Sendable {
    var organisation = RoomsListOrganisation()
    var knownRooms: [RoomID] = []
    var greetedRooms: [RoomID] = []
    var readThrough: [RoomID: EntryHash] = [:]
    var answeredDepartures: Set<EntryHash> = []
    var epochs: [RoomID: [UInt64]] = [:]
    var syncedFrontier = VectorClock()
    var publishedEntryCount = 0
    var knownSiblings: [DeviceID] = []
    var outstandingPackets: [PacketID: Set<EntryHash>] = [:]
    var packetsWritten: [PacketID: WrittenPacketRecord] = [:]
    var repairs: [HistoryRepair] = []
    var repairDuties: [RepairDuty] = []
    var restoreAsks: [RestoreAskRecord] = []
    var holesNoticed: [RoomID: Date] = [:]
    var askedAutomatically: [RoomID: Date] = [:]
    var outpostMediaOwed: [ParticipantID] = []
    var wantsOutpostBell: [ParticipantID] = []
    var outpostSeenThrough: [ParticipantID: Date] = [:]
    var reviewsPostponed: [RoomID: [ParticipantID]] = [:]
    var keyRotationsOwed: [RoomID] = []
    var unverifiable: [FeedGap] = []
    var spentEntries: [SpentEntry] = []
    var uploadsLeftForOthers: [AttachmentID] = []
    var attachmentsSent: [AttachmentID: SentAttachmentRecord] = [:]
    var acceptedInvitations: [AcceptedInvitation] = []
    var phraseNonces: [String: Data] = [:]
    var wantsWhatWasSaid = false
    var siblingMail = SiblingMail()

    private enum RetiredKeys: String, CodingKey { case awaitingJoin, epochTurnsOwed }
    var knownKeys: [IdentityPublicKeys] = []
    var certificates: [DeviceCertificate] = []
    var revocations: [DeviceRevocation] = []
    var otherRevocations: [DeviceRevocation] = []
    var authorityStored: [Data: Date] = [:]
    var authorityIsLegacy = false
    var authorityPublished: Set<Data> = []
    var authorityAnnounced: Data?
    var restoredWithTheRecoveryKey = false
    var rekeyBeforeWriting: Set<RoomID> = []
    var resend: Set<EntryHash> = []

    var preferences = MemberPreferences()

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let retired = try decoder.container(keyedBy: RetiredKeys.self)
        organisation =
            try container.decodeIfPresent(RoomsListOrganisation.self, forKey: .organisation)
            ?? RoomsListOrganisation()
        knownRooms = try container.decodeIfPresent([RoomID].self, forKey: .knownRooms) ?? []
        greetedRooms = try container.decodeIfPresent([RoomID].self, forKey: .greetedRooms) ?? []
        readThrough =
            try container.decodeIfPresent([RoomID: EntryHash].self, forKey: .readThrough) ?? [:]
        answeredDepartures =
            try container.decodeIfPresent(Set<EntryHash>.self, forKey: .answeredDepartures) ?? []
        epochs = try container.decodeIfPresent([RoomID: [UInt64]].self, forKey: .epochs) ?? [:]
        syncedFrontier =
            try container.decodeIfPresent(VectorClock.self, forKey: .syncedFrontier) ?? VectorClock()
        knownKeys =
            try container.decodeIfPresent([IdentityPublicKeys].self, forKey: .knownKeys) ?? []
        if let accepted = try container.decodeIfPresent(
            [AcceptedInvitation].self, forKey: .acceptedInvitations)
        {
            acceptedInvitations = accepted
        } else {
            acceptedInvitations =
                (try retired.decodeIfPresent([MembershipAttestation].self, forKey: .awaitingJoin)
                    ?? [])
                .map { AcceptedInvitation(attestation: $0, confirmedAt: .distantPast) }
        }
        phraseNonces =
            try container.decodeIfPresent([String: Data].self, forKey: .phraseNonces) ?? [:]
        certificates =
            try container.decodeIfPresent([DeviceCertificate].self, forKey: .certificates) ?? []
        revocations =
            try container.decodeIfPresent([DeviceRevocation].self, forKey: .revocations) ?? []
        publishedEntryCount = try container.decodeIfPresent(Int.self, forKey: .publishedEntryCount) ?? 0
        knownSiblings = try container.decodeIfPresent([DeviceID].self, forKey: .knownSiblings) ?? []
        repairs = try container.decodeIfPresent([HistoryRepair].self, forKey: .repairs) ?? []
        repairDuties = try container.decodeIfPresent([RepairDuty].self, forKey: .repairDuties) ?? []
        restoreAsks =
            try container.decodeIfPresent([RestoreAskRecord].self, forKey: .restoreAsks) ?? []
        unverifiable = try container.decodeIfPresent([FeedGap].self, forKey: .unverifiable) ?? []
        spentEntries = try container.decodeIfPresent([SpentEntry].self, forKey: .spentEntries) ?? []
        uploadsLeftForOthers =
            try container.decodeIfPresent([AttachmentID].self, forKey: .uploadsLeftForOthers) ?? []
        attachmentsSent =
            try container.decodeIfPresent([AttachmentID: SentAttachmentRecord].self, forKey: .attachmentsSent) ?? [:]
        holesNoticed = try container.decodeIfPresent([RoomID: Date].self, forKey: .holesNoticed) ?? [:]
        askedAutomatically =
            try container.decodeIfPresent([RoomID: Date].self, forKey: .askedAutomatically) ?? [:]
        keyRotationsOwed =
            try container.decodeIfPresent([RoomID].self, forKey: .keyRotationsOwed)
            ?? retired.decodeIfPresent([RoomID].self, forKey: .epochTurnsOwed) ?? []
        reviewsPostponed =
            try container.decodeIfPresent([RoomID: [ParticipantID]].self, forKey: .reviewsPostponed)
            ?? [:]
        outpostSeenThrough =
            try container.decodeIfPresent([ParticipantID: Date].self, forKey: .outpostSeenThrough)
            ?? [:]
        wantsOutpostBell =
            try container.decodeIfPresent([ParticipantID].self, forKey: .wantsOutpostBell) ?? []
        outpostMediaOwed =
            try container.decodeIfPresent([ParticipantID].self, forKey: .outpostMediaOwed) ?? []
        outstandingPackets =
            try container.decodeIfPresent([PacketID: Set<EntryHash>].self, forKey: .outstandingPackets)
            ?? [:]
        packetsWritten =
            try container.decodeIfPresent([PacketID: WrittenPacketRecord].self, forKey: .packetsWritten) ?? [:]
        preferences =
            try container.decodeIfPresent(MemberPreferences.self, forKey: .preferences)
            ?? MemberPreferences()
        wantsWhatWasSaid =
            try container.decodeIfPresent(Bool.self, forKey: .wantsWhatWasSaid) ?? false
        siblingMail = try container.decodeIfPresent(SiblingMail.self, forKey: .siblingMail) ?? SiblingMail()
        otherRevocations =
            try container.decodeIfPresent([DeviceRevocation].self, forKey: .otherRevocations) ?? []
        if let stored = try container.decodeIfPresent([Data: Date].self, forKey: .authorityStored) {
            authorityStored = stored
            authorityIsLegacy = try container.decodeIfPresent(Bool.self, forKey: .authorityIsLegacy) ?? false
        } else {
            authorityIsLegacy = true
        }
        authorityPublished = try container.decodeIfPresent(Set<Data>.self, forKey: .authorityPublished) ?? []
        authorityAnnounced = try container.decodeIfPresent(Data.self, forKey: .authorityAnnounced)
        restoredWithTheRecoveryKey =
            try container.decodeIfPresent(Bool.self, forKey: .restoredWithTheRecoveryKey) ?? false
        rekeyBeforeWriting = try container.decodeIfPresent(Set<RoomID>.self, forKey: .rekeyBeforeWriting) ?? []
        resend = try container.decodeIfPresent(Set<EntryHash>.self, forKey: .resend) ?? []
    }
}
