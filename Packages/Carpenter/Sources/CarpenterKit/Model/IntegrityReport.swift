import Foundation

public struct IntegrityReport: Hashable, Sendable {
    public var forks: [Fork] = []

    public var lastLoad: LogTermination = .complete

    public var discardedBytes: Int = 0

    public var unverifiableOnDisk: Int = 0

    public var rejectedFromPeers: Int = 0

    // MARK: What this device holds that is none of its business

    public var sealedForOthers: Int = 0

    public var unmetAuthorsHeld: Int = 0

    public var unverifiableFromOwnDevices: Int = 0

    public var certificatesRefused: Int = 0

    public var feedsFromOtherMembers: Int = 0

    public var unreadableSiblingFeeds: Int = 0

    public var writesFailed: Int = 0

    public var unexplainedContradictions: Int = 0

    public init() {}

    public var isClean: Bool {
        forks.isEmpty && lastLoad == .complete && discardedBytes == 0
            && unverifiableOnDisk == 0 && rejectedFromPeers == 0
            && feedsFromOtherMembers == 0 && writesFailed == 0
            && unverifiableFromOwnDevices == 0 && certificatesRefused == 0
            && unreadableSiblingFeeds == 0 && unexplainedContradictions == 0
    }

    public var hasDiverged: Bool { !forks.isEmpty }
}
