import Foundation

public enum OutpostConsent: String, Hashable, Sendable, Codable, CaseIterable {
    case open = "accepted"

    case closed

    case quiet

    case off

    public var participates: Bool { self == .open || self == .closed }

    public var showsOutposts: Bool { self != .off }

    public var reachesThePostsReaders: Bool { self == .open }
}
