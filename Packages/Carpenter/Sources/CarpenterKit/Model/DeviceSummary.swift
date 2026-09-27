import Foundation

public struct DeviceSummary: Identifiable, Hashable, Sendable {
    public let id: DeviceID
    public let isCurrent: Bool
    public let addedAt: Date?
    public let revokedAt: Date?

    public let hasSpoken: Bool

    public let name: String?

    public init(
        id: DeviceID, isCurrent: Bool, addedAt: Date?, revokedAt: Date? = nil,
        hasSpoken: Bool = true, name: String? = nil
    ) {
        self.id = id
        self.isCurrent = isCurrent
        self.addedAt = addedAt
        self.revokedAt = revokedAt
        self.hasSpoken = hasSpoken
        self.name = name
    }

    public var isActive: Bool { revokedAt == nil }

    public var shortCode: String { id.shortCode }

    public var isNamed: Bool { name?.isEmpty == false }
}
