import Foundation
import Testing

@testable import CarpenterKit

@Suite("The log and the state stay out of backups")
struct BackupExclusionTests {
    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "backups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isLeftOut(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    private func entries(_ count: Int) throws -> [Entry] {
        let identity = Identity.generate()
        let device = DeviceKeys.generate()
        let room = ConversationID.room(UUID())
        let (chain, _) = EpochChain.create(room: room)
        let feed = FeedKey(author: identity.id, device: device.id, conversation: room)
        var made: [Entry] = []
        for index in 0..<count {
            made.append(
                try Entry.append(
                    after: made.last?.link, author: identity.id, device: device, clock: VectorClock(),
                    wallTime: Date(), conversation: room,
                    payload: try Payload.post("line \(index)").sealed(at: .initial, using: chain, by: feed)))
        }
        return made
    }

    @Test("A state file left out of backups stays out after every save replaces it")
    func stateStaysOut() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: StorageLocation.stateName)
        let store = FileDocumentStore(url: url, backups: .excluded)

        try await store.save(["first"])
        #expect(try isLeftOut(url))
        try await store.save(["second"])
        #expect(try isLeftOut(url), "saving again put a new file in place, and it went back into backups")
    }

    @Test("A log left out of backups stays out when it is appended to, rewritten or recreated")
    func logStaysOut() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: StorageLocation.logName)
        let store = FileLogStore(url: url, backups: .excluded)
        let written = try entries(3)

        try await store.append(Array(written.prefix(2)))
        #expect(try isLeftOut(url))

        try await store.removeEntries { $0.hash == written[0].hash }
        #expect(try isLeftOut(url), "removing entries rewrote the log, and it went back into backups")

        try await store.removeAll()
        try await store.append([written[2]])
        #expect(try isLeftOut(url), "a log made again from nothing went into backups")
    }

    @Test("A file an earlier build left in backups is taken out as soon as it is read")
    func readingTakesItOut() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appending(path: StorageLocation.stateName)
        let log = root.appending(path: StorageLocation.logName)
        try await FileDocumentStore(url: state).save(["from before"])
        try await FileLogStore(url: log).append(try entries(1))
        #expect(try !isLeftOut(state) && !isLeftOut(log), "precondition: both began in backups")

        _ = try await FileDocumentStore(url: state, backups: .excluded).load([String].self)
        _ = try await FileLogStore(url: log, backups: .excluded).loadAll()
        #expect(try isLeftOut(state), "a state file nobody wrote to again stayed in backups")
        #expect(try isLeftOut(log), "a log nobody appended to again stayed in backups")
    }

    @Test("A store not told to leave its file out of backups leaves it in")
    func theDefaultIsIncluded() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appending(path: "kept.json")
        try await FileDocumentStore(url: state).save(["kept"])
        #expect(try !isLeftOut(state))

        let log = root.appending(path: "kept.log")
        try await FileLogStore(url: log).append(try entries(1))
        #expect(try !isLeftOut(log))
    }
}
