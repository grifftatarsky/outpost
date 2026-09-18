import Foundation

public actor FileMailbox: Mailbox {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private struct Stored: Codable {
        let packet: SyncPacket
        var outstanding: [Data]
    }

    public func put(_ packet: SyncPacket) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let stored = Stored(
            packet: packet, outstanding: packet.recipients.map(\.rawValue))
        try encode(stored).write(to: url(for: packet.id), options: .atomic)
    }

    public func fetch(for tags: Set<RecipientTag>) throws -> [SyncPacket] {
        let wanted = Set(tags.map(\.rawValue))
        return try all()
            .filter { !wanted.isDisjoint(with: $0.value.outstanding) }
            .map(\.value.packet)
    }

    public func pendingDeliveries() throws -> [PacketID: Set<RecipientTag>] {
        try all().values.reduce(into: [:]) { found, stored in
            found[stored.packet.id] = Set(stored.outstanding.map(RecipientTag.init(rawValue:)))
        }
    }

    public func acknowledge(_ id: PacketID, by tags: Set<RecipientTag>) throws {
        let file = url(for: id)
        guard let data = try? Data(contentsOf: file),
            var stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            throw MailboxError.unknownPacket
        }

        let wanted = Set(tags.map(\.rawValue))
        stored.outstanding.removeAll { wanted.contains($0) }

        if stored.outstanding.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try encode(stored).write(to: file, options: .atomic)
        }
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
