import Foundation

public protocol EntrySync: Sendable {
    @discardableResult
    func send(_ records: [SiblingRecord], deleting: [SiblingRecord.Name]) async throws -> [SiblingRecord.Name: Date]

    func onIncoming(_ handler: @escaping @Sendable (SiblingRecord) async -> Void) async

    func start() async throws

    func refresh() async throws

    func forgetOwnContribution() async throws
}
