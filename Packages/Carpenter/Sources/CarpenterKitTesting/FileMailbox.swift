import CarpenterKit
import Foundation

public actor FileMailbox: Mailbox {
    private let file: URL

    public init(directory: URL) {
        file = directory.appending(path: "pairs.json")
    }

    private func change<T>(_ body: (inout LocalPairStore) throws -> T) throws -> T {
        var store = (try? JSONDecoder().decode(LocalPairStore.self, from: Data(contentsOf: file))) ?? LocalPairStore()
        let result = try body(&store)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(store).write(to: file, options: .atomic)
        return result
    }

    public func account(in pairs: Pairs) -> String { LocalPairStore.account(of: pairs.me) }

    public func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        try change { try $0.space(for: peer, naming: account, in: pairs, as: self.account(in: pairs)) }
    }

    public func spaceForACode(in pairs: Pairs) throws -> URL { try change { $0.spaceForACode(in: pairs, as: self.account(in: pairs)) } }

    public func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        try change { try $0.claim(url, for: peer, naming: account, in: pairs, as: self.account(in: pairs)) }
    }

    public func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) throws -> JoinOutcome {
        try change { $0.join(link, of: peer, in: pairs, as: self.account(in: pairs)) }
    }


    public func reads(_ peer: ParticipantID, in pairs: Pairs) throws -> Bool {

        try change { $0.reads(peer, in: pairs, as: self.account(in: pairs)) }

    }

    public func close(_ peer: ParticipantID, in pairs: Pairs) throws { try change { $0.close(peer, in: pairs, as: self.account(in: pairs)) } }

    public func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs) throws {
        try change { try $0.put(packet, to: peer, in: pairs, as: self.account(in: pairs), at: Date()) }
    }

    public func ring(_ peer: ParticipantID, in pairs: Pairs) throws {
        try change { try $0.ring(peer, in: pairs, as: self.account(in: pairs), at: Date()) }
    }

    public func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) throws -> [SyncPacket] {
        try change { $0.fetch(from: peer, for: tags, in: pairs, as: self.account(in: pairs)) }
    }

    public func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs
    ) throws {
        try change { try $0.acknowledge(id, from: peer, with: receipt, in: pairs, as: self.account(in: pairs), at: Date()) }
    }

    public func sentPackets(in pairs: Pairs) throws -> [PacketID: SentPacket] {
        try change { $0.sentPackets(in: pairs, as: self.account(in: pairs)) }
    }

    public func withdraw(_ id: PacketID, in pairs: Pairs) throws { try change { $0.withdraw(id, as: self.account(in: pairs)) } }
}
