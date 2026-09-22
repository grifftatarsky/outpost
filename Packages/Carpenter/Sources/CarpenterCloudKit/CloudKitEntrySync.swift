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
    private var handler: (@Sendable (SealedSiblingFeed, DeviceID) async -> Void)?
    private var pending: [CKRecord.ID: Data] = [:]
    private var outcomes: [CKRecord.ID: Outcome] = [:]

    private enum Outcome {
        case saved
        case conflict
        case failed
    }

    private var starting: Task<Void, any Error>?

    private var known: [CKRecord.ID: CKRecord] = [:]

    public init(container: CKContainer, device: DeviceID, stateStore: any DocumentStore) {
        self.container = container
        self.device = device
        self.stateStore = stateStore
    }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }

    private func recordID(_ kind: DeviceRecordKind, for device: DeviceID) -> CKRecord.ID {
        CKRecord.ID(recordName: kind.name(for: device), zoneID: zoneID)
    }

    private func ownIDs(of device: DeviceID) -> [CKRecord.ID] {
        DeviceRecordKind.allCases.map { recordID($0, for: device) }
    }

    // MARK: EntrySync

    public func start() async throws {
        if engine != nil { return }
        // reentrancy considered
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

        do {
            _ = try await fetchOwn(of: device)
        } catch {
            Diagnostics.sync.error(
                "device sync: could not read this device's records: \(String(describing: error), privacy: .public)")
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

    public func onIncoming(_ handler: @escaping @Sendable (SealedSiblingFeed, DeviceID) async -> Void)
        async
    {
        self.handler = handler
    }

    public func send(_ records: DeviceRecords, from device: DeviceID) async throws -> DeviceRecordsSaved {
        let summaryID = recordID(.summary, for: device)
        let entriesID = recordID(.entries, for: device)
        pending[summaryID] = records.summary.ciphertext
        var writing = [summaryID]
        if let entries = records.entries {
            pending[entriesID] = entries.ciphertext
            writing.append(entriesID)
        }

        try await start()
        guard let engine else { return DeviceRecordsSaved(summary: false, entries: false) }

        var saved: Set<CKRecord.ID> = []
        for _ in 0..<2 {
            let waiting = writing.filter { !saved.contains($0) }
            guard !waiting.isEmpty else { break }
            for id in waiting { outcomes[id] = nil }
            engine.state.add(pendingRecordZoneChanges: waiting.map { .saveRecord($0) })
            Diagnostics.sync.notice(
                """
                device sync: staged \(records.summary.ciphertext.count, privacy: .public) + \
                \(records.entries?.ciphertext.count ?? 0, privacy: .public) sealed bytes
                """)

            try await engine.sendChanges()

            for id in waiting where outcomes[id] == .saved { saved.insert(id) }
            guard waiting.contains(where: { outcomes[$0] == .conflict }) else { break }
        }

        if !saved.contains(summaryID) {
            Diagnostics.sync.error("device sync: this device's summary record was not saved")
        }
        if writing.contains(entriesID), !saved.contains(entriesID) {
            Diagnostics.sync.error("device sync: this device's entries record was not saved")
        }
        return DeviceRecordsSaved(summary: saved.contains(summaryID), entries: saved.contains(entriesID))
    }

    public func ownRecords(of device: DeviceID) async throws -> [SealedSiblingFeed] {
        try await start()
        return try await fetchOwn(of: device).map(SealedSiblingFeed.init(ciphertext:))
    }

    private func fetchOwn(of device: DeviceID) async throws -> [Data] {
        let ids = ownIDs(of: device)
        let results: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            results = try await container.privateCloudDatabase.records(for: ids)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        }

        var found: [Data] = []
        for id in ids {
            switch results[id] {
            case .success(let record)?:
                known[id] = record
                if let data = record[Self.payloadKey] as? Data { found.append(data) }
            case .failure(let error as CKError)?
            where error.code == .unknownItem || error.code == .zoneNotFound
                || error.code == .userDeletedZone:
                known[id] = nil
            case .failure(let error)?:
                throw error
            case nil:
                continue
            }
        }
        Diagnostics.sync.notice(
            "device sync: read back \(found.count, privacy: .public) of this device's own record(s)")
        return found
    }

    public func refresh() async throws {
        try await start()
        guard let engine else { return }

        let started = Date()
        Diagnostics.sync.notice(
            "device sync: fetching; engine flagged \(engine.state.zoneIDsWithUnfetchedServerChanges.count, privacy: .public) zone(s) as pending")

        try await engine.fetchChanges()

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
        try? await stateStore.clear()
        Diagnostics.sync.notice("device sync: erased every feed on this account")
    }

    public func subscriptionSummary() async -> String {
        do {
            let all = try await container.privateCloudDatabase.allSubscriptions()
            guard !all.isEmpty else { return "No subscriptions: nothing will arrive on its own." }
            return all.map { "\($0.subscriptionID) (\(type(of: $0)))" }.joined(separator: "\n")
        } catch {
            return "Could not read subscriptions: \(error.localizedDescription)"
        }
    }

    public func forgetOwnContribution() async throws {
        try await start()
        guard let engine else { return }

        for id in ownIDs(of: device) { pending[id] = nil }
        engine.state.add(pendingRecordZoneChanges: ownIDs(of: device).map { .deleteRecord($0) })
        try await engine.sendChanges()
        Diagnostics.sync.notice("device sync: withdrew this device's records")
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

    fileprivate func saved(_ records: [CKRecord]) {
        for record in records {
            known[record.recordID] = record
            outcomes[record.recordID] = .saved
        }
    }

    fileprivate func conflicted(_ server: CKRecord) async {
        outcomes[server.recordID] = .conflict
        Diagnostics.sync.notice(
            "device sync: the server held a newer copy of one of this device's records; reading it first")
        await received([server])
        known[server.recordID] = server
    }

    fileprivate func failed(_ id: CKRecord.ID) {
        outcomes[id] = .failed
    }

    fileprivate func received(_ records: [CKRecord]) async {
        for record in records {
            if let held = known[record.recordID], held.recordChangeTag == record.recordChangeTag { continue }
            guard let data = record[Self.payloadKey] as? Data else { continue }
            guard let (_, writer) = DeviceRecordKind.parse(record.recordID.recordName) else {
                Diagnostics.sync.error("device sync: a device record's name named no device")
                continue
            }
            await handler?(SealedSiblingFeed(ciphertext: data), writer)
        }
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
                await owner.saved(sent.savedRecords)

                for failure in sent.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged,
                        let server = failure.error.serverRecord
                    {
                        await owner.conflicted(server)
                    } else {
                        await owner.failed(failure.record.recordID)
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
