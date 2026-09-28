import CarpenterKit
import Foundation

public actor HookedMailbox: Mailbox {
    public let inner: InMemoryMailbox
    private var duringPut: (@Sendable () async -> Void)?
    private var duringFetch: (@Sendable () async -> Void)?
    private var refusal: MailboxFailure?

    public init(inner: InMemoryMailbox = InMemoryMailbox()) {
        self.inner = inner
    }

    public func onPut(_ work: @escaping @Sendable () async -> Void) { duringPut = work }
    public func onFetch(_ work: @escaping @Sendable () async -> Void) { duringFetch = work }
    public func refuse(_ failure: MailboxFailure) { refusal = failure }
    public func relent() { refusal = nil }

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws {
        if let refusal { throw refusal }
        if let duringPut {
            self.duringPut = nil
            await duringPut()
        }
        try await inner.put(packet, to: peer, in: pairs)
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws
        -> [SyncPacket]
    {
        if let duringFetch {
            self.duringFetch = nil
            await duringFetch()
        }
        return await inner.fetch(from: peer, for: tags, in: pairs)
    }

    public func account(in pairs: Pairs) async throws -> String { await inner.account(in: pairs) }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws -> URL {
        try await inner.space(for: peer, naming: account, in: pairs)
    }

    public func spaceForACode(in pairs: Pairs) async throws -> URL { await inner.spaceForACode(in: pairs) }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) async throws
        -> URL
    {
        try await inner.claim(url, for: peer, naming: account, in: pairs)
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        await inner.join(link, of: peer, in: pairs)
    }

    public func reads(_ peer: ParticipantID, in pairs: Pairs) async throws -> Bool {
        await inner.reads(peer, in: pairs)
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws { await inner.close(peer, in: pairs) }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws { try await inner.ring(peer, in: pairs) }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        try await inner.acknowledge(id, from: peer, with: receipt, in: pairs)
    }

    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] {
        await inner.sentPackets(in: pairs)
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws { await inner.withdraw(id, in: pairs) }
}
