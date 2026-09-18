import Foundation

public struct HistoryRepairStatus: Hashable, Sendable, Identifiable {
    public let id: RepairID
    public let room: RoomID
    public let startedAt: Date
    public let asked: [Member]
    public let answered: [Member]
    public let waiting: [Member]
    public let recovered: Int
    public let stillMissing: Int
    public let heldByNobodyAsked: Int
    public let sentButNotArrived: Int

    public let unverifiable: Int

    public init(
        id: RepairID, room: RoomID, startedAt: Date, asked: [Member], answered: [Member],
        waiting: [Member], recovered: Int, stillMissing: Int, heldByNobodyAsked: Int,
        sentButNotArrived: Int, unverifiable: Int = 0
    ) {
        self.id = id
        self.room = room
        self.startedAt = startedAt
        self.asked = asked
        self.answered = answered
        self.waiting = waiting
        self.recovered = recovered
        self.stillMissing = stillMissing
        self.heldByNobodyAsked = heldByNobodyAsked
        self.sentButNotArrived = sentButNotArrived
        self.unverifiable = unverifiable
    }

    public var isComplete: Bool { waiting.isEmpty }
}
