import Foundation

public protocol EntrySync: Sendable {
    func send(_ feed: SealedSiblingFeed, from device: DeviceID) async throws

    func onIncoming(_ handler: @escaping @Sendable (SealedSiblingFeed, DeviceID) async -> Void) async

    func start() async throws

    func refresh() async throws

    func forgetOwnContribution() async throws
}

public actor InMemoryEntrySync: EntrySync {
    public actor Relay {
        private var members: [UUID: InMemoryEntrySync] = [:]
        private var records: [UUID: Record] = [:]

        struct Record: Sendable {
            let bytes: Data
            let device: DeviceID
        }

        private let announces: Bool

        public init(announces: Bool = true) {
            self.announces = announces
        }

        func join(_ id: UUID, _ member: InMemoryEntrySync) {
            members[id] = member
        }

        func store(_ record: Record, from sender: UUID) async {
            records[sender] = record
            guard announces else { return }

            for (id, member) in members where id != sender {
                await member.deliver(record)
            }
        }

        func withdraw(_ sender: UUID) {
            records[sender] = nil
        }

        func everything(except sender: UUID) -> [Record] {
            records.filter { $0.key != sender }.map(\.value)
        }
    }

    private let id = UUID()
    private let relay: Relay
    private var handler: (@Sendable (SealedSiblingFeed, DeviceID) async -> Void)?

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

    public func send(_ feed: SealedSiblingFeed, from device: DeviceID) async throws {
        sent.append(feed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        await relay.store(
            Relay.Record(bytes: try encoder.encode(feed), device: device), from: id)
    }

    public func refresh() async throws {
        for record in await relay.everything(except: id) {
            await deliver(record)
        }
    }

    public func forgetOwnContribution() async throws {
        sent = []
        await relay.withdraw(id)
    }
}
