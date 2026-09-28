import CloudKit
import Foundation
import Testing

enum PairRig {
    static let step = ProcessInfo.processInfo.environment["CARPENTER_PAIR_STEP"] ?? ""
    static let dir = URL(filePath: "/tmp/outpost-rig-exchange/pairs")
    static let count = 300
    static let special = ["one-person", "nobody", "restrict-later"]
    static var container: CKContainer { .default() }

    static func zone(_ index: Int) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "PairMeasure-\(index)")
    }

    static func note(_ line: String) {
        print("PAIR: \(line)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "notes-\(step).txt")
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? (old + line + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    static func timed<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await work()
        note("\(label): \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        return result
    }

    static func write(_ value: some Encodable, _ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: dir.appending(path: name))
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: dir.appending(path: name)))
    }

    static func archive(_ token: CKServerChangeToken, _ name: String) throws {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            .write(to: dir.appending(path: name))
    }

    static func unarchive(_ name: String) throws -> CKServerChangeToken? {
        try NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: Data(contentsOf: dir.appending(path: name)))
    }

    static func chunks<T>(_ items: [T], _ size: Int = 200) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? CKError else { return "\(error)" }
        return "CKError \(error.code.rawValue) \(error.code) — \(error.localizedDescription)"
    }

    static func identity(_ participant: CKShare.Participant) -> String {
        let who = participant.userIdentity
        let name = who.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) } ?? "no name"
        let email = who.lookupInfo?.emailAddress ?? "no email"
        let phone = who.lookupInfo?.phoneNumber ?? "no phone"
        let record = who.userRecordID?.recordName.prefix(6) ?? "no record"
        return "role \(participant.role.rawValue): name[\(name.isEmpty ? "empty" : "\(name.count) chars")] email[\(email == "no email" ? email : "present")] phone[\(phone == "no phone" ? phone : "present")] record[\(record)] account[\(who.hasiCloudAccount)]"
    }

    static func sharedZone(_ index: Int) async throws -> CKRecordZone.ID {
        let (zones, _, _) = try await sharedChanges(since: nil)
        guard let zone = zones.first(where: { $0.zoneName == "PairMeasure-\(index)" }) else { throw CKError(.zoneNotFound) }
        return zone
    }

    static func attempt(_ label: String, _ work: () async throws -> Void) async {
        do {
            try await work()
            note("\(label): ACCEPTED")
        } catch { note("\(label): refused, \(describe(error))") }
    }

    static func sharedChanges(since token: CKServerChangeToken?) async throws -> ([CKRecordZone.ID], [CKRecordZone.ID], CKServerChangeToken) {
        var token = token
        var changed: [CKRecordZone.ID] = []
        var gone: [CKRecordZone.ID] = []
        while true {
            let page = try await container.sharedCloudDatabase.databaseChanges(since: token)
            changed += page.modifications.map(\.zoneID)
            gone += page.deletions.map(\.zoneID)
            token = page.changeToken
            if !page.moreComing { break }
        }
        return (changed, gone, token!)
    }

    static func zoneChanges(_ zones: [CKRecordZone.ID], since tokens: [CKRecordZone.ID: CKServerChangeToken])
        async throws -> (records: Int, deletions: Int, failures: [String])
    {
        var records = 0
        var deletions = 0
        var failures: [String] = []
        for group in chunks(zones, 100) {
            let configs = Dictionary(uniqueKeysWithValues: group.map { zone in
                (zone, CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: tokens[zone]))
            })
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: group, configurationsByRecordZoneID: configs)
            let counts = Counts()
            operation.recordWasChangedBlock = { _, result in counts.add(record: (try? result.get()) != nil) }
            operation.recordWithIDWasDeletedBlock = { _, _ in counts.addDeletion() }
            operation.recordZoneFetchResultBlock = { zone, result in
                if case .failure(let error) = result { counts.fail("\(zone.zoneName): \(describe(error))") }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.fetchRecordZoneChangesResultBlock = { continuation.resume(with: $0) }
                container.sharedCloudDatabase.add(operation)
            }
            let (r, d, f) = counts.values
            records += r
            deletions += d
            failures += f
        }
        return (records, deletions, failures)
    }
}

final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var records = 0
    private var deletions = 0
    private var failures: [String] = []
    func add(record ok: Bool) { lock.withLock { if ok { records += 1 } } }
    func addDeletion() { lock.withLock { deletions += 1 } }
    func fail(_ line: String) { lock.withLock { failures.append(line) } }
    var values: (Int, Int, [String]) { lock.withLock { (records, deletions, failures) } }
}

@Suite("Measuring a mailbox per pair of people", .serialized)
struct LivePairMailboxMeasurements {
    @Test(.enabled(if: PairRig.step == "beta-id"))
    func betaSaysWhoItIs() async throws {
        let id = try await PairRig.container.userRecordID()
        try PairRig.write(id.recordName, "beta-user.json")
        PairRig.note("beta user record \(id.recordName.prefix(6))…")
    }

    @Test(.enabled(if: PairRig.step == "alpha-make"))
    func alphaMakesSpacesAndLinks() async throws {
        let db = PairRig.container.privateCloudDatabase
        let names = (0..<PairRig.count).map(PairRig.zone)
        try await PairRig.timed("made \(names.count) spaces") {
            for group in PairRig.chunks(names, 50) {
                let result = try await db.modifyRecordZones(saving: group.map { CKRecordZone(zoneID: $0) }, deleting: [])
                for (id, outcome) in result.saveResults {
                    if case .failure(let error) = outcome { PairRig.note("space \(id.zoneName) failed: \(PairRig.describe(error))") }
                }
            }
        }

        let betaName = try PairRig.read(String.self, "beta-user.json")
        let lookup = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: betaName))
        let beta: CKShare.Participant? = await withCheckedContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            let found = Found()
            operation.perShareParticipantResultBlock = { _, result in
                switch result {
                case .success(let participant): found.participant = participant
                case .failure(let error): PairRig.note("looking up beta failed: \(PairRig.describe(error))")
                }
            }
            operation.fetchShareParticipantsResultBlock = { result in
                if case .failure(let error) = result { PairRig.note("participant lookup failed: \(PairRig.describe(error))") }
                continuation.resume(returning: found.participant)
            }
            PairRig.container.add(operation)
        }
        PairRig.note("beta found by user record: \(beta != nil)")

        var shares: [CKShare] = []
        var records: [CKRecord] = []
        for (index, zone) in names.enumerated() {
            let share = CKShare(recordZoneID: zone)
            switch index {
            case 0:
                share.publicPermission = .none
                if let beta {
                    beta.permission = .readOnly
                    share.addParticipant(beta)
                }
            case 1: share.publicPermission = .none
            default: share.publicPermission = .readOnly
            }
            shares.append(share)
            for n in 0..<2 {
                let record = CKRecord(recordType: "PairMeasure", recordID: CKRecord.ID(recordName: "m\(n)", zoneID: zone))
                record["body"] = Data((0..<1024).map { _ in UInt8.random(in: 0...255) }) as NSData
                records.append(record)
            }
        }

        var urls: [String: String] = [:]
        try await PairRig.timed("made \(shares.count) links") {
            for group in PairRig.chunks(shares, 50) {
                let result = try await db.modifyRecords(saving: group, deleting: [])
                for (id, outcome) in result.saveResults {
                    switch outcome {
                    case .success(let record):
                        if let share = record as? CKShare, let url = share.url { urls[id.zoneID.zoneName] = url.absoluteString }
                    case .failure(let error): PairRig.note("link \(id.zoneID.zoneName) failed: \(PairRig.describe(error))")
                    }
                }
            }
        }
        try await PairRig.timed("wrote \(records.count) records") {
            for group in PairRig.chunks(records, 100) {
                let result = try await db.modifyRecords(saving: group, deleting: [])
                let failed = result.saveResults.values.filter { if case .failure = $0 { true } else { false } }.count
                if failed > 0 { PairRig.note("\(failed) record writes failed") }
            }
        }
        try PairRig.write(urls, "urls.json")
        PairRig.note("links written: \(urls.count)")
    }

    @Test(.enabled(if: PairRig.step == "beta-open"))
    func betaOpensEveryLink() async throws {
        let urls = try PairRig.read([String: String].self, "urls.json")
        var metadatas: [CKShare.Metadata] = []
        try await PairRig.timed("read \(urls.count) links") {
            for group in PairRig.chunks(Array(urls), 100) {
                let result = try await PairRig.container.shareMetadatas(for: group.compactMap { URL(string: $0.value) })
                for (url, outcome) in result {
                    switch outcome {
                    case .success(let metadata): metadatas.append(metadata)
                    case .failure(let error):
                        let name = urls.first { $0.value == url.absoluteString }?.key ?? "?"
                        PairRig.note("reading link \(name) failed: \(PairRig.describe(error))")
                    }
                }
            }
        }
        PairRig.note("links read: \(metadatas.count)")
        for metadata in metadatas where ["PairMeasure-0", "PairMeasure-1"].contains(metadata.share.recordID.zoneID.zoneName) {
            PairRig.note("\(metadata.share.recordID.zoneID.zoneName): role \(metadata.participantRole.rawValue) status \(metadata.participantStatus.rawValue) permission \(metadata.participantPermission.rawValue)")
        }
        try await PairRig.timed("accepted \(metadatas.count) links") {
            for group in PairRig.chunks(metadatas, 50) {
                for metadata in group {
                    do { _ = try await PairRig.container.accept(metadata) } catch {
                        PairRig.note("accepting \(metadata.share.recordID.zoneID.zoneName) failed: \(PairRig.describe(error))")
                    }
                }
            }
        }

        let (zones, _, token) = try await PairRig.timed("listed shared spaces") { try await PairRig.sharedChanges(since: nil) }
        PairRig.note("shared spaces listed: \(zones.count)")
        try PairRig.archive(token, "db-token")
        let full = try await PairRig.timed("first full read of \(zones.count) spaces") {
            try await PairRig.zoneChanges(zones, since: [:])
        }
        PairRig.note("records read: \(full.records); failures: \(full.failures.count) \(full.failures.prefix(3))")
        let (_, _, again) = try await PairRig.timed("check with nothing new") { try await PairRig.sharedChanges(since: token) }
        _ = again

    }

    @Test(.enabled(if: PairRig.step == "beta-probe"))
    func betaTriesToWrite() async throws {
        let shared = PairRig.container.sharedCloudDatabase
        let target = try await PairRig.sharedZone(10)
        let attempt = CKRecord(recordType: "PairMeasure", recordID: CKRecord.ID(recordName: "intruder", zoneID: target))
        attempt["body"] = Data([1]) as NSData
        await PairRig.attempt("watch one of alpha's spaces") {
            let sub = CKRecordZoneSubscription(zoneID: target, subscriptionID: "pair-measure-zone")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            _ = try await shared.save(sub)
        }
        await PairRig.attempt("add a record to alpha's space") { _ = try await shared.modifyRecords(saving: [attempt], deleting: []).saveResults.first?.value.get() }
        await PairRig.attempt("delete a record in alpha's space") { _ = try await shared.modifyRecords(saving: [], deleting: [CKRecord.ID(recordName: "m1", zoneID: target)]).deleteResults.first?.value.get() }
        await PairRig.attempt("change a record in alpha's space") {
            let record = try await shared.record(for: CKRecord.ID(recordName: "m1", zoneID: target))
            record["body"] = Data([9]) as NSData
            _ = try await shared.modifyRecords(saving: [record], deleting: []).saveResults.first?.value.get()
        }
        await PairRig.attempt("change alpha's link") {
            let zone = try await shared.recordZone(for: target)
            guard let reference = zone.share, let share = try await shared.record(for: reference.recordID) as? CKShare
            else { throw CKError(.unknownItem) }
            share[CKShare.SystemFieldKey.title] = "changed by beta" as NSString
            _ = try await shared.modifyRecords(saving: [share], deleting: []).saveResults.first?.value.get()
        }
    }

    @Test(.enabled(if: PairRig.step == "alpha-change"))
    func alphaChangesAFew() async throws {
        let db = PairRig.container.privateCloudDatabase
        let fresh = CKRecord(recordType: "PairMeasure", recordID: CKRecord.ID(recordName: "new", zoneID: PairRig.zone(150)))
        fresh["body"] = Data([2]) as NSData
        _ = try await db.modifyRecords(saving: [fresh], deleting: [CKRecord.ID(recordName: "m0", zoneID: PairRig.zone(151))])
        PairRig.note("wrote in 150, deleted in 151 at \(Date())")

        let zone = PairRig.zone(2)
        let shareID = try #require(try await db.recordZone(for: zone).share?.recordID)
        let share = try #require(try await db.record(for: shareID) as? CKShare)
        PairRig.note("PairMeasure-2 participants before: \(share.participants.map { "\($0.role.rawValue)/\($0.acceptanceStatus.rawValue)/\($0.permission.rawValue)" })")
        share.publicPermission = .none
        let saved = try await db.modifyRecords(saving: [share], deleting: [])
        if let after = try saved.saveResults[shareID]?.get() as? CKShare {
            PairRig.note("PairMeasure-2 participants after closing the link: \(after.participants.map { "\($0.role.rawValue)/\($0.acceptanceStatus.rawValue)/\($0.permission.rawValue)" })")
        }
    }

    @Test(.enabled(if: PairRig.step == "alpha-poke"))
    func alphaWritesOnce() async throws {
        let fresh = CKRecord(recordType: "PairMeasure", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: PairRig.zone(77)))
        fresh["body"] = Data([3]) as NSData
        _ = try await PairRig.container.privateCloudDatabase.modifyRecords(saving: [fresh], deleting: [])
        PairRig.note("wrote in 77")
    }

    @Test(.enabled(if: PairRig.step == "beta-again"))
    func betaReadsWhatChanged() async throws {
        let token = try PairRig.unarchive("db-token")
        let (zones, gone, next) = try await PairRig.timed("check after alpha changed two spaces") {
            try await PairRig.sharedChanges(since: token)
        }
        try PairRig.archive(next, "db-token")
        PairRig.note("spaces reported changed: \(zones.map(\.zoneName)); gone: \(gone.map(\.zoneName))")
        let shared = PairRig.container.sharedCloudDatabase
        for index in [0, 2] {
            do {
                let record = try await shared.record(for: CKRecord.ID(recordName: "m1", zoneID: try await PairRig.sharedZone(index)))
                PairRig.note("PairMeasure-\(index) still readable: \(record.recordID.recordName)")
            } catch { PairRig.note("PairMeasure-\(index) not readable: \(PairRig.describe(error))") }
        }
    }

    @Test(.enabled(if: PairRig.step == "alpha-who"))
    func alphaSeesWhoTheyAdded() async throws {
        let db = PairRig.container.privateCloudDatabase
        let zone = PairRig.zone(999)
        let shareID = (try? await db.recordZone(for: zone))?.share?.recordID
        if let shareID, let share = try await db.record(for: shareID) as? CKShare {
            PairRig.note("after joining, alpha sees: \(share.participants.map(PairRig.identity))")
            return
        }
        _ = try await db.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
        let betaName = try PairRig.read(String.self, "beta-user.json")
        let lookup = CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: betaName))
        let beta: CKShare.Participant? = await withCheckedContinuation { continuation in
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            let found = Found()
            operation.perShareParticipantResultBlock = { _, result in found.participant = try? result.get() }
            operation.fetchShareParticipantsResultBlock = { _ in continuation.resume(returning: found.participant) }
            PairRig.container.add(operation)
        }
        let share = CKShare(recordZoneID: zone)
        share.publicPermission = .none
        if let beta {
            beta.permission = .readOnly
            share.addParticipant(beta)
            PairRig.note("lookup gives alpha: \(PairRig.identity(beta))")
        }
        let saved = try await db.modifyRecords(saving: [share], deleting: [])
        let back = try saved.saveResults[share.recordID]?.get() as? CKShare
        PairRig.note("saved share lists: \(back?.participants.map(PairRig.identity) ?? [])")
        try PairRig.write([back?.url?.absoluteString ?? ""], "who-url.json")
    }

    @Test(.enabled(if: PairRig.step == "beta-who"))
    func betaSeesWhoInvitedThem() async throws {
        let url = try #require(URL(string: try PairRig.read([String].self, "who-url.json")[0]))
        let metadata = try await PairRig.container.shareMetadata(for: url)
        PairRig.note("before joining, beta sees owner: \(PairRig.identity(metadata.share.owner))")
        PairRig.note("before joining, beta sees everyone: \(metadata.share.participants.map(PairRig.identity))")
        _ = try await PairRig.container.accept(metadata)
        let again = try await PairRig.container.shareMetadata(for: url)
        PairRig.note("after joining, beta sees everyone: \(again.share.participants.map(PairRig.identity))")
    }

    @Test(.enabled(if: PairRig.step == "alpha-clean"))
    func alphaClearsUp() async throws {
        let db = PairRig.container.privateCloudDatabase
        let mine = try await db.allRecordZones().map(\.zoneID).filter { $0.zoneName.hasPrefix("PairMeasure-") }
        for group in PairRig.chunks(mine) { _ = try await db.modifyRecordZones(saving: [], deleting: group) }
        PairRig.note("deleted \(mine.count) spaces")
    }

    @Test(.enabled(if: PairRig.step == "beta-clean"))
    func betaClearsUp() async throws {
        let shared = PairRig.container.sharedCloudDatabase
        _ = try? await shared.modifySubscriptions(saving: [], deleting: ["pair-measure-db", "pair-measure-zone"])
        let (zones, _, _) = try await PairRig.sharedChanges(since: nil)
        let left = zones.filter { $0.zoneName.hasPrefix("PairMeasure-") }
        PairRig.note("shared spaces left: \(left.count)")
        if let first = left.first {
            await PairRig.attempt("read \(first.zoneName)") { _ = try await shared.recordZone(for: first) }
        }
        for group in PairRig.chunks(left, 50) {
            let result = try await shared.modifyRecordZones(saving: [], deleting: group)
            let failed = result.deleteResults.filter { if case .failure = $0.value { true } else { false } }.count
            PairRig.note("left \(group.count - failed), failed \(failed)")
        }
    }
}

final class Found: @unchecked Sendable {
    var participant: CKShare.Participant?
}

private func outcomeText<T>(_ outcome: Result<T, Error>) -> String {
    switch outcome {
    case .success: "ACCEPTED"
    case .failure(let error): "refused, \(PairRig.describe(error))"
    }
}
