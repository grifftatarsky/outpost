import CarpenterKit
import Foundation

public struct TestProfilesControl: Sendable {
    public let profiles: [TestProfile]
    public let activeID: UUID?
    public let supports: @Sendable (URL) -> Bool
    public let add: @MainActor @Sendable (TestProfile) -> TestProfileProblem?
    public let start: @MainActor @Sendable (UUID) async -> TestProfileProblem?
    public let stop: @MainActor @Sendable () async -> TestProfileProblem?
    public let remove: @MainActor @Sendable (UUID) async -> TestProfileProblem?

    public init(
        profiles: [TestProfile],
        activeID: UUID?,
        supports: @escaping @Sendable (URL) -> Bool,
        add: @escaping @MainActor @Sendable (TestProfile) -> TestProfileProblem?,
        start: @escaping @MainActor @Sendable (UUID) async -> TestProfileProblem?,
        stop: @escaping @MainActor @Sendable () async -> TestProfileProblem?,
        remove: @escaping @MainActor @Sendable (UUID) async -> TestProfileProblem?
    ) {
        self.profiles = profiles
        self.activeID = activeID
        self.supports = supports
        self.add = add
        self.start = start
        self.stop = stop
        self.remove = remove
    }

    public var active: TestProfile? {
        profiles.first { $0.id == activeID }
    }
}
