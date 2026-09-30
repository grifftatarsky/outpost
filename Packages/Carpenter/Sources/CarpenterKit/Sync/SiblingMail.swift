import CryptoKit
import Foundation

public struct SiblingCursor: Hashable, Sendable, Codable {
    public let device: DeviceID
    public let mail: Int

    public init(device: DeviceID, mail: Int) {
        self.device = device
        self.mail = mail
    }
}

public struct ForwardedGrant: Hashable, Sendable, Codable {
    public let from: ParticipantID
    public let grant: EpochGrant
    public let storedAt: Date?

    public init(from: ParticipantID, grant: EpochGrant, storedAt: Date? = nil) {
        self.from = from
        self.grant = grant
        self.storedAt = storedAt
    }
}

public struct ForwardedAsk: Hashable, Sendable, Codable {
    public let from: ParticipantID
    public let ask: PhotoAsk

    public init(from: ParticipantID, ask: PhotoAsk) {
        self.from = from
        self.ask = ask
    }
}

public struct SiblingRecord: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case state
        case mail(Int)
        case catchUp(for: DeviceID)
        case request
        case approval(for: DeviceID)
        case authority(Data)
    }

    public struct Name: Hashable, Sendable {
        public let writer: DeviceID
        public let kind: Kind

        public init(writer: DeviceID, kind: Kind) {
            self.writer = writer
            self.kind = kind
        }

        public var recordName: String {
            switch kind {
            case .state: "feed-\(writer.rawValue.lowercaseHex)"
            case .mail(let number): "mail-\(writer.rawValue.lowercaseHex)-\(number)"
            case .catchUp(let target): "catchup-\(writer.rawValue.lowercaseHex)-\(target.rawValue.lowercaseHex)"
            case .request: "request-\(writer.rawValue.lowercaseHex)"
            case .approval(let target): "approval-\(writer.rawValue.lowercaseHex)-\(target.rawValue.lowercaseHex)"
            case .authority(let digest): "authority-\(writer.rawValue.lowercaseHex)-\(digest.lowercaseHex)"
            }
        }

        public init?(recordName: String) {
            let parts = recordName.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let writer = Data(lowercaseHex: parts[1]).map(DeviceID.init(rawValue:)) else {
                return nil
            }
            switch (parts[0], parts.count) {
            case ("feed", 2):
                self.init(writer: writer, kind: .state)
            case ("mail", 3):
                guard let number = Int(parts[2]), number > 0 else { return nil }
                self.init(writer: writer, kind: .mail(number))
            case ("catchup", 3):
                guard let target = Data(lowercaseHex: parts[2]).map(DeviceID.init(rawValue:)) else { return nil }
                self.init(writer: writer, kind: .catchUp(for: target))
            case ("request", 2):
                self.init(writer: writer, kind: .request)
            case ("approval", 3):
                guard let target = Data(lowercaseHex: parts[2]).map(DeviceID.init(rawValue:)) else { return nil }
                self.init(writer: writer, kind: .approval(for: target))
            case ("authority", 3):
                guard let digest = Data(lowercaseHex: parts[2]), digest.count == 32 else { return nil }
                self.init(writer: writer, kind: .authority(digest))
            default:
                return nil
            }
        }
    }

    public let name: Name
    public let sealed: SealedSiblingFeed
    public let created: Date?
    public let modified: Date?

    public init(name: Name, sealed: SealedSiblingFeed, created: Date? = nil, modified: Date? = nil) {
        self.name = name
        self.sealed = sealed
        self.created = created
        self.modified = modified
    }
}

public struct SiblingMail: Hashable, Sendable, Codable {
    public static let keptFor: TimeInterval = 30 * 24 * 60 * 60

    public struct Mail: Sendable {
        public let number: Int
        public let entries: [Entry]
        public let epochs: [HeldEpoch]
        public let forwarded: [ForwardedGrant]
        public let people: [IdentityPublicKeys]
        public let carriesPreferences: Bool
        public let addresses: [HeldAddress]
    }

    public struct Plan: Sendable {
        public fileprivate(set) var mail: Mail?
        public fileprivate(set) var catchUpsFor: [DeviceID] = []
        public fileprivate(set) var mailsToDelete: [Int] = []
        public fileprivate(set) var catchUpsToDelete: [DeviceID] = []
        public fileprivate(set) var through: Int
        public fileprivate(set) var recipients: [DeviceID] = []
        fileprivate var skipped: Int?
        fileprivate var sharedClock: [FeedKey: UInt64]
        fileprivate var sharedEpochs: Set<EpochMark>
        fileprivate var sharedPeople: Set<ParticipantID> = []
        fileprivate var sharedPreferences: Data?
        fileprivate var sharedAddresses: Set<AddressMark> = []
        fileprivate let now: Date

        public var deletions: [SiblingRecord.Kind] {
            mailsToDelete.map { .mail($0) } + catchUpsToDelete.map { .catchUp(for: $0) }
        }
    }

    struct EpochMark: Hashable, Sendable, Codable {
        let room: RoomID
        let epoch: EpochNumber
        let key: Data?

        init(_ held: HeldEpoch) {
            room = held.room
            epoch = held.epoch
            key = EpochSecret(material: held.material).fingerprint
        }
    }

    struct AddressMark: Hashable, Sendable, Codable {
        let owner: ParticipantID?
        let salt: Data

        init(_ held: HeldAddress) {
            owner = held.owner
            salt = held.salt.bytes
        }
    }

    struct Seen: Hashable, Sendable, Codable {
        var hasOfMine: Int?
        var at: Date
    }

    struct Sent: Hashable, Sendable, Codable {
        var through: Int
        var at: Date
    }

    private(set) var lastMail = 0
    private(set) var sharedClock: [FeedKey: UInt64] = [:]
    private(set) var sharedEpochs: Set<EpochMark> = []
    private(set) var outstanding: [Int: Date] = [:]
    private(set) var deletedThrough = 0
    private(set) var collected: [DeviceID: Int] = [:]
    private(set) var takenAbove: [DeviceID: Set<Int>] = [:]
    private(set) var catchUps: [DeviceID: Sent] = [:]
    private(set) var siblings: [DeviceID: Seen] = [:]
    public private(set) var lastState: Data?
    private(set) var forwards: [ForwardedGrant] = []
    private(set) var sharedPeople: Set<ParticipantID> = []
    private(set) var sharedPreferences: Data?
    private(set) var sharedAddresses: Set<AddressMark> = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case lastMail, sharedClock, sharedEpochs, outstanding, deletedThrough, collected, takenAbove
        case catchUps, siblings, lastState, forwards, sharedPeople, sharedPreferences, sharedAddresses
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastMail = try container.decodeIfPresent(Int.self, forKey: .lastMail) ?? 0
        sharedClock = try container.decodeIfPresent([FeedKey: UInt64].self, forKey: .sharedClock) ?? [:]
        sharedEpochs = try container.decodeIfPresent(Set<EpochMark>.self, forKey: .sharedEpochs) ?? []
        outstanding = try container.decodeIfPresent([Int: Date].self, forKey: .outstanding) ?? [:]
        deletedThrough = try container.decodeIfPresent(Int.self, forKey: .deletedThrough) ?? 0
        collected = try container.decodeIfPresent([DeviceID: Int].self, forKey: .collected) ?? [:]
        takenAbove = try container.decodeIfPresent([DeviceID: Set<Int>].self, forKey: .takenAbove) ?? [:]
        catchUps = try container.decodeIfPresent([DeviceID: Sent].self, forKey: .catchUps) ?? [:]
        siblings = try container.decodeIfPresent([DeviceID: Seen].self, forKey: .siblings) ?? [:]
        lastState = try container.decodeIfPresent(Data.self, forKey: .lastState)
        forwards = try container.decodeIfPresent([ForwardedGrant].self, forKey: .forwards) ?? []
        sharedPeople = try container.decodeIfPresent(Set<ParticipantID>.self, forKey: .sharedPeople) ?? []
        sharedPreferences = try container.decodeIfPresent(Data.self, forKey: .sharedPreferences)
        sharedAddresses = try container.decodeIfPresent(Set<AddressMark>.self, forKey: .sharedAddresses) ?? []
    }

    public mutating func shared(_ people: [IdentityPublicKeys]) {
        sharedPeople.formUnion(people.map(\.participantID))
    }

    public mutating func forward(_ grant: ForwardedGrant) {
        guard !forwards.contains(grant) else { return }
        forwards.append(grant)
    }

    // MARK: What this device has taken

    public var cursors: [SiblingCursor] {
        collected.map { SiblingCursor(device: $0.key, mail: $0.value) }
            .sorted { $0.device.rawValue.lexicographicallyPrecedes($1.device.rawValue) }
    }

    public mutating func noteState(
        from sibling: DeviceID, cursors: [SiblingCursor], at: Date, me: DeviceID
    ) {
        guard sibling != me else { return }
        siblings[sibling] = Seen(hasOfMine: cursors.first { $0.device == me }?.mail, at: at)
    }

    public mutating func took(mail number: Int, from sibling: DeviceID) {
        let cursor = collected[sibling] ?? 0
        var above = takenAbove[sibling] ?? []
        if number > cursor { above.insert(number) }
        advance(sibling, from: cursor, above: above)
    }

    public mutating func took(catchUpThrough through: Int, from sibling: DeviceID) {
        let cursor = Swift.max(collected[sibling] ?? 0, through)
        advance(sibling, from: cursor, above: (takenAbove[sibling] ?? []).filter { $0 > cursor })
    }

    public mutating func shared(_ epochs: [HeldEpoch]) {
        sharedEpochs.formUnion(epochs.map(EpochMark.init))
    }

    public mutating func shared(_ addresses: [HeldAddress]) {
        sharedAddresses.formUnion(addresses.map(AddressMark.init))
    }

    private mutating func advance(_ sibling: DeviceID, from start: Int, above: Set<Int>) {
        var cursor = start
        var above = above
        while above.remove(cursor + 1) != nil { cursor += 1 }
        collected[sibling] = cursor
        takenAbove[sibling] = above.isEmpty ? nil : above
    }

    // MARK: What this device writes and deletes

    public mutating func shared(_ entries: [Entry]) {
        for entry in entries {
            let feed = FeedKey(author: entry.author, device: entry.device)
            sharedClock[feed] = Swift.max(sharedClock[feed] ?? 0, entry.seq)
        }
    }

    public func plan(
        entries all: [Entry], held: [HeldEpoch], people known: [IdentityPublicKeys] = [],
        preferences: Data? = nil, addresses kept: [HeldAddress] = [], me: DeviceID, revoked: Set<DeviceID>,
        now: Date
    ) -> Plan {
        let active = siblings.filter { id, seen in
            id != me && !revoked.contains(id) && now.timeIntervalSince(seen.at) < Self.keptFor
        }
        var plan = Plan(
            through: lastMail, sharedClock: sharedClock, sharedEpochs: sharedEpochs, now: now)
        plan.recipients = active.keys.sorted { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }

        let entries = all.filter { $0.seq > sharedClock[FeedKey(author: $0.author, device: $0.device)] ?? 0 }
        let epochs = held.filter { !sharedEpochs.contains(EpochMark($0)) }
        for entry in entries {
            let feed = FeedKey(author: entry.author, device: entry.device)
            plan.sharedClock[feed] = Swift.max(plan.sharedClock[feed] ?? 0, entry.seq)
        }
        plan.sharedEpochs.formUnion(epochs.map(EpochMark.init))

        let people = known.filter { !sharedPeople.contains($0.participantID) }
        plan.sharedPeople = Set(people.map(\.participantID))
        let preferencesChanged = preferences != nil && preferences != sharedPreferences
        plan.sharedPreferences = preferences ?? sharedPreferences
        let addresses = kept.filter { !sharedAddresses.contains(AddressMark($0)) }
        plan.sharedAddresses = Set(addresses.map(AddressMark.init))

        if !entries.isEmpty || !epochs.isEmpty || !people.isEmpty || preferencesChanged || !addresses.isEmpty
            || (!forwards.isEmpty && !active.isEmpty)
        {
            plan.through = lastMail + 1
            if active.isEmpty {
                plan.skipped = plan.through
            } else {
                plan.mail = Mail(
                    number: plan.through, entries: entries, epochs: epochs, forwarded: forwards, people: people,
                    carriesPreferences: preferencesChanged, addresses: addresses)
            }
        }

        for (number, writtenAt) in outstanding.sorted(by: { $0.key < $1.key }) {
            let everyoneHasIt = active.values.allSatisfy { ($0.hasOfMine ?? 0) >= number }
            guard everyoneHasIt || now.timeIntervalSince(writtenAt) >= Self.keptFor else { break }
            plan.mailsToDelete.append(number)
        }
        let gone = Swift.max(deletedThrough, plan.mailsToDelete.max() ?? 0, plan.skipped ?? 0)

        for (id, seen) in active where catchUps[id] == nil {
            if (seen.hasOfMine ?? -1) < gone || seen.hasOfMine == nil {
                plan.catchUpsFor.append(id)
            }
        }
        for (id, sent) in catchUps {
            let taken = (siblings[id]?.hasOfMine ?? -1) >= sent.through
            if taken || active[id] == nil || now.timeIntervalSince(sent.at) >= Self.keptFor {
                plan.catchUpsToDelete.append(id)
            }
        }
        plan.catchUpsFor.sort { $0.rawValue.lexicographicallyPrecedes($1.rawValue) }
        return plan
    }

    public mutating func commit(_ plan: Plan, stateWritten digest: Data?) {
        lastMail = Swift.max(lastMail, plan.through)
        if let mail = plan.mail {
            outstanding[mail.number] = plan.now
            forwards.removeAll { mail.forwarded.contains($0) }
        }
        if let skipped = plan.skipped { deletedThrough = Swift.max(deletedThrough, skipped) }
        for (feed, seq) in plan.sharedClock { sharedClock[feed] = Swift.max(sharedClock[feed] ?? 0, seq) }
        sharedEpochs.formUnion(plan.sharedEpochs)
        sharedPeople.formUnion(plan.sharedPeople)
        sharedPreferences = plan.sharedPreferences
        sharedAddresses.formUnion(plan.sharedAddresses)
        for number in plan.mailsToDelete {
            outstanding[number] = nil
            deletedThrough = Swift.max(deletedThrough, number)
        }
        for id in plan.catchUpsToDelete { catchUps[id] = nil }
        for id in plan.catchUpsFor { catchUps[id] = Sent(through: plan.through, at: plan.now) }
        if let digest { lastState = digest }
    }

    public var ownRecords: [SiblingRecord.Kind] {
        [.state] + outstanding.keys.sorted().map { .mail($0) } + catchUps.keys.map { .catchUp(for: $0) }
    }

    public static func digest(of preferences: MemberPreferences) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Data(SHA256.hash(data: try encoder.encode(preferences)))
    }

    public static func digest(of state: SiblingFeed, on day: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bucket = Int(day.timeIntervalSince1970 / (24 * 60 * 60))
        return Data(SHA256.hash(data: try encoder.encode(state) + Data("\(bucket)".utf8)))
    }
}
