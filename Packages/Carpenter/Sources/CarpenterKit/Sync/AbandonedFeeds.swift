import Foundation

public enum AbandonedFeeds {
    public struct Candidate: Hashable, Sendable {
        public let device: DeviceID
        public let writtenAt: Date?

        public init(device: DeviceID, writtenAt: Date?) {
            self.device = device
            self.writtenAt = writtenAt
        }
    }

    public static let graceInterval: TimeInterval = 30 * 86_400

    public static func reapable(
        among candidates: [Candidate],
        knownDevices: Set<DeviceID>,
        thisDevice: DeviceID,
        now: Date,
        graceInterval: TimeInterval = AbandonedFeeds.graceInterval
    ) -> [DeviceID] {
        candidates.compactMap { candidate in
            guard candidate.device != thisDevice else { return nil }
            guard !knownDevices.contains(candidate.device) else { return nil }
            guard let writtenAt = candidate.writtenAt else { return nil }
            guard now.timeIntervalSince(writtenAt) > graceInterval else { return nil }
            return candidate.device
        }
    }
}
