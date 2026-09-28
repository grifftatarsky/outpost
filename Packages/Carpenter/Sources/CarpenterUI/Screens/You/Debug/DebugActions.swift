import Foundation

public struct DebugActions: Sendable {
    public let checkMailbox: @MainActor @Sendable () async -> Void
    public let rotateMailboxShare: @MainActor @Sendable () async -> Void
    public let pretendFocus: @MainActor @Sendable (Bool) async -> Void
    public let fitTest: (@MainActor @Sendable (URL, @escaping @MainActor @Sendable (FitTestStage) -> Void) async -> FitTestReport)?
    public let contactSpaceTest: (@MainActor @Sendable (ContactSpaceStep) async -> [String])?

    public init(
        checkMailbox: @escaping @MainActor @Sendable () async -> Void,
        rotateMailboxShare: @escaping @MainActor @Sendable () async -> Void = {},
        pretendFocus: @escaping @MainActor @Sendable (Bool) async -> Void = { _ in },
        fitTest: (@MainActor @Sendable (URL, @escaping @MainActor @Sendable (FitTestStage) -> Void) async -> FitTestReport)? = nil,
        contactSpaceTest: (@MainActor @Sendable (ContactSpaceStep) async -> [String])? = nil
    ) {
        self.checkMailbox = checkMailbox
        self.rotateMailboxShare = rotateMailboxShare
        self.pretendFocus = pretendFocus
        self.fitTest = fitTest
        self.contactSpaceTest = contactSpaceTest
    }
}

public enum ContactSpaceStep: Hashable, Sendable {
    case join
    case watch
    case check
    case remove
}

public enum FitTestStage: Hashable, Sendable {
    case fitting
    case uploading(done: Int)
    case downloading(done: Int, of: Int)
    case clearing
}

public struct FitTestReport: Hashable, Sendable {
    public var originalBytes = 0
    public var fittedBytes = 0
    public var seconds: TimeInterval = 0
    public var width = 0
    public var height = 0
    public var fitSeconds: TimeInterval = 0
    public var sealSeconds: TimeInterval = 0
    public var pieces = 0
    public var sealedBytes = 0
    public var uploadSeconds: TimeInterval = 0
    public var downloadSeconds: TimeInterval = 0
    public var piecesMatched = 0
    public var cleared = false
    public var failure: String?

    public init() {}
}
