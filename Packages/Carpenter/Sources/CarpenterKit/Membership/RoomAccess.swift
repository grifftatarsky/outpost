import Foundation

public enum RoomAccess: Hashable, Sendable, Codable {
    case open

    case founder

    case member(ParticipantID)

    case anyMember

    case atLeast(Int)

    case unanimous

    public var admitsOnInvitation: Bool { self == .open }

    public func approvers(among members: Set<ParticipantID>, founder: ParticipantID?)
        -> Set<ParticipantID>
    {
        switch self {
        case .open:
            return []
        case .founder:
            return founder.map { [$0] } ?? []
        case .member(let who):
            return members.contains(who) ? [who] : []
        case .anyMember, .atLeast, .unanimous:
            return members
        }
    }
}
