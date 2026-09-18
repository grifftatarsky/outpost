import Foundation

public struct MessagingNotificationChoices: Hashable, Sendable, Codable {
    public var wantsMessages: Bool
    public var level: NotificationLevel

    public var wantsRoomUpdates: Bool
    public var roomUpdateLevel: RoomUpdateLevel

    public static let `default` = MessagingNotificationChoices(
        wantsMessages: true, level: .everything, wantsRoomUpdates: true, roomUpdateLevel: .whoAndWhere)

    public init(
        wantsMessages: Bool, level: NotificationLevel, wantsRoomUpdates: Bool,
        roomUpdateLevel: RoomUpdateLevel
    ) {
        self.wantsMessages = wantsMessages
        self.level = level
        self.wantsRoomUpdates = wantsRoomUpdates
        self.roomUpdateLevel = roomUpdateLevel
    }
}

public enum RoomUpdateLevel: String, CaseIterable, Sendable, Codable {
    case whoAndWhere
    case whereOnly
    case whatOnly
    case nothing

    public var namesThePerson: Bool { self == .whoAndWhere }
    public var namesTheRoom: Bool { self == .whoAndWhere || self == .whereOnly }
    public var namesWhatHappened: Bool { self != .nothing }
}

public enum RoomUpdate: String, CaseIterable, Sendable {
    case somebodyJoined, somebodyLeft, somebodyRemoved, roomRenamed, invitationAnswered
    case accessChanged
}
