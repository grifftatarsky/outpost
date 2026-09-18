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
    private var pending: Data?

    private var starting: Task<Void, any Error>?

    private var known: CKRecord?

    public init(container: CKContainer, device: DeviceID, stateStore: any DocumentStore) {
        self.container = container
        self.device = device
        self.stateStore = stateStore
    }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }

    private func recordID(for device: DeviceID) -> CKRecord.ID {
        CKRecord.ID(recordName: Self.namePrefix + Self.hex(device.rawValue), zoneID: zoneID)
    }

    private static let namePrefix = "feed-"

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func device(named name: String) -> DeviceID? {
        guard name.hasPrefix(namePrefix) else { return nil }
        let digits = Array(name.dropFirst(namePrefix.count))
        guard digits.count % 2 == 0 else { return nil }
        var bytes = Data()
        for pair in stride(from: 0, to: digits.count, by: 2) {
            guard let byte = UInt8(String(digits[pair...pair + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return DeviceID(rawValue: bytes)
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

        do {
            known = try await container.privateCloudDatabase.record(for: recordID(for: device))
        } catch let error as CKError where error.code == .unknownItem {
            known = nil
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

    public func onIncoming(_ handler: @escaping @Sendable (SealedSiblingFeed, DeviceID) async -> Void)
        async
    {
        self.handler = handler
    }

    public func send(_ feed: SealedSiblingFeed, from device: DeviceID) async throws {
        pending = feed.ciphertext

        try await start()
        guard let engine else { return }

        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(for: device))])
        Diagnostics.sync.notice(
            "device sync: staged \(feed.ciphertext.count, privacy: .public) sealed bytes")

        try await engine.sendChanges()
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
        known = nil
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

        pending = nil
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(for: device))])
        try await engine.sendChanges()
        Diagnostics.sync.notice("device sync: withdrew this device's feed")
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
        guard let pending else {
            Diagnostics.sync.error(
                "device sync: \(changes.count, privacy: .public) change(s) staged but no feed to send")
            return nil
        }

        let mine = recordID(for: device)
        let feed = pending

        let template = known

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            guard id == mine else { return nil }

            let record = template ?? CKRecord(recordType: Self.recordType, recordID: id)
            record[Self.payloadKey] = feed as NSData
            return record
        }
    }

    fileprivate func saved(_ records: [CKRecord]) {
        for record in records where record.recordID == recordID(for: device) {
            known = record
        }
    }

    fileprivate func resolve(_ record: CKRecord) {
        guard record.recordID == recordID(for: device) else { return }
        known = record
        Diagnostics.sync.notice("device sync: adopted the server's copy after a conflict")
    }

    fileprivate func received(_ records: [CKRecord]) async {
        let mine = recordID(for: device)

        for record in records where record.recordID != mine {
            guard let data = record[Self.payloadKey] as? Data else { continue }
            guard let writer = Self.device(named: record.recordID.recordName) else {
                Diagnostics.sync.error("device sync: a sibling record's name named no device")
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
                        await owner.resolve(server)

                        let id = failure.record.recordID
                        Task {
                            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                            do {
                                try await syncEngine.sendChanges()
                            } catch {
                                Diagnostics.sync.error(
                                    "device sync: retry after conflict failed: \(String(describing: error), privacy: .public)")
                            }
                        }
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
