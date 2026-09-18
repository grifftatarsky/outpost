import Foundation

public enum NotificationLevel: String, CaseIterable, Sendable, Codable {
    case everything

    case whoAndWhere

    case whereOnly

    case nothing

    public static let `default` = NotificationLevel.everything

    public var showsRoom: Bool { self == .everything || self == .whoAndWhere || self == .whereOnly }

    public var showsSender: Bool { self == .everything || self == .whoAndWhere }

    public var showsMessage: Bool { self == .everything }

    public var groupsByRoom: Bool { self != .nothing }
}
