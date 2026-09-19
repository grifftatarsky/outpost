import Foundation

public enum RoomAccess: Hashable, Sendable, Codable {
    case open

    case founder

    case members([ParticipantID])

    case anyMember

    case atLeast(Int)

    case unanimous

    public static func member(_ who: ParticipantID) -> RoomAccess { .members([who]) }

    public var admitsOnInvitation: Bool { self == .open }

    public var excludesTheInviter: Bool {
        switch self {
        case .anyMember, .atLeast, .unanimous: return true
        case .open, .founder, .members: return false
        }
    }

    public var namedApprovers: [ParticipantID] {
        if case .members(let who) = self { return who }
        return []
    }

    public func approvers(among members: Set<ParticipantID>, founder: ParticipantID?)
        -> Set<ParticipantID>
    {
        switch self {
        case .open:
            return []
        case .founder:
            return founder.map { [$0] } ?? []
        case .members(let who):
            return members.intersection(who)
        case .anyMember, .atLeast, .unanimous:
            return members
        }
    }

    private enum CodingKeys: String, CodingKey {
        case open, founder, member, members, anyMember, atLeast, unanimous
    }

    private enum SingleKeys: String, CodingKey { case _0 }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.members) {
            let nested = try container.nestedContainer(keyedBy: SingleKeys.self, forKey: .members)
            self = .members(try nested.decode([ParticipantID].self, forKey: ._0))
            return
        }
        if container.contains(.member) {
            let nested = try container.nestedContainer(keyedBy: SingleKeys.self, forKey: .member)
            self = .members([try nested.decode(ParticipantID.self, forKey: ._0)])
            return
        }
        if container.contains(.atLeast) {
            let nested = try container.nestedContainer(keyedBy: SingleKeys.self, forKey: .atLeast)
            self = .atLeast(try nested.decode(Int.self, forKey: ._0))
            return
        }
        if container.contains(.founder) {
            self = .founder
            return
        }
        if container.contains(.anyMember) {
            self = .anyMember
            return
        }
        if container.contains(.unanimous) {
            self = .unanimous
            return
        }
        if container.contains(.open) {
            self = .open
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "no room access in this entry"))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .open:
            _ = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .open)
        case .founder:
            _ = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .founder)
        case .members(let who):
            var nested = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .members)
            try nested.encode(who, forKey: ._0)
        case .anyMember:
            _ = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .anyMember)
        case .atLeast(let count):
            var nested = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .atLeast)
            try nested.encode(count, forKey: ._0)
        case .unanimous:
            _ = container.nestedContainer(keyedBy: SingleKeys.self, forKey: .unanimous)
        }
    }
}
