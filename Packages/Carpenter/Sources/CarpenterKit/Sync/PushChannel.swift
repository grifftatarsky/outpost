import Foundation

public enum PushChannel: String, CaseIterable, Sendable {
    case deviceFeed

    case inbox

    case ring

    public var subscriptionID: String {
        switch self {
        case .deviceFeed: "outpost.sibling-feed.v1"
        case .inbox: "outpost.inbox.v3"
        case .ring: "outpost.ring.v1"
        }
    }

    public var recordType: String {
        switch self {
        case .deviceFeed: "SiblingFeed"
        case .inbox: "SyncPacket"
        case .ring: PairWire.ringType
        }
    }

    public var isVisible: Bool { self == .ring }

    public static func of(subscriptionID: String?) -> PushChannel? {
        guard let subscriptionID else { return nil }
        return allCases.first { $0.subscriptionID == subscriptionID }
    }
}
