import Foundation

public struct LocalPairStore: Codable, Sendable {
    public struct Record: Codable, Sendable {
        public var fields: [String: PacketField]
        public var storedAt: Date
        public var modifiedAt: Date
    }

    public struct Space: Codable, Sendable {
        public let owner: ParticipantID
        public let account: String
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
        "_" + participant.rawValue.prefix(16).lowercaseHex
    }

    public mutating func stamp(_ now: Date) -> Date {
        serverNow = max(serverNow.addingTimeInterval(0.001), now)
        return serverNow
    }

    // MARK: Spaces

    func mine(for peer: ParticipantID, in pairs: Pairs, as account: String) -> URL? {
        guard let hint = pairs.hints[peer] else { return nil }
        return spaces.values.filter { $0.account == account && $0.hint == hint }.map(\.url)
            .min { $0.absoluteString < $1.absoluteString }
    }

    func theirs(_ peer: ParticipantID, in pairs: Pairs, as account: String) -> [Space] {
        guard let hint = pairs.hints[peer] else { return [] }
        return spaces.values.filter {
            pairs.reads(peer, from: $0.account) && $0.account != account && $0.hint == hint && $0.named == account
                && $0.joined.contains(account)
        }.sorted { $0.url.absoluteString < $1.url.absoluteString }
    }

    private mutating func newSpace(for owner: ParticipantID, as account: String, hint: PairHint?) -> URL {
        made += 1
        let url = URL(string: "https://icloud.invalid/share/\(UUID().uuidString)")!
        spaces[url] = Space(owner: owner, account: account, url: url, hint: hint)
        return url
    }

    private mutating func ensureSpace(for peer: ParticipantID, in pairs: Pairs, as account: String) throws -> URL {
        let hint = try pairs.hint(for: peer)
        return mine(for: peer, in: pairs, as: account) ?? newSpace(for: pairs.me, as: account, hint: hint)
    }

    public mutating func space(
        for peer: ParticipantID, naming reader: String?, in pairs: Pairs, as account: String
    ) throws -> URL {
        let url = try ensureSpace(for: peer, in: pairs, as: account)
        name(reader, in: url)
        return url
    }

    private mutating func name(_ reader: String?, in url: URL) {
        guard let reader, spaces[url]?.named != reader else { return }
        spaces[url]?.named = reader
        spaces[url]?.joined = []
    }

    public mutating func spaceForACode(in pairs: Pairs, as account: String) -> URL {
        newSpace(for: pairs.me, as: account, hint: nil)
    }

    public mutating func claim(
        _ url: URL, for peer: ParticipantID, naming reader: String?, in pairs: Pairs, as account: String
    ) throws -> URL {
        let hint = try pairs.hint(for: peer)
        if let existing = mine(for: peer, in: pairs, as: account), existing != url {
            if spaces[url]?.account == account, spaces[url]?.hint == nil { spaces[url] = nil }
            name(reader, in: existing)
            return existing
        }
        guard spaces[url]?.account == account else {
            return try space(for: peer, naming: reader, in: pairs, as: account)
        }
        spaces[url]?.hint = hint
        name(reader, in: url)
        return url
    }

    public mutating func join(_ link: PairLink, of peer: ParticipantID, in pairs: Pairs, as account: String) -> JoinOutcome {
        guard var space = spaces[link.url], space.account == link.account, space.account != account else {
            return .gone
        }
        guard space.named == account else { return .notYetNamed }
        space.joined.insert(account)
        spaces[link.url] = space
        return .joined
    }

    public func reads(_ peer: ParticipantID, in pairs: Pairs, as account: String) -> Bool {
        !theirs(peer, in: pairs, as: account).isEmpty
    }

    public mutating func close(_ peer: ParticipantID, in pairs: Pairs, as account: String) {
        guard let url = mine(for: peer, in: pairs, as: account) else { return }
        for name in spaces[url]?.order ?? [] {
            if let id = UUID(uuidString: name) { packetOrder.removeAll { $0.rawValue == id } }
        }
        spaces[url] = nil
    }

    // MARK: Records in one's own space

    public mutating func write(
        _ name: String, _ fields: [String: PacketField], to peer: ParticipantID, in pairs: Pairs, as account: String,
        at now: Date
    ) throws {
        let url = try ensureSpace(for: peer, in: pairs, as: account)
        let instant = stamp(now)
        let storedAt = spaces[url]?.records[name]?.storedAt ?? instant
        if spaces[url]?.records[name] == nil { spaces[url]?.order.append(name) }
        spaces[url]?.records[name] = Record(fields: fields, storedAt: storedAt, modifiedAt: instant)
    }

    @discardableResult
    public mutating func remove(_ name: String, fromEverySpaceIn account: String) -> Int {
        var removed = 0
        for url in spaces.keys where spaces[url]?.account == account && spaces[url]?.records[name] != nil {
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

    public func records(
        inSpaceOf peer: ParticipantID, forMe pairs: Pairs, as account: String
    ) -> [(name: String, record: Record)] {
        theirs(peer, in: pairs, as: account).flatMap { space in
            space.order.compactMap { name in space.records[name].map { (name, $0) } }
        }
    }

    public func ownSpaces(in pairs: Pairs, as account: String) -> [(peer: ParticipantID, space: Space)] {
        spaces.values.compactMap { space in
            guard space.account == account, let hint = space.hint, let peer = pairs.peer(for: hint) else { return nil }
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
    public mutating func put(
        _ packet: SyncPacket, to peer: ParticipantID, in pairs: Pairs, as account: String, at now: Date
    ) throws {
        let fields = PacketWire.fields(of: packet)
        let weight = MailboxRules.weigh(fields)
        guard weight <= MailboxRules.recordByteCeiling else {
            throw MailboxError.recordTooLarge(bytes: weight, ceiling: MailboxRules.recordByteCeiling)
        }
        try write(packet.id.rawValue.uuidString, fields, to: peer, in: pairs, as: account, at: now)
        notePacket(packet.id)
    }

    public mutating func ring(_ peer: ParticipantID, in pairs: Pairs, as account: String, at now: Date) throws {
        try write(PairWire.ringRecord, [PairWire.ring: .string(PairWire.ringValue())], to: peer, in: pairs, as: account, at: now)
    }

    public mutating func fetch(
        from peer: ParticipantID, for tags: Set<RecipientTag>, in pairs: Pairs, as account: String
    ) -> [SyncPacket] {
        let found = records(inSpaceOf: peer, forMe: pairs, as: account)
        let held = Set(found.map(\.name))
        if reads(peer, in: pairs, as: account), let url = mine(for: peer, in: pairs, as: account) {
            for name in spaces[url]?.order ?? [] {
                guard let packet = PairWire.packet(fromReceiptName: name), !held.contains(packet.rawValue.uuidString)
                else { continue }
                spaces[url]?.records[name] = nil
                spaces[url]?.order.removeAll { $0 == name }
            }
        }
        let mine = mine(for: peer, in: pairs, as: account).flatMap { spaces[$0] }
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
        _ id: PacketID, from peer: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs, as account: String,
        at now: Date
    ) throws {
        try write(
            PairWire.receiptName(for: id), PacketWire.receiptFields(receipt), to: peer, in: pairs, as: account, at: now)
    }

    public func sentPackets(in pairs: Pairs, as account: String) -> [PacketID: SentPacket] {
        var sent: [PacketID: SentPacket] = [:]
        for (peer, space) in ownSpaces(in: pairs, as: account) {
            let answers = Dictionary(
                records(inSpaceOf: peer, forMe: pairs, as: account).map { ($0.name, $0.record) },
                uniquingKeysWith: { a, _ in a })
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

    public mutating func withdraw(_ id: PacketID, as account: String) {
        remove(id.rawValue.uuidString, fromEverySpaceIn: account)
        packetOrder.removeAll { $0 == id }
    }

    // MARK: Photos, one copy in each recipient's space, sealed for that pair

    public mutating func upload(_ copies: PhotoCopies, in pairs: Pairs, as account: String, at now: Date) throws {
        for (peer, copy) in copies.copies {
            try write(copy.name.recordName, AttachmentWire.fields(of: copy), to: peer, in: pairs, as: account, at: now)
        }
    }

    public func download(_ copy: PhotoCopyName, from sender: ParticipantID, in pairs: Pairs, as account: String) -> Data? {
        records(inSpaceOf: sender, forMe: pairs, as: account)
            .first { $0.name == copy.recordName }
            .flatMap { AttachmentWire.sealedCopy(from: $0.record.fields) }
    }

    public mutating func acknowledge(
        copy: PhotoCopyName, from sender: ParticipantID, with receipt: SealedReceipt, in pairs: Pairs,
        as account: String, at now: Date
    ) throws {
        try write(copy.receiptName, PacketWire.receiptFields(receipt), to: sender, in: pairs, as: account, at: now)
    }

    public func storedCopies(in pairs: Pairs, as account: String) -> [StoredPhotoCopy] {
        var found: [StoredPhotoCopy] = []
        for (peer, space) in ownSpaces(in: pairs, as: account) {
            let answers = Dictionary(
                records(inSpaceOf: peer, forMe: pairs, as: account).map { ($0.name, $0.record) },
                uniquingKeysWith: { first, _ in first })
            for recordName in space.order {
                guard let name = PhotoCopyName(recordName: recordName), let record = space.records[recordName] else {
                    continue
                }
                found.append(
                    AttachmentWire.stored(
                        name, fields: record.fields, to: peer, storedAt: record.storedAt, modifiedAt: record.modifiedAt,
                        answeredBy: answers[name.receiptName].map { (fields: $0.fields, modifiedAt: $0.modifiedAt) }))
            }
        }
        return found
    }

    public mutating func delete(copies: Set<PhotoCopyName>, as account: String) {
        for copy in copies { remove(copy.recordName, fromEverySpaceIn: account) }
    }
}

extension LocalPairStore {
    private func counterpart(of space: Space) -> Space? {
        guard let hint = space.hint else { return nil }
        return spaces.values.first { $0.hint == hint && $0.account != space.account }
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

    public var everyStoredCopy: [StoredPhotoCopy] {
        var found: [StoredPhotoCopy] = []
        for space in spaces.values {
            let other = counterpart(of: space)
            for recordName in space.order {
                guard let name = PhotoCopyName(recordName: recordName), let record = space.records[recordName] else {
                    continue
                }
                found.append(
                    AttachmentWire.stored(
                        name, fields: record.fields, to: other?.owner ?? space.owner, storedAt: record.storedAt,
                        modifiedAt: record.modifiedAt,
                        answeredBy: other?.records[name.receiptName].map { (fields: $0.fields, modifiedAt: $0.modifiedAt) }))
            }
        }
        return found
    }
}
