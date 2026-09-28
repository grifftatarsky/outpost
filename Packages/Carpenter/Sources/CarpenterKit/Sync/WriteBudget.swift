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

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws {
        try budget.consume(1, at: clock.now)
        do {
            try await underlying.put(packet, to: peer, in: pairs)
        } catch {
            budget.refund(1)
            throw error
        }
    }

    public func account(in pairs: Pairs) async throws -> String {
        try await underlying.account(in: pairs)
    }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        try await underlying.space(for: peer, naming: account, in: pairs)
    }

    public func spaceForACode(in pairs: Pairs) async throws -> URL {
        try await underlying.spaceForACode(in: pairs)
    }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        try await underlying.claim(url, for: peer, naming: account, in: pairs)
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        try await underlying.join(link, of: peer, in: pairs)
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws {
        try await underlying.close(peer, in: pairs)
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws -> [SyncPacket] {
        try await underlying.fetch(from: peer, for: tags, in: pairs)
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        try await underlying.acknowledge(id, from: peer, with: receipt, in: pairs)
    }

    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] {
        try await underlying.sentPackets(in: pairs)
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws {
        try await underlying.withdraw(id, in: pairs)
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws {
        try await underlying.ring(peer, in: pairs)
    }
}

extension WriteBudget {
    fileprivate mutating func refund(_ count: Int) {
        used = max(used - count, 0)
    }
}
