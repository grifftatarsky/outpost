import Foundation

public enum PushChannel: String, CaseIterable, Sendable {
    case deviceFeed

    case inbox

    case bell

    public var subscriptionID: String {
        switch self {
        case .deviceFeed: "outpost.sibling-feed.v1"
        case .inbox: "outpost.inbox.v2"
        case .bell: "outpost.bell.v1"
        }
    }

    public var recordType: String {
        switch self {
        case .deviceFeed: "SiblingFeed"
        case .inbox: "SyncPacket"
        case .bell: "MessageBell"
        }
    }

    public var isVisible: Bool { self == .bell }

    public static func of(subscriptionID: String?) -> PushChannel? {
        guard let subscriptionID else { return nil }
        return allCases.first { $0.subscriptionID == subscriptionID }
    }
}
