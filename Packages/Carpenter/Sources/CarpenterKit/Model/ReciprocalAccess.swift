import Foundation

public struct ReciprocalAccess: Hashable, Sendable {
    public let person: Member
    public let sharedRooms: [String]
    public let theyGave: OutpostAccess.Grant?
    public let youGave: OutpostAccess.Grant?

    public init(
        person: Member, sharedRooms: [String] = [], theyGave: OutpostAccess.Grant? = nil,
        youGave: OutpostAccess.Grant? = nil
    ) {
        self.person = person
        self.sharedRooms = sharedRooms
        self.theyGave = theyGave
        self.youGave = youGave
    }

    public var youCanRead: [AccessWindow] { theyGave?.windows ?? [] }
    public var theyCanRead: [AccessWindow] { youGave?.windows ?? [] }

    public var isOneSided: Bool { youCanRead != theyCanRead }

    public var yourStanding: OutpostAccess.Standing { OutpostAccess.Standing(youGave) }
}
