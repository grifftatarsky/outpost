import CarpenterKit
import Foundation

public actor FileMailbox: Mailbox {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private struct Stored: Codable {
        let packet: SyncPacket
        let written: Date
        var receipts: [SealedReceipt]?
        var modified: Date?
    }

    public func put(_ packet: SyncPacket) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let stored = Stored(packet: packet, written: Date(), receipts: [], modified: nil)
        try encode(stored).write(to: url(for: packet.id), options: .atomic)
    }

    public func fetch(for tags: Set<RecipientTag>) throws -> [SyncPacket] {
        try all().values
            .filter { !tags.isDisjoint(with: $0.packet.recipients) }
            .sorted {
                $0.written != $1.written
                    ? $0.written < $1.written : $0.packet.id.rawValue.uuidString < $1.packet.id.rawValue.uuidString
            }
            .map { stored in
                var packet = stored.packet
                packet.storedAt = stored.modified ?? stored.written
                packet.receipts = stored.receipts ?? []
                return packet
            }
    }

    public func sentPackets() throws -> [PacketID: SentPacket] {
        try all().values.reduce(into: [:]) { found, stored in
            found[stored.packet.id] = SentPacket(
                recipients: stored.packet.recipients, receipts: stored.receipts ?? [], createdAt: stored.written,
                contentDigest: stored.packet.contentDigest)
        }
    }

    public func acknowledge(_ id: PacketID, with receipt: SealedReceipt) throws {
        let file = url(for: id)
        guard let data = try? Data(contentsOf: file),
            var stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            throw MailboxError.unknownPacket
        }
        var receipts = stored.receipts ?? []
        guard !receipts.contains(receipt) else { return }
        receipts.append(receipt)
        stored.receipts = receipts
        stored.modified = Date()
        try encode(stored).write(to: file, options: .atomic)
    }

    public func withdraw(_ id: PacketID) throws {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    public private(set) var bells: [MessageBell] = []

    public func ring(_ bell: MessageBell) throws { bells.append(bell) }

    public func pendingCount() throws -> Int { try all().count }

    private func all() throws -> [URL: Stored] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [:] }

        var found: [URL: Stored] = [:]
        for file in files where file.pathExtension == "packet" {
            guard let data = try? Data(contentsOf: file),
                let stored = try? JSONDecoder().decode(Stored.self, from: data)
            else { continue }
            found[file] = stored
        }
        return found
    }

    private func url(for id: PacketID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString).packet")
    }

    private func encode(_ stored: Stored) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(stored)
    }
}
