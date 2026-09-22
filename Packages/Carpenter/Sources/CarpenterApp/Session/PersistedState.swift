import CarpenterKit
import Foundation

struct PersistedState: Codable, Sendable {
    var organisation = RoomsListOrganisation()
    var knownRooms: [ConversationID] = []
    var greetedRooms: [ConversationID] = []
    var readThrough: [ConversationID: EntryHash] = [:]
    var answeredDepartures: Set<EntryHash> = []
    var epochs: [ConversationID: [UInt64]] = [:]
    var syncedFrontier = VectorClock()
    var publishedEntryCount = 0
    var knownSiblings: [DeviceID] = []
    var outstandingPackets: [PacketID: Set<EntryHash>] = [:]
    var repairs: [HistoryRepair] = []
    var repairDuties: [RepairDuty] = []
    var restoreAsks: [RestoreAskRecord] = []
    var holesNoticed: [ConversationID: Date] = [:]
    var askedAutomatically: [ConversationID: Date] = [:]
    var outpostMediaOwed: [ParticipantID] = []
    var wantsOutpostBell: [ParticipantID] = []
    var outpostSeenThrough: [ParticipantID: Date] = [:]
    var reviewsPostponed: [ConversationID: [ParticipantID]] = [:]
    var epochTurnsOwed: [ConversationID] = []
    var unverifiable: [FeedGap] = []
    var elsewhere: [FeedGap] = []
    var ownHeads: [ConversationID: EntryLink] = [:]
    var attestedHeads: [FeedKey: [ParticipantID: EntryLink]] = [:]
    var contradictions: [RecordedContradiction] = []
    var contradictionAsks: [Contradiction] = []
    var awaitingOwnRecords = false
    var publishedPositions: [ConversationID: UInt64] = [:]
    var withheldTold: [ParticipantID: [FeedGap]] = [:]
    var spentEntries: [SpentEntry] = []
    var uploadsLeftForOthers: [AttachmentID] = []
    var acceptedInvitations: [AcceptedInvitation] = []
    var phraseNonces: [String: Data] = [:]
    var wantsWhatWasSaid = false
    var turnsEveryKeyAfterALoss = false
    var drafts: [ConversationID: Data] = [:]
    var newPostDraft: Data?
    var commentDrafts: [PostID: Data] = [:]

    private enum RetiredKeys: String, CodingKey { case awaitingJoin }
    var knownKeys: [IdentityPublicKeys] = []
    var certificates: [DeviceCertificate] = []
    var revocations: [DeviceRevocation] = []

    var preferences = MemberPreferences()

    func sealedDraft(at place: DraftPlace) -> Data? {
        switch place {
        case .room(let room): drafts[room]
        case .newPost: newPostDraft
        case .comment(let post): commentDrafts[post]
        }
    }

    mutating func setSealedDraft(_ sealed: Data?, at place: DraftPlace) {
        switch place {
        case .room(let room): drafts[room] = sealed
        case .newPost: newPostDraft = sealed
        case .comment(let post): commentDrafts[post] = sealed
        }
    }

    var sealedDrafts: [(DraftPlace, Data)] {
        drafts.map { (.room($0.key), $0.value) }
            + (newPostDraft.map { [(.newPost, $0)] } ?? [])
            + commentDrafts.map { (.comment($0.key), $0.value) }
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        organisation =
            try container.decodeIfPresent(RoomsListOrganisation.self, forKey: .organisation)
            ?? RoomsListOrganisation()
        knownRooms = try container.decodeIfPresent([ConversationID].self, forKey: .knownRooms) ?? []
        greetedRooms = try container.decodeIfPresent([ConversationID].self, forKey: .greetedRooms) ?? []
        readThrough =
            try container.decodeIfPresent([ConversationID: EntryHash].self, forKey: .readThrough) ?? [:]
        answeredDepartures =
            try container.decodeIfPresent(Set<EntryHash>.self, forKey: .answeredDepartures) ?? []
        epochs = try container.decodeIfPresent([ConversationID: [UInt64]].self, forKey: .epochs) ?? [:]
        syncedFrontier =
            try container.decodeIfPresent(VectorClock.self, forKey: .syncedFrontier) ?? VectorClock()
        knownKeys =
            try container.decodeIfPresent([IdentityPublicKeys].self, forKey: .knownKeys) ?? []
        if let accepted = try container.decodeIfPresent(
            [AcceptedInvitation].self, forKey: .acceptedInvitations)
        {
            acceptedInvitations = accepted
        } else {
            let retired = try decoder.container(keyedBy: RetiredKeys.self)
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
        elsewhere = try container.decodeIfPresent([FeedGap].self, forKey: .elsewhere) ?? []
        ownHeads =
            try container.decodeIfPresent([ConversationID: EntryLink].self, forKey: .ownHeads) ?? [:]
        attestedHeads =
            try container.decodeIfPresent(
                [FeedKey: [ParticipantID: EntryLink]].self, forKey: .attestedHeads) ?? [:]
        contradictions =
            try container.decodeIfPresent([RecordedContradiction].self, forKey: .contradictions) ?? []
        contradictionAsks =
            try container.decodeIfPresent([Contradiction].self, forKey: .contradictionAsks) ?? []
        withheldTold =
            try container.decodeIfPresent([ParticipantID: [FeedGap]].self, forKey: .withheldTold) ?? [:]
        spentEntries = try container.decodeIfPresent([SpentEntry].self, forKey: .spentEntries) ?? []
        uploadsLeftForOthers =
            try container.decodeIfPresent([AttachmentID].self, forKey: .uploadsLeftForOthers) ?? []
        holesNoticed = try container.decodeIfPresent([ConversationID: Date].self, forKey: .holesNoticed) ?? [:]
        askedAutomatically =
            try container.decodeIfPresent([ConversationID: Date].self, forKey: .askedAutomatically) ?? [:]
        epochTurnsOwed = try container.decodeIfPresent([ConversationID].self, forKey: .epochTurnsOwed) ?? []
        reviewsPostponed =
            try container.decodeIfPresent([ConversationID: [ParticipantID]].self, forKey: .reviewsPostponed)
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
        preferences =
            try container.decodeIfPresent(MemberPreferences.self, forKey: .preferences)
            ?? MemberPreferences()
        wantsWhatWasSaid =
            try container.decodeIfPresent(Bool.self, forKey: .wantsWhatWasSaid) ?? false
        turnsEveryKeyAfterALoss =
            try container.decodeIfPresent(Bool.self, forKey: .turnsEveryKeyAfterALoss) ?? false
        drafts = try container.decodeIfPresent([ConversationID: Data].self, forKey: .drafts) ?? [:]
        newPostDraft = try container.decodeIfPresent(Data.self, forKey: .newPostDraft)
        commentDrafts = try container.decodeIfPresent([PostID: Data].self, forKey: .commentDrafts) ?? [:]
        awaitingOwnRecords =
            try container.decodeIfPresent(Bool.self, forKey: .awaitingOwnRecords) ?? false
        publishedPositions =
            try container.decodeIfPresent([ConversationID: UInt64].self, forKey: .publishedPositions) ?? [:]
    }
}
