import CarpenterKit
import CloudKit
import Foundation
import OSLog

public actor CloudKitEntrySync: EntrySync, AccountRegistry {
    private static let zoneName = "SiblingFeeds"
    private static let recordType = PushChannel.deviceFeed.recordType
    private static let payloadKey = "feed"

    private let container: CKContainer
    private let device: DeviceID
    private let stateStore: any DocumentStore

    private var engine: CKSyncEngine?
    private var delegate: Delegate?
    private var handler: (@Sendable (SiblingRecord) async -> Void)?
    private var pending: [CKRecord.ID: Data] = [:]

    private var arrivals: [SiblingRecord] = []
    private var delivering: Task<Void, Never>?
    @TaskLocal private static var isDelivering = false

    private var starting: Task<Void, any Error>?

    private var known: [CKRecord.ID: CKRecord] = [:]

    public init(container: CKContainer, device: DeviceID, stateStore: any DocumentStore) {
        self.container = container
        self.device = device
        self.stateStore = stateStore
    }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }

    private func recordID(for name: SiblingRecord.Name) -> CKRecord.ID {
        CKRecord.ID(recordName: name.recordName, zoneID: zoneID)
    }

    // MARK: EntrySync

    public func start() async throws {
        if engine != nil { return }
        // reentrancy considered: the start is held as a task and a second caller awaits it.
        if let starting { return try await starting.value }

        let task = Task { try await bringUp() }
        starting = task
        defer { starting = nil }
        try await task.value
    }

    private func bringUp() async throws {
        let delegate = Delegate(owner: self)
        self.delegate = delegate

        let saved = try? await stateStore.load(CKSyncEngine.State.Serialization.self)

        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: saved,
            delegate: delegate
        )
        configuration.automaticallySync = false

        configuration.subscriptionID = await subscribeForPushes()

        let engine = CKSyncEngine(configuration)
        self.engine = engine

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        let state = recordID(for: SiblingRecord.Name(writer: device, kind: .state))
        do {
            known[state] = try await container.privateCloudDatabase.record(for: state)
        } catch let error as CKError where error.code == .unknownItem {
            known[state] = nil
        } catch {
            Diagnostics.sync.error(
                "device sync: could not read this device's record: \(String(describing: error), privacy: .public)")
        }

        await subscribeForPushes()
        await reportSubscription()

        Diagnostics.sync.notice("device sync engine started")
    }

    private static let subscriptionID = PushChannel.deviceFeed.subscriptionID

    private func reportSubscription() async {
        do {
            let all = try await container.privateCloudDatabase.allSubscriptions()
            for subscription in all {
                let info = subscription.notificationInfo
                Diagnostics.sync.notice(
                    """
                    device sync: subscription \(subscription.subscriptionID, privacy: .public) \
                    badge=\(info?.shouldBadge == true, privacy: .public) \
                    contentAvailable=\(info?.shouldSendContentAvailable == true, privacy: .public)
                    """)
            }
        } catch {
            Diagnostics.sync.error(
                "device sync: could not read subscriptions: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    private func subscribeForPushes() async -> CKSubscription.ID? {
        let subscription = PushChannel.deviceFeed.subscription()

        do {
            let stale = ((try? await container.privateCloudDatabase.allSubscriptions()) ?? [])
                .map(\.subscriptionID)
                .filter { $0 != Self.subscriptionID }

            _ = try await container.privateCloudDatabase.modifySubscriptions(
                saving: [subscription], deleting: stale)

            if !stale.isEmpty {
                Diagnostics.sync.notice(
                    "device sync: removed \(stale.count, privacy: .public) silent subscription(s)")
            }
            Diagnostics.sync.notice("device sync: subscribed for priority pushes")
            return Self.subscriptionID
        } catch {
            Diagnostics.sync.error(
                "device sync: could not subscribe, falling back to the engine's own: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func onIncoming(_ handler: @escaping @Sendable (SiblingRecord) async -> Void) async {
        self.handler = handler
    }

    public func send(_ records: [SiblingRecord], deleting: [SiblingRecord.Name]) async throws {
        try await start()
        guard let engine else { return }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for record in records {
            let id = recordID(for: record.name)
            pending[id] = record.sealed.ciphertext
            changes.append(.saveRecord(id))
        }
        for name in deleting {
            let id = recordID(for: name)
            pending[id] = nil
            changes.append(.deleteRecord(id))
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
        Diagnostics.sync.notice(
            "device sync: staged \(records.count, privacy: .public) record(s), \(records.reduce(0) { $0 + $1.sealed.ciphertext.count }, privacy: .public) sealed bytes, and \(deleting.count, privacy: .public) deletion(s)")

        do {
            try await engine.sendChanges()
        } catch let error as CKError where Self.isOnlyConflicts(error) {
            Diagnostics.sync.notice("device sync: writing again over the server's copy")
            try await engine.sendChanges()
        }
    }

    static func isOnlyConflicts(_ error: CKError) -> Bool {
        guard error.code == .partialFailure else { return error.code == .serverRecordChanged }
        let partials = error.partialErrorsByItemID?.values.map { ($0 as? CKError)?.code } ?? []
        return !partials.isEmpty && partials.allSatisfy { $0 == .serverRecordChanged }
    }

    public func refresh() async throws {
        try await start()
        guard let engine else { return }

        let started = Date()
        Diagnostics.sync.notice(
            "device sync: fetching; engine flagged \(engine.state.zoneIDsWithUnfetchedServerChanges.count, privacy: .public) zone(s) as pending")

        try await engine.fetchChanges()
        if !Self.isDelivering, let delivering { await delivering.value }

        Diagnostics.sync.notice(
            "device sync: fetch took \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)ms")
    }

    public func occupancy() async -> AccountOccupancy {
        do {
            let batch = try await container.privateCloudDatabase.recordZoneChanges(
                inZoneWith: zoneID, since: nil, desiredKeys: [], resultsLimit: 1)
            return batch.modificationResultsByID.isEmpty ? .empty : .occupied
        } catch {
            let occupancy = Self.occupancy(for: error)
            Diagnostics.sync.notice(
                "account check: \(String(describing: occupancy), privacy: .public) — \(String(describing: error), privacy: .public)"
            )
            return occupancy
        }
    }

    static func occupancy(for error: any Error) -> AccountOccupancy {
        guard let ckError = error as? CKError else { return .undetermined }

        if ckError.code == .partialFailure {
            let partials = ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError }
            guard let partials, !partials.isEmpty else { return .undetermined }
            if partials.contains(where: { $0.code == .zoneNotFound || $0.code == .userDeletedZone }) {
                return .empty
            }
            return partials.map { occupancy(for: $0) }.contains(.offline) ? .offline : .undetermined
        }

        switch ckError.code {
        case .zoneNotFound, .userDeletedZone:
            return .empty

        case .networkUnavailable, .networkFailure, .notAuthenticated, .managedAccountRestricted:
            return .offline

        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable,
            .internalError, .serverResponseLost, .operationCancelled:
            return .undetermined

        case _:
            return .undetermined
        }
    }

    public func eraseSharedState() async throws {
        _ = try await container.privateCloudDatabase.modifyRecordZones(
            saving: [], deleting: [zoneID])
        engine = nil
        delegate = nil
        known = [:]
        pending = [:]
        try? await stateStore.clear()
        Diagnostics.sync.notice("device sync: erased every feed on this account")
    }

    public func forgetOwnContribution() async throws {
        try await start()
        guard let engine else { return }

        var mine: [CKRecord.ID] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let batch = try await container.privateCloudDatabase.recordZoneChanges(
                inZoneWith: zoneID, since: token, desiredKeys: [])
            mine += batch.modificationResultsByID.keys.filter {
                SiblingRecord.Name(recordName: $0.recordName)?.writer == device
            }
            token = batch.changeToken
            more = batch.moreComing
        }
        for id in mine { pending[id] = nil }
        engine.state.add(pendingRecordZoneChanges: mine.map { .deleteRecord($0) })
        try await engine.sendChanges()
        Diagnostics.sync.notice(
            "device sync: withdrew this device's \(mine.count, privacy: .public) record(s)")
    }

    // MARK: Engine callbacks

    fileprivate func persist(_ serialization: CKSyncEngine.State.Serialization) async {
        try? await stateStore.save(serialization)
    }

    fileprivate func batch(
        _ context: CKSyncEngine.SendChangesContext, _ engine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = engine.state.pendingRecordZoneChanges
        guard !changes.isEmpty else {
            Diagnostics.sync.notice("device sync: asked for a batch with nothing staged")
            return nil
        }

        let payloads = pending
        let templates = known

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            guard let payload = payloads[id] else { return nil }
            let record = templates[id] ?? CKRecord(recordType: Self.recordType, recordID: id)
            record[Self.payloadKey] = payload as NSData
            return record
        }
    }

    fileprivate func saved(_ records: [CKRecord], deleted: [CKRecord.ID]) {
        for record in records {
            known[record.recordID] = record
            pending[record.recordID] = nil
        }
        for id in deleted { known[id] = nil }
    }

    fileprivate func resolve(_ record: CKRecord) {
        known[record.recordID] = record
        Diagnostics.sync.notice("device sync: adopted the server's copy after a conflict")
    }

    fileprivate func received(_ records: [CKRecord]) {
        for record in records {
            guard let name = SiblingRecord.Name(recordName: record.recordID.recordName) else {
                Diagnostics.sync.error("device sync: a sibling record's name named no device")
                continue
            }
            guard name.writer != device, let data = record[Self.payloadKey] as? Data else { continue }
            arrivals.append(SiblingRecord(name: name, sealed: SealedSiblingFeed(ciphertext: data)))
        }
        guard delivering == nil, !arrivals.isEmpty else { return }
        delivering = Task.detached { [weak self] in
            await self?.deliver()
        }
    }

    private func deliver() async {
        while !arrivals.isEmpty {
            let record = arrivals.removeFirst()
            await Self.$isDelivering.withValue(true) { await handler?(record) }
        }
        // reentrancy considered: the loop checks for arrivals after every await, and nothing suspends between that check and this line.
        delivering = nil
    }

    private final class Delegate: CKSyncEngineDelegate, @unchecked Sendable {
        private let owner: CloudKitEntrySync

        init(owner: CloudKitEntrySync) {
            self.owner = owner
        }

        func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
            switch event {
            case .stateUpdate(let update):
                await owner.persist(update.stateSerialization)

            case .fetchedRecordZoneChanges(let changes):
                Diagnostics.sync.notice(
                    "device sync: \(changes.modifications.count, privacy: .public) record(s) arrived")
                await owner.received(changes.modifications.map(\.record))

            case .sentRecordZoneChanges(let sent):
                Diagnostics.sync.notice(
                    "device sync: sent \(sent.savedRecords.count, privacy: .public) record(s), \(sent.failedRecordSaves.count, privacy: .public) failed")
                await owner.saved(sent.savedRecords, deleted: sent.deletedRecordIDs)

                for failure in sent.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged,
                        let server = failure.error.serverRecord
                    {
                        await owner.resolve(server)

                        syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                    } else {
                        Diagnostics.sync.error(
                            "device sync: save failed: \(String(describing: failure.error), privacy: .public)")
                    }
                }

            case .fetchedDatabaseChanges(let changes):
                Diagnostics.sync.notice(
                    "device sync: database says \(changes.modifications.count, privacy: .public) zone(s) changed")

            case .didFetchRecordZoneChanges(let done):
                if let error = done.error {
                    Diagnostics.sync.error(
                        "device sync: fetch failed: \(String(describing: error), privacy: .public)")
                }

            case .willFetchChanges:
                Diagnostics.sync.notice("device sync: fetching…")

            case .didFetchChanges:
                Diagnostics.sync.notice("device sync: fetch finished")

            case .willSendChanges, .didSendChanges, .accountChange, .sentDatabaseChanges,
                .willFetchRecordZoneChanges:
                break

            @unknown default:
                break
            }
        }

        func nextRecordZoneChangeBatch(
            _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
        ) async -> CKSyncEngine.RecordZoneChangeBatch? {
            await owner.batch(context, syncEngine)
        }
    }
}
