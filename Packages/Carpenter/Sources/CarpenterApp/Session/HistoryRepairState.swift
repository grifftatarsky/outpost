import CarpenterKit
import Foundation

struct HistoryRepair: Hashable, Sendable, Codable {
    var id: RepairID
    var room: RoomID
    var startedAt: Date
    var request: RepairRequest
    var asked: [ParticipantID]
    var sent: Set<ParticipantID> = []
    var answers: [ParticipantID: RepairAnswer] = [:]
    var quiet = false

    init(
        id: RepairID, room: RoomID, startedAt: Date, request: RepairRequest,
        asked: [ParticipantID], quiet: Bool = false
    ) {
        self.id = id
        self.room = room
        self.startedAt = startedAt
        self.request = request
        self.asked = asked
        self.quiet = quiet
    }

    var isAnswered: Bool { asked.allSatisfy { answers[$0] != nil } }

    var isSent: Bool { asked.allSatisfy { sent.contains($0) } }

    func isStale(at now: Date, patience: TimeInterval) -> Bool {
        isSent && now.timeIntervalSince(startedAt) >= patience
    }

    private enum CodingKeys: String, CodingKey {
        case id, room, startedAt, request, asked, sent, answers, quiet
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RepairID.self, forKey: .id)
        room = try container.decode(RoomID.self, forKey: .room)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
        request = try container.decode(RepairRequest.self, forKey: .request)
        asked = try container.decodeIfPresent([ParticipantID].self, forKey: .asked) ?? []
        sent = try container.decodeIfPresent(Set<ParticipantID>.self, forKey: .sent) ?? []
        answers =
            try container.decodeIfPresent([ParticipantID: RepairAnswer].self, forKey: .answers) ?? [:]
        quiet = try container.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
    }
}

struct RepairDuty: Hashable, Sendable, Codable {
    var request: RepairRequest
    var from: ParticipantID

    init(request: RepairRequest, from: ParticipantID) {
        self.request = request
        self.from = from
    }

    private enum CodingKeys: String, CodingKey { case request, from }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(RepairRequest.self, forKey: .request)
        from = try container.decode(ParticipantID.self, forKey: .from)
    }
}

public enum RestoreHold: String, Hashable, Sendable, Codable {
    case held
    case allowed
    case refused
}

struct RestoreAskRecord: Hashable, Sendable, Codable {
    var request: RepairID
    var from: ParticipantID
    var room: RoomID?
    var at: Date
    var hold: RestoreHold

    static let kept = 20

    init(request: RepairID, from: ParticipantID, room: RoomID?, at: Date, hold: RestoreHold) {
        self.request = request
        self.from = from
        self.room = room
        self.at = at
        self.hold = hold
    }

    private enum CodingKeys: String, CodingKey { case request, from, room, at, hold }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(RepairID.self, forKey: .request)
        from = try container.decode(ParticipantID.self, forKey: .from)
        room = try container.decodeIfPresent(RoomID.self, forKey: .room)
        at = try container.decodeIfPresent(Date.self, forKey: .at) ?? .distantPast
        hold = try container.decodeIfPresent(RestoreHold.self, forKey: .hold) ?? .allowed
    }
}
