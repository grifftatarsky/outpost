import Foundation

public protocol EntrySync: Sendable {
    func send(_ records: [SiblingRecord], deleting: [SiblingRecord.Name]) async throws

    func onIncoming(_ handler: @escaping @Sendable (SiblingRecord) async -> Void) async

    func start() async throws

    func refresh() async throws

    func forgetOwnContribution() async throws
}

public actor InMemoryEntrySync: EntrySync {
    public actor Relay {
        private var members: [UUID: InMemoryEntrySync] = [:]
        private var records: [String: Data] = [:]
        private var written: [DeviceID: Int] = [:]

        private let announces: Bool

        public init(announces: Bool = true) {
            self.announces = announces
        }

        public func bytesWritten(by device: DeviceID) -> Int { written[device, default: 0] }

        public func bytesHeld(from device: DeviceID) -> Int {
            records.filter { SiblingRecord.Name(recordName: $0.key)?.writer == device }
                .reduce(0) { $0 + $1.value.count }
        }

        public func names(from device: DeviceID) -> [SiblingRecord.Name] {
            records.keys.compactMap(SiblingRecord.Name.init(recordName:)).filter { $0.writer == device }
        }

        public func place(_ name: SiblingRecord.Name, _ sealed: SealedSiblingFeed) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            records[name.recordName] = try encoder.encode(sealed)
        }

        func join(_ id: UUID, _ member: InMemoryEntrySync) {
            members[id] = member
        }

        func store(
            _ stored: [(name: SiblingRecord.Name, bytes: Data)], deleting: [SiblingRecord.Name], from sender: UUID
        ) async {
            for name in deleting { records[name.recordName] = nil }
            for record in stored {
                records[record.name.recordName] = record.bytes
                written[record.name.writer, default: 0] += record.bytes.count
            }
            guard announces else { return }

            for (id, member) in members where id != sender {
                for record in stored { await member.deliver(record.name, record.bytes) }
            }
        }

        func withdraw(_ writers: Set<DeviceID>) {
            records = records.filter { key, _ in
                SiblingRecord.Name(recordName: key).map { !writers.contains($0.writer) } ?? true
            }
        }

        func everything(exceptFrom writers: Set<DeviceID>) -> [(SiblingRecord.Name, Data)] {
            records.sorted { $0.key < $1.key }.compactMap { key, bytes in
                guard let name = SiblingRecord.Name(recordName: key), !writers.contains(name.writer) else {
                    return nil
                }
                return (name, bytes)
            }
        }
    }

    private let id = UUID()
    private let relay: Relay
    private var handler: (@Sendable (SiblingRecord) async -> Void)?
    private var writers: Set<DeviceID> = []

    public private(set) var sent: [SiblingRecord] = []

    public init(relay: Relay) {
        self.relay = relay
    }

    public func start() async throws {
        await relay.join(id, self)
    }

    public func onIncoming(_ handler: @escaping @Sendable (SiblingRecord) async -> Void) async {
        self.handler = handler
    }

    fileprivate func deliver(_ name: SiblingRecord.Name, _ bytes: Data) async {
        guard !writers.contains(name.writer),
            let sealed = try? JSONDecoder().decode(SealedSiblingFeed.self, from: bytes)
        else { return }
        await handler?(SiblingRecord(name: name, sealed: sealed))
    }

    public func send(_ records: [SiblingRecord], deleting: [SiblingRecord.Name]) async throws {
        sent.append(contentsOf: records)
        writers.formUnion(records.map(\.name.writer) + deleting.map(\.writer))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        await relay.store(
            try records.map { ($0.name, try encoder.encode($0.sealed)) }, deleting: deleting, from: id)
    }

    public func refresh() async throws {
        for (name, bytes) in await relay.everything(exceptFrom: writers) {
            await deliver(name, bytes)
        }
    }

    public func forgetOwnContribution() async throws {
        sent = []
        await relay.withdraw(writers)
    }
}
