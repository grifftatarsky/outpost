import CloudKit
import CarpenterKit
import Foundation

public struct CloudKitMailbox: Mailbox, MediaMailbox {
    public static let legacyZoneName = "Outbox"
    static let pairZonePrefix = "Pair-"

    let container: CKContainer
    let index: PairIndex

    public init(container: CKContainer, index: PairIndex = PairIndex()) {
        self.container = container
        self.index = index
    }

    public static func refusal(for error: any Error) -> MailboxFailure? {
        guard let error = error as? CKError else { return nil }
        switch error.code {
        case .quotaExceeded: return .noRoomInICloud
        case .notAuthenticated, .accountTemporarilyUnavailable: return .notSignedIn
        case .partialFailure:
            let nested = error.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? []
            if nested.contains(where: { $0.code == .quotaExceeded }) { return .noRoomInICloud }
            if nested.contains(where: {
                $0.code == .notAuthenticated || $0.code == .accountTemporarilyUnavailable
            }) { return .notSignedIn }
            return nil
        default: return nil
        }
    }

    public static let scannedFields: [CKRecord.FieldKey] = [
        PacketWire.packetID, PacketWire.outstanding, PacketWire.wrapTags, PacketWire.wrapValues,
        PacketWire.ciphertext, PacketWire.grantTags, PacketWire.grantValues,
        AttachmentWire.attachmentID, PairWire.hint, PairWire.ring, PairWire.receiptTag, PairWire.receiptSealed,
    ]

    // MARK: Reading what changed

    func refresh() async throws {
        try await index.refresh { try await load() }
    }

    private func load() async throws {
        let privateChanges = try await changes(in: container.privateCloudDatabase, since: await index.privateToken)
        var mine: [CKRecordZone.ID: PairIndex.Zone] = [:]
        for zone in privateChanges.changed {
            if zone.zoneName.hasPrefix(Self.pairZonePrefix) {
                mine[zone] = try await read(zone, in: container.privateCloudDatabase)
            } else if zone.zoneName == Self.legacyZoneName {
                await index.noteOldOutbox(true)
            }
        }
        if privateChanges.gone.contains(where: { $0.zoneName == Self.legacyZoneName }) { await index.noteOldOutbox(false) }
        let sharedChanges = try await changes(in: container.sharedCloudDatabase, since: await index.sharedToken)
        var theirs: [CKRecordZone.ID: PairIndex.Zone] = [:]
        var legacy: [CKRecordZone.ID: PairIndex.Zone] = [:]
        for zone in sharedChanges.changed {
            do {
                if zone.zoneName.hasPrefix(Self.pairZonePrefix) {
                    theirs[zone] = try await read(zone, in: container.sharedCloudDatabase)
                } else if zone.zoneName == Self.legacyZoneName {
                    legacy[zone] = try await read(zone, in: container.sharedCloudDatabase)
                }
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                theirs[zone] = nil
            }
        }
        await index.take(
            mine: mine, mineGone: privateChanges.gone, privateToken: privateChanges.token,
            theirs: theirs, legacy: legacy, sharedGone: sharedChanges.gone, sharedToken: sharedChanges.token)
        try await sweepDuplicates()
    }

    private func changes(in database: CKDatabase, since token: CKServerChangeToken?) async throws
        -> (changed: [CKRecordZone.ID], gone: [CKRecordZone.ID], token: CKServerChangeToken)
    {
        var token = token
        var changed: [CKRecordZone.ID] = []
        var gone: [CKRecordZone.ID] = []
        while true {
            let page = try await database.databaseChanges(since: token)
            changed += page.modifications.map(\.zoneID)
            gone += page.deletions.map(\.zoneID)
            token = page.changeToken
            if !page.moreComing { break }
        }
        return (changed, gone, token!)
    }

    func read(_ zone: CKRecordZone.ID, in database: CKDatabase) async throws -> PairIndex.Zone {
        var found = PairIndex.Zone()
        var token: CKServerChangeToken?
        while true {
            let batch = try await database.recordZoneChanges(
                inZoneWith: zone, since: token, desiredKeys: Self.scannedFields)
            for (id, result) in batch.modificationResultsByID {
                guard let record = try? result.get().record else { continue }
                if id.recordName == PairWire.infoRecord, let hint = record[PairWire.hint] as? Data {
                    found.hint = PairHint(rawValue: hint)
                }
                found.records[id.recordName] = PairIndex.Cached(record)
            }
            guard batch.moreComing else { return found }
            token = batch.changeToken
        }
    }

    private func sweepDuplicates() async throws {
        let extra = await index.duplicates()
        guard !extra.isEmpty else { return }
        _ = try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: extra)
        await index.forget(mine: extra)
        Diagnostics.sync.notice("pairs: removed \(extra.count, privacy: .public) extra space(s) made twice for one person")
    }

    func save(_ records: [CKRecord], in database: CKDatabase) async throws {
        do {
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
            for (_, outcome) in result.saveResults { _ = try outcome.get() }
        } catch {
            if let refusal = Self.refusal(for: error) { throw refusal }
            throw error
        }
    }
}

// MARK: What this device knows about the spaces it can reach

public actor PairIndex {
    struct Cached: Sendable {
        let type: String
        let fields: [String: PacketField]
        let created: Date
        let modified: Date

        init(_ record: CKRecord) {
            type = record.recordType
            var fields: [String: PacketField] = [:]
            for key in record.allKeys() {
                switch record[key] {
                case let value as String: fields[key] = .string(value)
                case let value as [Data]: fields[key] = .dataList(value)
                case let value as Data: fields[key] = .data(value)
                default: continue
                }
            }
            self.fields = fields
            created = record.creationDate ?? .distantPast
            modified = record.modificationDate ?? created
        }

        init(type: String, fields: [String: PacketField], at instant: Date) {
            self.type = type
            self.fields = fields
            created = instant
            modified = instant
        }
    }

    struct Zone: Sendable {
        var hint: PairHint?
        var records: [String: Cached] = [:]
    }

    private(set) var mine: [CKRecordZone.ID: Zone] = [:]
    private(set) var theirs: [CKRecordZone.ID: Zone] = [:]
    private(set) var legacy: [CKRecordZone.ID: Zone] = [:]
    private(set) var privateToken: CKServerChangeToken?
    private(set) var sharedToken: CKServerChangeToken?
    private(set) var links: [CKRecordZone.ID: URL] = [:]
    private var readers: [CKRecordZone.ID: String] = [:]
    private var making: [PairHint: Task<CKRecordZone.ID, any Error>] = [:]
    private(set) var account: String?
    private(set) var hasOldOutbox = false
    private var refreshedAt: Date?
    private var refreshing: Task<Void, any Error>?

    public init() {}

    func refresh(_ load: @escaping @Sendable () async throws -> Void) async throws {
        if let refreshing { return try await refreshing.value }
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 2 { return }
        let task = Task { try await load() }
        refreshing = task
        defer { refreshing = nil }
        try await task.value
        refreshedAt = Date()
    }

    func invalidate() { refreshedAt = nil }

    func take(
        mine changedMine: [CKRecordZone.ID: Zone], mineGone: [CKRecordZone.ID], privateToken: CKServerChangeToken,
        theirs changedTheirs: [CKRecordZone.ID: Zone], legacy changedLegacy: [CKRecordZone.ID: Zone],
        sharedGone: [CKRecordZone.ID], sharedToken: CKServerChangeToken
    ) {
        for zone in mineGone { dropMine(zone) }
        for (zone, found) in changedMine {
            mine[zone] = found
            readers[zone] = nil
        }
        for zone in sharedGone {
            theirs[zone] = nil
            legacy[zone] = nil
        }
        for (zone, found) in changedTheirs { theirs[zone] = found }
        for (zone, found) in changedLegacy { legacy[zone] = found }
        self.privateToken = privateToken
        self.sharedToken = sharedToken
    }

    func duplicates() -> [CKRecordZone.ID] {
        let grouped = Dictionary(grouping: mine.filter { $0.value.hint != nil }, by: { $0.value.hint! })
        return grouped.values.flatMap { zones in
            zones.map(\.key).sorted { $0.zoneName < $1.zoneName }.dropFirst()
        }
    }

    func forget(mine zones: [CKRecordZone.ID]) {
        for zone in zones { dropMine(zone) }
    }

    func zone(for hint: PairHint, making make: @escaping @Sendable () async throws -> CKRecordZone.ID) async throws
        -> CKRecordZone.ID
    {
        if let known = mineFor(hint) { return known }
        if let pending = making[hint] { return try await pending.value }
        let task = Task { try await make() }
        making[hint] = task
        defer { making[hint] = nil }
        return try await task.value
    }

    func mineFor(_ hint: PairHint) -> CKRecordZone.ID? {
        mine.filter { $0.value.hint == hint }.map(\.key).min { $0.zoneName < $1.zoneName }
    }

    func theirZone(for peer: ParticipantID, in pairs: Pairs) -> Zone? {
        let zones = theirsFor(peer, in: pairs).compactMap { theirs[$0] }
        guard !zones.isEmpty else { return nil }
        return Zone(hint: pairs.hints[peer], records: zones.reduce(into: [:]) { $0.merge($1.records) { first, _ in first } })
    }

    func myZone(for hint: PairHint) -> Zone? { mineFor(hint).flatMap { mine[$0] } }

    func theirsFor(_ peer: ParticipantID, in pairs: Pairs) -> [CKRecordZone.ID] {
        guard let hint = pairs.hints[peer] else { return [] }
        return theirs.filter { $0.value.hint == hint && pairs.reads(peer, from: $0.key.ownerName) }.map(\.key)
            .sorted { $0.zoneName < $1.zoneName }
    }

    func adopt(_ zone: CKRecordZone.ID, hint: PairHint?, link: URL?) {
        var found = mine[zone] ?? Zone()
        if let hint { found.hint = hint }
        mine[zone] = found
        if let link { links[zone] = link }
    }

    func remember(_ link: URL, for zone: CKRecordZone.ID) { links[zone] = link }

    func remember(reader: String, of zone: CKRecordZone.ID) { readers[zone] = reader }

    func known(_ zone: CKRecordZone.ID, naming reader: String?) -> URL? {
        guard reader == nil || readers[zone] == reader else { return nil }
        return links[zone]
    }

    func zone(linkedBy url: URL) -> CKRecordZone.ID? { links.first { $0.value == url }?.key }

    func remember(account: String) { self.account = account }

    func noteOldOutbox(_ present: Bool) { hasOldOutbox = present }

    func wrote(_ name: String, _ cached: Cached, in zone: CKRecordZone.ID) {
        mine[zone, default: Zone()].records[name] = cached
    }

    func removed(_ name: String, from zone: CKRecordZone.ID) { mine[zone]?.records[name] = nil }

    func dropMine(_ zone: CKRecordZone.ID) {
        mine[zone] = nil
        links[zone] = nil
        readers[zone] = nil
    }
}
