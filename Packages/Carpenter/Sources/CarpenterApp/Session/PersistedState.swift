import CarpenterKit
import Foundation

struct PersistedState: Codable, Sendable {
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
    var repairs: [HistoryRepair] = []
    var repairDuties: [RepairDuty] = []
    var restoreAsks: [RestoreAskRecord] = []
    var holesNoticed: [RoomID: Date] = [:]
    var askedAutomatically: [RoomID: Date] = [:]
    var outpostMediaOwed: [ParticipantID] = []
    var wantsOutpostBell: [ParticipantID] = []
    var outpostSeenThrough: [ParticipantID: Date] = [:]
    var reviewsPostponed: [RoomID: [ParticipantID]] = [:]
    var epochTurnsOwed: [RoomID] = []
    var unverifiable: [FeedGap] = []
    var spentEntries: [SpentEntry] = []
    var uploadsLeftForOthers: [AttachmentID] = []
    var acceptedInvitations: [AcceptedInvitation] = []
    var phraseNonces: [String: Data] = [:]
    var wantsWhatWasSaid = false
    var turnsEveryKeyAfterALoss = false
    var drafts: [RoomID: Data] = [:]
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
        spentEntries = try container.decodeIfPresent([SpentEntry].self, forKey: .spentEntries) ?? []
        uploadsLeftForOthers =
            try container.decodeIfPresent([AttachmentID].self, forKey: .uploadsLeftForOthers) ?? []
        holesNoticed = try container.decodeIfPresent([RoomID: Date].self, forKey: .holesNoticed) ?? [:]
        askedAutomatically =
            try container.decodeIfPresent([RoomID: Date].self, forKey: .askedAutomatically) ?? [:]
        epochTurnsOwed = try container.decodeIfPresent([RoomID].self, forKey: .epochTurnsOwed) ?? []
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
        preferences =
            try container.decodeIfPresent(MemberPreferences.self, forKey: .preferences)
            ?? MemberPreferences()
        wantsWhatWasSaid =
            try container.decodeIfPresent(Bool.self, forKey: .wantsWhatWasSaid) ?? false
        turnsEveryKeyAfterALoss =
            try container.decodeIfPresent(Bool.self, forKey: .turnsEveryKeyAfterALoss) ?? false
        drafts = try container.decodeIfPresent([RoomID: Data].self, forKey: .drafts) ?? [:]
        newPostDraft = try container.decodeIfPresent(Data.self, forKey: .newPostDraft)
        commentDrafts = try container.decodeIfPresent([PostID: Data].self, forKey: .commentDrafts) ?? [:]
    }
}
