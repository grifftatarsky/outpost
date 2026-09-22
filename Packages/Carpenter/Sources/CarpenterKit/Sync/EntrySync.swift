import Foundation

public protocol EntrySync: Sendable {
    func send(_ records: DeviceRecords, from device: DeviceID) async throws -> DeviceRecordsSaved

    func ownRecords(of device: DeviceID) async throws -> [SealedSiblingFeed]

    func onIncoming(_ handler: @escaping @Sendable (SealedSiblingFeed, DeviceID) async -> Void) async

    func start() async throws

    func refresh() async throws

    func forgetOwnContribution() async throws
}

extension EntrySync {
    public func send(_ feed: SealedSiblingFeed, from device: DeviceID) async throws {
        _ = try await send(DeviceRecords(summary: feed, entries: feed), from: device)
    }
}

public enum DeviceRecordKind: String, Sendable, CaseIterable {
    case summary = "place"
    case entries = "feed"

    public func name(for device: DeviceID) -> String {
        rawValue + "-" + device.rawValue.map { String(format: "%02x", $0) }.joined()
    }

    public static func parse(_ name: String) -> (kind: DeviceRecordKind, device: DeviceID)? {
        for kind in allCases where name.hasPrefix(kind.rawValue + "-") {
            let digits = Array(name.dropFirst(kind.rawValue.count + 1))
            guard !digits.isEmpty, digits.count % 2 == 0 else { return nil }
            var bytes = Data()
            for pair in stride(from: 0, to: digits.count, by: 2) {
                guard let byte = UInt8(String(digits[pair...pair + 1]), radix: 16) else { return nil }
                bytes.append(byte)
            }
            return (kind, DeviceID(rawValue: bytes))
        }
        return nil
    }
}

public enum EntrySyncRules {
    public static let documentedRecordCeiling = 1_000_000
}

public actor InMemoryEntrySync: EntrySync {
    public actor Relay {
        private var members: [UUID: InMemoryEntrySync] = [:]
        private var records: [String: Record] = [:]
        private var order: [String] = []
        private var refusedKinds: Set<DeviceRecordKind> = []
        private(set) var unreachable = false
        private(set) var unreadable = false

        public struct Unreachable: Error {}

        struct Record: Sendable {
            let bytes: Data
            let device: DeviceID
            let kind: DeviceRecordKind
            let version: Int
        }

        enum Written: Sendable {
            case saved(version: Int)
            case conflict(Record)
            case refused
        }

        private let announces: Bool

        public init(announces: Bool = true) {
            self.announces = announces
        }

        public func refuse(_ kinds: Set<DeviceRecordKind>) {
            refusedKinds = kinds
        }

        public func goOffline(_ offline: Bool) {
            unreachable = offline
        }

        public func failReads(_ failing: Bool) {
            unreadable = failing
        }

        func join(_ id: UUID, _ member: InMemoryEntrySync) {
            members[id] = member
        }

        func store(
            _ bytes: Data, kind: DeviceRecordKind, device: DeviceID, over version: Int?, from sender: UUID
        ) async -> Written {
            let name = kind.name(for: device)
            if let current = records[name], current.version != version { return .conflict(current) }
            guard !refusedKinds.contains(kind), bytes.count <= EntrySyncRules.documentedRecordCeiling
            else { return .refused }

            let record = Record(
                bytes: bytes, device: device, kind: kind, version: (records[name]?.version ?? 0) + 1)
            records[name] = record
            order.removeAll { $0 == name }
            order.append(name)
            guard announces else { return .saved(version: record.version) }

            for (id, member) in members where id != sender {
                await member.deliver(record)
            }
            return .saved(version: record.version)
        }

        func withdraw(_ device: DeviceID) {
            for kind in DeviceRecordKind.allCases {
                records[kind.name(for: device)] = nil
                order.removeAll { $0 == kind.name(for: device) }
            }
        }

        func everything() -> [Record] {
            order.compactMap { records[$0] }
        }

        func records(of device: DeviceID) -> [Record] {
            DeviceRecordKind.allCases.compactMap { records[$0.name(for: device)] }
        }

        public func bytesStored(of kind: DeviceRecordKind, for device: DeviceID) -> Int? {
            records[kind.name(for: device)]?.bytes.count
        }
    }

    private let id = UUID()
    private let relay: Relay
    private var handler: (@Sendable (SealedSiblingFeed, DeviceID) async -> Void)?
    private var known: [String: Int] = [:]
    private var devicesSentFor: Set<DeviceID> = []

    public private(set) var sent: [SealedSiblingFeed] = []

    public init(relay: Relay) {
        self.relay = relay
    }

    public func start() async throws {
        await relay.join(id, self)
    }

    public func onIncoming(_ handler: @escaping @Sendable (SealedSiblingFeed, DeviceID) async -> Void)
        async
    {
        self.handler = handler
    }

    fileprivate func deliver(_ record: Relay.Record) async {
        guard let sealed = try? JSONDecoder().decode(SealedSiblingFeed.self, from: record.bytes)
        else { return }
        await handler?(sealed, record.device)
    }

    public func send(_ records: DeviceRecords, from device: DeviceID) async throws -> DeviceRecordsSaved {
        if await relay.unreachable { throw Relay.Unreachable() }
        if let entries = records.entries { sent.append(entries) }
        devicesSentFor.insert(device)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var saved: [DeviceRecordKind: Bool] = [:]
        let writing = [(DeviceRecordKind.summary, records.summary)]
            + (records.entries.map { [(DeviceRecordKind.entries, $0)] } ?? [])
        for (kind, sealed) in writing {
            let bytes = try encoder.encode(sealed)
            let name = kind.name(for: device)
            var attempt = 0
            while attempt < 2 {
                attempt += 1
                switch await relay.store(bytes, kind: kind, device: device, over: known[name], from: id) {
                case .saved(let version):
                    known[name] = version
                    saved[kind] = true
                    attempt = 2
                case .conflict(let server):
                    known[name] = server.version
                    await deliver(server)
                case .refused:
                    saved[kind] = false
                    attempt = 2
                }
            }
        }
        return DeviceRecordsSaved(summary: saved[.summary] ?? false, entries: saved[.entries] ?? false)
    }

    public func ownRecords(of device: DeviceID) async throws -> [SealedSiblingFeed] {
        let offline = await relay.unreachable
        let failing = await relay.unreadable
        if offline || failing { throw Relay.Unreachable() }
        var found: [SealedSiblingFeed] = []
        for record in await relay.records(of: device) {
            known[record.kind.name(for: device)] = record.version
            if let sealed = try? JSONDecoder().decode(SealedSiblingFeed.self, from: record.bytes) {
                found.append(sealed)
            }
        }
        return found
    }

    public func refresh() async throws {
        let offline = await relay.unreachable
        let failing = await relay.unreadable
        if offline || failing { throw Relay.Unreachable() }
        for record in await relay.everything() {
            await deliver(record)
        }
    }

    public func forgetOwnContribution() async throws {
        sent = []
        for device in devicesSentFor { await relay.withdraw(device) }
    }
}
