import CarpenterKit
import Foundation

public actor InMemoryEntrySync: EntrySync {
    public actor Relay {
        public enum HandOver: Sendable {
            case always
            case once
        }

        public struct Refused: Error {}

        private var members: [(id: UUID, member: InMemoryEntrySync)] = []
        private var records: [String: Data] = [:]
        private var written: [DeviceID: Int] = [:]
        private var created: [String: Date] = [:]
        private var modified: [String: Date] = [:]
        private var serverNow = Date(timeIntervalSince1970: 1_900_000_000)
        private var handedOver: [String: [String: Date]] = [:]
        private var sendsToFail: [(storing: Int, silently: Bool)] = []
        private var refreshesToFail = 0

        private let announces: Bool
        private let clock: (any Clock)?
        private let handsOver: HandOver

        public init(announces: Bool = true, clock: (any Clock)? = nil, handsOver: HandOver = .always) {
            self.announces = announces
            self.clock = clock
            self.handsOver = handsOver
            if let clock { serverNow = clock.now.addingTimeInterval(-1) }
        }

        public func failNextSend(storing count: Int = 0, silently: Bool = false) {
            sendsToFail.append((count, silently))
        }

        public func failNextRefresh() { refreshesToFail += 1 }

        public var failuresPending: Int { sendsToFail.count + refreshesToFail }

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
            stamp(name.recordName)
        }

        public func rewrite(_ name: SiblingRecord.Name, _ sealed: SealedSiblingFeed) throws {
            guard records[name.recordName] != nil else { return }
            try place(name, sealed)
        }

        public func remove(_ name: SiblingRecord.Name) {
            forget(name.recordName)
        }

        public func created(_ name: SiblingRecord.Name) -> Date? { created[name.recordName] }

        public func stamps() -> [String] {
            records.keys.sorted().map { "\($0) \(modified[$0]?.timeIntervalSince1970 ?? 0)" }
        }

        public func sealed(_ name: SiblingRecord.Name) -> SealedSiblingFeed? {
            records[name.recordName].flatMap { try? JSONDecoder().decode(SealedSiblingFeed.self, from: $0) }
        }

        private func stamp(_ key: String) {
            if let clock {
                serverNow = max(serverNow.addingTimeInterval(0.001), clock.now)
            } else {
                serverNow += 1
            }
            if created[key] == nil { created[key] = serverNow }
            modified[key] = serverNow
        }

        private func forget(_ key: String) {
            records[key] = nil
            created[key] = nil
            modified[key] = nil
        }

        private func times(_ key: String) -> (created: Date?, modified: Date?) {
            (created[key], modified[key])
        }

        func join(_ id: UUID, _ member: InMemoryEntrySync) {
            members.removeAll { $0.id == id }
            members.append((id, member))
        }

        func store(
            _ stored: [(name: SiblingRecord.Name, bytes: Data)], deleting: [SiblingRecord.Name], from sender: UUID
        ) async throws -> [SiblingRecord.Name: Date] {
            var stored = stored
            var refused = false
            if !sendsToFail.isEmpty {
                let failure = sendsToFail.removeFirst()
                stored = Array(stored.prefix(failure.storing))
                refused = !failure.silently
            }
            if !refused { for name in deleting { forget(name.recordName) } }
            var firstStored: [SiblingRecord.Name: Date] = [:]
            for record in stored {
                let key = record.name.recordName
                if case .authority = record.name.kind, records[key] != nil {
                    firstStored[record.name] = created[key]
                    continue
                }
                records[key] = record.bytes
                written[record.name.writer, default: 0] += record.bytes.count
                stamp(key)
                firstStored[record.name] = created[key]
            }
            if refused { throw Refused() }
            guard announces else { return firstStored }

            for (id, member) in members where id != sender {
                for record in stored {
                    let (created, modified) = times(record.name.recordName)
                    await member.deliver(record.name, record.bytes, created: created, modified: modified)
                }
            }
            return firstStored
        }

        func withdraw(_ writers: Set<DeviceID>) {
            for key in records.keys {
                guard let name = SiblingRecord.Name(recordName: key), writers.contains(name.writer) else { continue }
                forget(key)
            }
        }

        func everything(exceptFrom writers: Set<DeviceID>, handedTo reader: String?) throws
            -> [(name: SiblingRecord.Name, bytes: Data, created: Date?, modified: Date?)]
        {
            if refreshesToFail > 0 {
                refreshesToFail -= 1
                throw Refused()
            }
            let all: [(name: SiblingRecord.Name, bytes: Data, created: Date?, modified: Date?)] =
                records.sorted { $0.key < $1.key }.compactMap { key, bytes in
                    guard let name = SiblingRecord.Name(recordName: key), !writers.contains(name.writer) else {
                        return nil
                    }
                    return (name, bytes, created[key], modified[key])
                }
            guard handsOver == .once, let reader else { return all }
            var handed = handedOver[reader, default: [:]]
            let fresh = all.filter { record in
                guard let modified = record.modified else { return true }
                return handed[record.name.recordName].map { $0 < modified } ?? true
            }
            for record in fresh { handed[record.name.recordName] = record.modified }
            handedOver[reader] = handed
            return fresh
        }
    }

    private let id = UUID()
    private let relay: Relay
    private let reader: String?
    private var handler: (@Sendable (SiblingRecord) async -> Void)?
    private var writers: Set<DeviceID> = []

    public private(set) var sent: [SiblingRecord] = []
    private var isCut = false

    public func cut() { isCut = true }

    public init(relay: Relay, as reader: String? = nil) {
        self.relay = relay
        self.reader = reader
    }

    public func start() async throws {
        await relay.join(id, self)
    }

    public func onIncoming(_ handler: @escaping @Sendable (SiblingRecord) async -> Void) async {
        self.handler = handler
    }

    fileprivate func deliver(_ name: SiblingRecord.Name, _ bytes: Data, created: Date?, modified: Date?) async {
        guard !isCut, !writers.contains(name.writer),
            let sealed = try? JSONDecoder().decode(SealedSiblingFeed.self, from: bytes)
        else { return }
        await handler?(SiblingRecord(name: name, sealed: sealed, created: created, modified: modified))
    }

    @discardableResult
    public func send(_ records: [SiblingRecord], deleting: [SiblingRecord.Name]) async throws
        -> [SiblingRecord.Name: Date]
    {
        if isCut { throw Relay.Refused() }
        sent.append(contentsOf: records)
        writers.formUnion(records.map(\.name.writer))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try await relay.store(
            try records.map { ($0.name, try encoder.encode($0.sealed)) }, deleting: deleting, from: id)
    }

    public func refresh() async throws {
        if isCut { throw Relay.Refused() }
        for record in try await relay.everything(exceptFrom: writers, handedTo: reader) {
            await deliver(record.name, record.bytes, created: record.created, modified: record.modified)
        }
    }

    public func readEverything() async throws {
        if isCut { throw Relay.Refused() }
        for record in try await relay.everything(exceptFrom: writers, handedTo: nil) {
            await deliver(record.name, record.bytes, created: record.created, modified: record.modified)
        }
    }

    public func forgetOwnContribution() async throws {
        sent = []
        await relay.withdraw(writers)
    }
}
