import Foundation

public struct DebugActions: Sendable {
    public let checkMailbox: @MainActor @Sendable () async -> Void
    public let rotateMailboxShare: @MainActor @Sendable () async -> Void
    public let pretendFocus: @MainActor @Sendable (Bool) async -> Void

    public init(
        checkMailbox: @escaping @MainActor @Sendable () async -> Void,
        rotateMailboxShare: @escaping @MainActor @Sendable () async -> Void = {},
        pretendFocus: @escaping @MainActor @Sendable (Bool) async -> Void = { _ in }
    ) {
        self.checkMailbox = checkMailbox
        self.rotateMailboxShare = rotateMailboxShare
        self.pretendFocus = pretendFocus
    }
}
