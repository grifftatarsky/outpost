import CloudKit
import CarpenterKit
import Foundation

public actor PeerZoneDirectory {
    private struct Place: Codable, Hashable {
        let zoneName: String
        let ownerName: String
        let scope: Int
        let learnedAt: Date

        var zone: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
        var databaseScope: CKDatabase.Scope { CKDatabase.Scope(rawValue: scope) ?? .shared }
    }

    private var places: [RecipientTag: Place] = [:]
    private let store: (any DocumentStore)?
    private let clock: any Clock

    static let lifetime: TimeInterval = 30 * 24 * 60 * 60

    public init(store: (any DocumentStore)? = nil, clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    public func restore() async {
        guard let store, let saved = try? await store.load([RecipientTag: Place].self) else { return }
        let fresh = saved.filter { clock.now.timeIntervalSince($0.value.learnedAt) < Self.lifetime }
        places = fresh
        Diagnostics.sync.notice(
            "mailbox: restored \(fresh.count, privacy: .public) learned mailbox address(es)")
    }

    func learn(zone: CKRecordZone.ID, in scope: CKDatabase.Scope, for tags: Set<RecipientTag>) async {
        let place = Place(
            zoneName: zone.zoneName, ownerName: zone.ownerName, scope: scope.rawValue,
            learnedAt: clock.now)
        for tag in tags { places[tag] = place }
        await save()
    }

    func place(for tag: RecipientTag) -> (CKRecordZone.ID, CKDatabase.Scope)? {
        guard let place = places[tag] else { return nil }
        return (place.zone, place.databaseScope)
    }

    public var learnedCount: Int { places.count }

    private func save() async {
        guard let store else { return }
        let keep = places.filter { clock.now.timeIntervalSince($0.value.learnedAt) < Self.lifetime }
        places = keep
        try? await store.save(keep)
    }
}
