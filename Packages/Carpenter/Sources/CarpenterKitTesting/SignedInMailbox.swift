import CarpenterKit
import Foundation

public struct SignedInMailbox: Mailbox {
    let base: InMemoryMailbox
    public let account: String

    public func account(in pairs: Pairs) async throws -> String { account }

    public func space(for peer: ParticipantID, naming reader: String?, in pairs: Pairs) async throws -> URL {
        try await base.acting(as: account) { try $0.space(for: peer, naming: reader, in: pairs) }
    }

    public func spaceForACode(in pairs: Pairs) async throws -> URL {
        await base.acting(as: account) { $0.spaceForACode(in: pairs) }
    }

    public func claim(_ url: URL, for peer: ParticipantID, naming reader: String?, in pairs: Pairs) async throws -> URL {
        try await base.acting(as: account) { try $0.claim(url, for: peer, naming: reader, in: pairs) }
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) async throws -> JoinOutcome {
        await base.acting(as: account) { $0.join(link, of: peer, in: pairs) }
    }

    public func reads(_ peer: ParticipantID, in pairs: Pairs) async throws -> Bool {
        await base.acting(as: account) { $0.reads(peer, in: pairs) }
    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) async throws {
        await base.acting(as: account) { $0.close(peer, in: pairs) }
    }

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) async throws {
        try await base.acting(as: account) { try $0.put(packet, to: peer, in: pairs) }
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) async throws {
        try await base.acting(as: account) { try $0.ring(peer, in: pairs) }
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) async throws -> [SyncPacket] {
        await base.acting(as: account) { $0.fetch(from: peer, for: tags, in: pairs) }
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) async throws {
        try await base.acting(as: account) { try $0.acknowledge(id, from: peer, with: receipt, in: pairs) }
    }

    public func sentPackets(in pairs: Pairs) async throws -> [PacketID: SentPacket] {
        await base.acting(as: account) { $0.sentPackets(in: pairs) }
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) async throws {
        await base.acting(as: account) { $0.withdraw(id, in: pairs) }
    }
}
