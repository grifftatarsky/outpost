#if DEBUG

    import CarpenterKit
    import CryptoKit
    import Foundation
    import os

    actor FileMailbox: Mailbox, MediaMailbox {
        private let root: URL
        private let owner: String

        private let packets: URL
        private let acknowledgements: URL
        private let media: URL
        private let bells: URL
        private let refusal: MailboxFailure?

        init(root: URL, owner: String, refusal: MailboxFailure? = nil) throws {
            self.root = root
            self.owner = owner
            self.refusal = refusal
            packets = root.appending(path: "packets")
            acknowledgements = root.appending(path: "acks")
            media = root.appending(path: "media")
            bells = root.appending(path: "bells")
            for directory in [packets, acknowledgements, media, bells] {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
            }
        }

        // MARK: What is on disk

        private struct StoredPacket: Codable {
            let owner: String
            let sequence: UInt64
            let fields: [String: WireValue]
        }

        private enum WireValue: Codable {
            case string(String)
            case data(Data)
            case dataList([Data])

            init(_ field: PacketField) {
                switch field {
                case .string(let value): self = .string(value)
                case .data(let value): self = .data(value)
                case .dataList(let value): self = .dataList(value)
                }
            }

            var field: PacketField {
                switch self {
                case .string(let value): return .string(value)
                case .data(let value): return .data(value)
                case .dataList(let value): return .dataList(value)
                }
            }
        }

        private struct StoredAttachment: Codable {
            let owner: String
            let fields: [String: WireValue]
        }

        // MARK: Packets

        func put(_ packet: SyncPacket) throws {
            if let refusal { throw refusal }
            let stored = StoredPacket(
                owner: owner,
                sequence: Self.nextSequence(),
                fields: PacketWire.fields(of: packet).mapValues(WireValue.init))
            try write(
                stored,
                to: packets.appending(path: "\(stored.sequence)-\(packet.id.rawValue.uuidString).json"))
        }

        func fetch(for tags: Set<RecipientTag>) throws -> [SyncPacket] {
            try readPackets()
                .filter { $0.stored.owner != owner }
                .sorted { $0.stored.sequence < $1.stored.sequence }
                .compactMap { entry in
                    guard var packet = PacketWire.packet(from: entry.stored.fields.mapValues(\.field)),
                        !packet.recipients.isDisjoint(with: tags)
                    else { return nil }
                    packet.storedAt = entry.written
                    packet.receipts = receipts(of: entry.id)
                    return packet
                }
        }

        func acknowledge(_ id: PacketID, with receipt: SealedReceipt) throws {
            guard try readPackets().contains(where: { $0.id == id }) else {
                throw MailboxError.unknownPacket
            }
            let digest = Data(SHA256.hash(data: receipt.tag.rawValue + receipt.sealed)).prefix(12)
            let name = "\(id.rawValue.uuidString)-\(digest.base64EncodedString().replacingOccurrences(of: "/", with: "_"))"
            let file = acknowledgements.appending(path: name)
            if !FileManager.default.fileExists(atPath: file.path) {
                try JSONEncoder().encode(receipt).write(to: file, options: .atomic)
            }
        }

        func sentPackets() throws -> [PacketID: SentPacket] {
            try readPackets()
                .filter { $0.stored.owner == owner }
                .reduce(into: [:]) { found, entry in
                    guard let packet = PacketWire.packet(from: entry.stored.fields.mapValues(\.field)) else { return }
                    found[entry.id] = SentPacket(
                        recipients: packet.recipients, receipts: receipts(of: entry.id), createdAt: entry.written)
                }
        }

        func withdraw(_ id: PacketID) throws {
            for entry in try readPackets() where entry.id == id && entry.stored.owner == owner {
                try? FileManager.default.removeItem(at: entry.file)
            }
        }

        func ring(_ bell: MessageBell) throws {
            try? Data(String(describing: bell).utf8).write(
                to: bells.appending(path: "\(bell.name).txt"), options: .atomic)
        }

        // MARK: Attachments

        func upload(_ attachment: OutgoingAttachment) throws {
            let stored = StoredAttachment(
                owner: owner,
                fields: AttachmentWire.fields(of: attachment).mapValues(WireValue.init))
            try write(stored, to: media.appending(path: "\(attachment.id.rawValue.uuidString).json"))
        }

        func download(_ id: AttachmentID, hint tags: Set<RecipientTag>) throws -> Data? {
            let file = media.appending(path: "\(id.rawValue.uuidString).json")
            guard let bytes = try? Data(contentsOf: file),
                let stored = try? JSONDecoder().decode(StoredAttachment.self, from: bytes)
            else { return nil }
            return AttachmentWire.attachment(from: stored.fields.mapValues(\.field))?.ciphertext
        }

        func acknowledge(attachment id: AttachmentID, by tags: Set<RecipientTag>) throws {
            for tag in tags {
                let name = "media-\(id.rawValue.uuidString)-\(tag.rawValue.base64EncodedString().replacingOccurrences(of: "/", with: "_"))"
                let file = acknowledgements.appending(path: name)
                if !FileManager.default.fileExists(atPath: file.path) {
                    try Data().write(to: file, options: .atomic)
                }
            }
        }

        func pendingAttachments() throws -> [AttachmentID: Set<RecipientTag>] { [:] }

        func sweepableAttachments() throws -> [AttachmentID: Set<RecipientTag>] { [:] }

        func delete(attachment id: AttachmentID) throws {
            try? FileManager.default.removeItem(
                at: media.appending(path: "\(id.rawValue.uuidString).json"))
        }

        // MARK: Reading the directory

        private struct Entry {
            let id: PacketID
            let stored: StoredPacket
            let written: Date?
            let file: URL
        }

        private func readPackets() throws -> [Entry] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: packets, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return files.compactMap { file in
                guard let bytes = try? Data(contentsOf: file),
                    let stored = try? JSONDecoder().decode(StoredPacket.self, from: bytes),
                    case .string(let text)? = stored.fields[PacketWire.packetID]?.field,
                    let uuid = UUID(uuidString: text)
                else { return nil }
                let written = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return Entry(id: PacketID(rawValue: uuid), stored: stored, written: written, file: file)
            }
        }

        private func receipts(of id: PacketID) -> [SealedReceipt] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: acknowledgements.path)) ?? []
            return names.filter { $0.hasPrefix(id.rawValue.uuidString) }.sorted().compactMap { name in
                guard let bytes = try? Data(contentsOf: acknowledgements.appending(path: name)) else { return nil }
                return try? JSONDecoder().decode(SealedReceipt.self, from: bytes)
            }
        }

        private func write(_ value: some Encodable, to file: URL) throws {
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
        }

        private static func nextSequence() -> UInt64 {
            UInt64(Date().timeIntervalSince1970 * 1_000_000)
        }
    }

    struct RigAccount: AccountRegistry {
        func occupancy() async -> AccountOccupancy { .empty }
    }

    enum RigCodes {
        static func leave(_ code: String, as name: String) {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--mailbox"), index + 1 < arguments.count
            else { return }
            let codes = URL(fileURLWithPath: arguments[index + 1]).appending(path: "codes")
            do {
                try FileManager.default.createDirectory(at: codes, withIntermediateDirectories: true)
                try code.write(to: codes.appending(path: name), atomically: true, encoding: .utf8)
            } catch {
                Diagnostics.sync.error(
                    "rig mailbox: could not leave a code — \(String(describing: error), privacy: .public)")
            }
        }
    }

    extension FileMailbox {
        static func fromLaunchArguments() -> FileMailbox? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--mailbox"), index + 1 < arguments.count
            else { return nil }

            let owner: String
            if let kept = UserDefaults.standard.string(forKey: "rig.mailboxOwner") {
                owner = kept
            } else {
                owner = UUID().uuidString
                UserDefaults.standard.set(owner, forKey: "rig.mailboxOwner")
            }

            do {
                let refusal: MailboxFailure? =
                    switch arguments.firstIndex(of: "--mailbox-refuses").flatMap({
                        arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
                    }) {
                    case "full": .noRoomInICloud
                    case "signed-out": .notSignedIn
                    default: nil
                    }
                let mailbox = try FileMailbox(
                    root: URL(fileURLWithPath: arguments[index + 1]), owner: owner, refusal: refusal)
                Diagnostics.sync.notice(
                    "rig mailbox: a directory, not CloudKit — proves nothing below the seam")
                return mailbox
            } catch {
                Diagnostics.sync.error(
                    "rig mailbox: could not open — \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

#endif
