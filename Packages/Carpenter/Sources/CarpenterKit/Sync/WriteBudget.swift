import Foundation

public struct WriteBudget: Hashable, Sendable {
    public let ceiling: Int
    public let window: TimeInterval

    public private(set) var used: Int
    public private(set) var windowStartedAt: Date

    public static let provisionalDailyCeiling = 400

    public init(
        ceiling: Int = provisionalDailyCeiling,
        window: TimeInterval = 86_400,
        startingAt: Date
    ) {
        self.ceiling = ceiling
        self.window = window
        used = 0
        windowStartedAt = startingAt
    }

    public var remaining: Int { max(ceiling - used, 0) }

    public var isExhausted: Bool { remaining == 0 }

    public var fractionUsed: Double {
        ceiling > 0 ? Double(used) / Double(ceiling) : 1
    }

    public mutating func canAfford(_ count: Int, at instant: Date) -> Bool {
        rollOver(at: instant)
        return used + count <= ceiling
    }

    public mutating func consume(_ count: Int, at instant: Date) throws {
        guard canAfford(count, at: instant) else { throw MailboxError.budgetExhausted }
        used += count
    }

    private mutating func rollOver(at instant: Date) {
        guard instant.timeIntervalSince(windowStartedAt) >= window else { return }
        used = 0
        windowStartedAt = instant
    }
}

public actor BudgetedMailbox: Mailbox {
    private let underlying: any Mailbox
    private let clock: any Clock

    public private(set) var budget: WriteBudget

    public init(wrapping mailbox: any Mailbox, budget: WriteBudget, clock: any Clock = SystemClock()) {
        underlying = mailbox
        self.budget = budget
        self.clock = clock
    }

    public func put(_ packet: SyncPacket) async throws {
        try budget.consume(1, at: clock.now)
        do {
            try await underlying.put(packet)
        } catch {
            budget.refund(1)
            throw error
        }
    }

    public func fetch(for tags: Set<RecipientTag>) async throws -> [SyncPacket] {
        try await underlying.fetch(for: tags)
    }

    public func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) async throws {
        try await underlying.acknowledge(id, by: tags)
    }

    public func pendingDeliveries() async throws -> [PacketID: Set<RecipientTag>] {
        try await underlying.pendingDeliveries()
    }

    public func ring(_ bell: MessageBell) async throws {
        try await underlying.ring(bell)
    }
}

extension WriteBudget {
    fileprivate mutating func refund(_ count: Int) {
        used = max(used - count, 0)
    }
}
