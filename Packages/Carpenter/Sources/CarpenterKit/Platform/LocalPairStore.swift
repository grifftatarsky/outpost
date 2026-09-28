import Foundation

public struct LocalPairStore: Codable, Sendable {
    public struct Record: Codable, Sendable {
        public var fields: [String: PacketField]
        public var storedAt: Date
        public var modifiedAt: Date
    }

    public struct Space: Codable, Sendable {
        public let owner: ParticipantID
        public let url: URL
        public var hint: PairHint?
        public var named: String?
        public var joined: Set<String> = []
        public var records: [String: Record] = [:]
        public var order: [String] = []
    }

    public private(set) var spaces: [URL: Space] = [:]
    public private(set) var packetOrder: [PacketID] = []
    private var serverNow = Date.distantPast
    private var made = 0

    public init() {}

    public static func account(of participant: ParticipantID) -> String {
        "_" + participant.rawValue.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public mutating func stamp(_ now: Date) -> Date {
        serverNow = max(serverNow.addingTimeInterval(0.001), now)
        return serverNow
    }

    // MARK: Spaces

    func mine(for peer: ParticipantID, in pairs: Pairs) -> URL? {
        guard let hint = pairs.hints[peer] else { return nil }
        return spaces.values.first { $0.owner == pairs.me && $0.hint == hint }?.url
    }

    func theirs(_ peer: ParticipantID, in pairs: Pairs) -> Space? {
        guard let hint = pairs.hints[peer] else { return nil }
        let me = Self.account(of: pairs.me)
        return spaces.values.first {
            $0.owner == peer && $0.hint == hint && $0.named == me && $0.joined.contains(me)
        }
    }

    private mutating func newSpace(for owner: ParticipantID, hint: PairHint?, named: String?) -> URL {
        made += 1
        let url = URL(string: "https://icloud.invalid/share/\(UUID().uuidString)")!
        spaces[url] = Space(owner: owner, url: url, hint: hint, named: named)
        return url
    }

    public mutating func space(for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        let hint = try pairs.hint(for: peer)
        if let url = mine(for: peer, in: pairs) {
            if let account { spaces[url]?.named = account }
            return url
        }
        return newSpace(for: pairs.me, hint: hint, named: account)
    }

    public mutating func spaceForACode(in pairs: Pairs) -> URL {
        newSpace(for: pairs.me, hint: nil, named: nil)
    }

    public mutating func claim(_ url: URL, for peer: ParticipantID, naming account: String?, in pairs: Pairs) throws -> URL {
        let hint = try pairs.hint(for: peer)
        if let existing = mine(for: peer, in: pairs), existing != url {
            if spaces[url]?.owner == pairs.me, spaces[url]?.hint == nil { spaces[url] = nil }
            if let account { spaces[existing]?.named = account }
            return existing
        }
        guard var space = spaces[url], space.owner == pairs.me else {
            return try self.space(for: peer, naming: account, in: pairs)
        }
        space.hint = hint
        if let account { space.named = account }
        spaces[url] = space
        return url
    }

    public mutating func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs) -> JoinOutcome {
        guard var space = spaces[link.url], space.owner == peer, Self.account(of: peer) == link.account else {
            return .gone
        }
        let me = Self.account(of: pairs.me)
        guard space.named == me else { return .notYetNamed }
        space.joined.insert(me)
        spaces[link.url] = space
        return .joined
    }

    public mutating func close(_ peer: ParticipantID, in pairs: Pairs) {
        guard let url = mine(for: peer, in: pairs) else { return }
        for name in spaces[url]?.order ?? [] {
            if let id = UUID(uuidString: name) { packetOrder.removeAll { $0.rawValue == id } }
        }
        spaces[url] = nil
    }

    // MARK: Records in one's own space

    public mutating func write(
        _ name: String, _ fields: [String: PacketField], to peer: ParticipantID, in pairs: Pairs, at now: Date
    ) throws {
        let url = try space(for: peer, naming: nil, in: pairs)
        let instant = stamp(now)
        let storedAt = spaces[url]?.records[name]?.storedAt ?? instant
        if spaces[url]?.records[name] == nil { spaces[url]?.order.append(name) }
        spaces[url]?.records[name] = Record(fields: fields, storedAt: storedAt, modifiedAt: instant)
    }

    @discardableResult
    public mutating func remove(_ name: String, fromEverySpaceOf me: ParticipantID) -> Int {
        var removed = 0
        for url in spaces.keys where spaces[url]?.owner == me && spaces[url]?.records[name] != nil {
            spaces[url]?.records[name] = nil
            spaces[url]?.order.removeAll { $0 == name }
            removed += 1
        }
        return removed
    }

    public mutating func notePacket(_ id: PacketID) { packetOrder.append(id) }

    public mutating func forgetPacket(_ id: PacketID) {
        packetOrder.removeAll { $0 == id }
        for url in spaces.keys {
            spaces[url]?.records[id.rawValue.uuidString] = nil
            spaces[url]?.order.removeAll { $0 == id.rawValue.uuidString }
        }
    }

    public mutating func change(_ name: String, _ edit: (inout [String: PacketField]) -> Void, at now: Date) {
        let instant = stamp(now)
        for url in spaces.keys where spaces[url]?.records[name] != nil {
            edit(&spaces[url]!.records[name]!.fields)
            spaces[url]?.records[name]?.modifiedAt = instant
        }
    }

    // MARK: Reading

    public func records(inSpaceOf peer: ParticipantID, forMe pairs: Pairs) -> [(name: String, record: Record)] {
        guard let space = theirs(peer, in: pairs) else { return [] }
        return space.order.compactMap { name in space.records[name].map { (name, $0) } }
    }

    public func ownSpaces(of me: ParticipantID, in pairs: Pairs) -> [(peer: ParticipantID, space: Space)] {
        spaces.values.compactMap { space in
            guard space.owner == me, let hint = space.hint, let peer = pairs.peer(for: hint) else { return nil }
            return (peer, space)
        }
    }

    public var allRecords: [(url: URL, name: String, record: Record)] {
        spaces.values.flatMap { space in
            space.order.compactMap { name in space.records[name].map { (space.url, name, $0) } }
        }
    }
}

extension LocalPairStore {
    public static let photoPrefix = "photo-"

    public mutating func put(_ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs, at now: Date) throws {
        let fields = PacketWire.fields(of: packet)
        let weight = MailboxRules.weigh(fields)
        guard weight <= MailboxRules.recordByteCeiling else {
            throw MailboxError.recordTooLarge(bytes: weight, ceiling: MailboxRules.recordByteCeiling)
        }
        try write(packet.id.rawValue.uuidString, fields, to: peer, in: pairs, at: now)
        notePacket(packet.id)
    }

    public mutating func ring(_ peer: ParticipantID, in pairs: Pairs, at now: Date) throws {
        try write(
            PairWire.ringRecord, [PairWire.ring: .string(String(now.timeIntervalSince1970))], to: peer, in: pairs,
            at: now)
    }

    public mutating func fetch(from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs) -> [SyncPacket] {
        let found = records(inSpaceOf: peer, forMe: pairs)
        let held = Set(found.map(\.name))
        if theirs(peer, in: pairs) != nil, let url = mine(for: peer, in: pairs) {
            for name in spaces[url]?.order ?? [] {
                guard let packet = PairWire.packet(fromReceiptName: name), !held.contains(packet.rawValue.uuidString)
                else { continue }
                spaces[url]?.records[name] = nil
                spaces[url]?.order.removeAll { $0 == name }
            }
        }
        let mine = mine(for: peer, in: pairs).flatMap { spaces[$0] }
        return found.compactMap { name, record in
            guard let uuid = UUID(uuidString: name), var packet = PacketWire.packet(from: record.fields),
                !packet.recipients.isDisjoint(with: tags)
            else { return nil }
            packet.storedAt = record.storedAt
            packet.from = peer
            if let answer = mine?.records[PairWire.receiptName(for: PacketID(rawValue: uuid))],
                let receipt = PacketWire.receipt(from: answer.fields)
            {
                packet.receipts = [receipt]
            }
            return packet
        }
    }

    public mutating func acknowledge(
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs, at now: Date
    ) throws {
        try write(PairWire.receiptName(for: id), PacketWire.receiptFields(receipt), to: peer, in: pairs, at: now)
    }

    public func sentPackets(in pairs: Pairs) -> [PacketID: SentPacket] {
        var sent: [PacketID: SentPacket] = [:]
        for (peer, space) in ownSpaces(of: pairs.me, in: pairs) {
            let answers = Dictionary(
                records(inSpaceOf: peer, forMe: pairs).map { ($0.name, $0.record) }, uniquingKeysWith: { a, _ in a })
            for name in space.order {
                guard let uuid = UUID(uuidString: name), let record = space.records[name],
                    let packet = PacketWire.packet(from: record.fields)
                else { continue }
                let id = PacketID(rawValue: uuid)
                let receipts = answers[PairWire.receiptName(for: id)].flatMap { PacketWire.receipt(from: $0.fields) }
                sent[id] = SentPacket(
                    to: peer, recipients: packet.recipients, receipts: receipts.map { [$0] } ?? [],
                    createdAt: record.storedAt, contentDigest: packet.contentDigest)
            }
        }
        return sent
    }

    public mutating func withdraw(_ id: PacketID, in pairs: Pairs) {
        remove(id.rawValue.uuidString, fromEverySpaceOf: pairs.me)
        packetOrder.removeAll { $0 == id }
    }

    // MARK: Photos, one copy in each recipient's space

    public mutating func upload(_ attachment: OutgoingAttachment, in pairs: Pairs, at now: Date) throws {
        for (peer, tag) in attachment.recipients {
            try write(
                Self.photoPrefix + attachment.id.rawValue.uuidString, AttachmentWire.fields(of: attachment, for: tag),
                to: peer, in: pairs, at: now)
        }
    }

    public func download(_ id: AttachmentID, from sender: ParticipantID, in pairs: Pairs) -> Data? {
        records(inSpaceOf: sender, forMe: pairs)
            .first { $0.name == Self.photoPrefix + id.rawValue.uuidString }
            .flatMap { AttachmentWire.attachment(from: $0.record.fields)?.ciphertext }
    }

    public mutating func acknowledge(
        attachment id: AttachmentID, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs,
        at now: Date
    ) throws {
        try write(PairWire.receiptName(for: id), PacketWire.receiptFields(receipt), to: sender, in: pairs, at: now)
    }

    public func pendingAttachments(in pairs: Pairs) -> [AttachmentID: SentAttachment] {
        var recipients: [AttachmentID: Set<RecipientTag>] = [:]
        var receipts: [AttachmentID: [SealedReceipt]] = [:]
        for (peer, space) in ownSpaces(of: pairs.me, in: pairs) {
            let answers = Dictionary(
                records(inSpaceOf: peer, forMe: pairs).map { ($0.name, $0.record) }, uniquingKeysWith: { a, _ in a })
            for name in space.order where name.hasPrefix(Self.photoPrefix) {
                guard let uuid = UUID(uuidString: String(name.dropFirst(Self.photoPrefix.count))),
                    let record = space.records[name]
                else { continue }
                let id = AttachmentID(rawValue: uuid)
                recipients[id, default: []].formUnion(AttachmentWire.recipients(in: record.fields))
                if let answer = answers[PairWire.receiptName(for: id)], answer.modifiedAt >= record.modifiedAt,
                    let receipt = PacketWire.receipt(from: answer.fields)
                {
                    receipts[id, default: []].append(receipt)
                }
            }
        }
        return recipients.reduce(into: [:]) { found, entry in
            found[entry.key] = SentAttachment(recipients: entry.value, receipts: receipts[entry.key] ?? [])
        }
    }

    public func sweepableAttachments(in pairs: Pairs, at now: Date) -> [AttachmentID: Date] {
        let settled = now.addingTimeInterval(-MailboxRules.sweepAge)
        var found: [AttachmentID: Date] = [:]
        for space in spaces.values where space.owner == pairs.me {
            for name in space.order where name.hasPrefix(Self.photoPrefix) {
                guard let uuid = UUID(uuidString: String(name.dropFirst(Self.photoPrefix.count))),
                    let record = space.records[name], record.storedAt < settled
                else { continue }
                let id = AttachmentID(rawValue: uuid)
                found[id] = max(found[id] ?? .distantPast, record.modifiedAt)
            }
        }
        return found
    }

    public mutating func delete(attachment id: AttachmentID, in pairs: Pairs) {
        remove(Self.photoPrefix + id.rawValue.uuidString, fromEverySpaceOf: pairs.me)
    }
}

extension LocalPairStore {
    private func counterpart(of space: Space) -> Space? {
        guard let hint = space.hint else { return nil }
        return spaces.values.first { $0.hint == hint && $0.owner != space.owner }
    }

    public var everySentPacket: [PacketID: SentPacket] {
        var sent: [PacketID: SentPacket] = [:]
        for space in spaces.values {
            let other = counterpart(of: space)
            for name in space.order {
                guard let uuid = UUID(uuidString: name), let record = space.records[name],
                    let packet = PacketWire.packet(from: record.fields)
                else { continue }
                let id = PacketID(rawValue: uuid)
                let receipt = other?.records[PairWire.receiptName(for: id)].flatMap { PacketWire.receipt(from: $0.fields) }
                sent[id] = SentPacket(
                    to: other?.owner ?? space.owner, recipients: packet.recipients, receipts: receipt.map { [$0] } ?? [],
                    createdAt: record.storedAt, contentDigest: packet.contentDigest)
            }
        }
        return sent
    }

    public var everyPendingAttachment: [AttachmentID: SentAttachment] {
        var recipients: [AttachmentID: Set<RecipientTag>] = [:]
        var receipts: [AttachmentID: [SealedReceipt]] = [:]
        for space in spaces.values {
            let other = counterpart(of: space)
            for name in space.order where name.hasPrefix(Self.photoPrefix) {
                guard let uuid = UUID(uuidString: String(name.dropFirst(Self.photoPrefix.count))),
                    let record = space.records[name]
                else { continue }
                let id = AttachmentID(rawValue: uuid)
                recipients[id, default: []].formUnion(AttachmentWire.recipients(in: record.fields))
                if let answer = other?.records[PairWire.receiptName(for: id)], answer.modifiedAt >= record.modifiedAt,
                    let receipt = PacketWire.receipt(from: answer.fields)
                {
                    receipts[id, default: []].append(receipt)
                }
            }
        }
        return recipients.reduce(into: [:]) { found, entry in
            found[entry.key] = SentAttachment(recipients: entry.value, receipts: receipts[entry.key] ?? [])
        }
    }
}
