import Foundation
import Testing

@testable import CarpenterKit

@Suite("Concurrent storage", .serialized)
struct ConcurrentStorageTests {
    private func scratch() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "carpenter-concurrent-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("Concurrent appends from separate stores lose nothing and tear nothing")
    func concurrentAppendsSurvive() async throws {
        let directory = scratch()
        let url = directory.appending(path: "log.carpenter")

        let writers = 8
        let perWriter = 25

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    var author = Author()
                    let store = FileLogStore(url: url)
                    for index in 0..<perWriter {
                        guard
                            let entry = try? author.post(
                                "writer \(writer) entry \(index)",
                                at: Date(timeIntervalSince1970: 1_786_635_000))
                        else { continue }
                        try? await store.append([entry])
                    }
                }
            }
        }

        let loaded = try await FileLogStore(url: url).loadAll()

        #expect(
            loaded.termination == .complete,
            "the log tore: \(loaded.termination), \(loaded.discardedTrailingBytes) bytes discarded")
        #expect(
            loaded.entries.count == writers * perWriter,
            "\(writers * perWriter - loaded.entries.count) entries were lost to interleaved appends")
    }

    @Test("Taking a room out of the log while other stores append loses none of what they wrote")
    func removalDuringAppendsLosesNothing() async throws {
        let directory = scratch()
        let url = directory.appending(path: "log.carpenter")
        let deleted = RoomID()
        let kept = RoomID()

        var seed = Author()
        try await FileLogStore(url: url).append(
            try (0..<50).map { index in
                try seed.append(
                    try Payload.post("deleted \(index)"), at: Date(timeIntervalSince1970: 0), room: deleted)
            })

        let writers = 8
        let perWriter = 25

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<writers {
                group.addTask {
                    var author = Author()
                    let store = FileLogStore(url: url)
                    for index in 0..<perWriter {
                        guard
                            let entry = try? author.append(
                                try Payload.post("writer \(writer) entry \(index)"),
                                at: Date(timeIntervalSince1970: 1), room: kept)
                        else { continue }
                        try? await store.append([entry])
                    }
                }
            }
            group.addTask {
                let store = FileLogStore(url: url)
                for _ in 0..<20 {
                    _ = try? await store.removeEntries { $0.room == deleted }
                }
            }
        }

        let loaded = try await FileLogStore(url: url).loadAll()
        #expect(loaded.termination == .complete, "the log tore: \(loaded.termination)")
        #expect(!loaded.entries.contains { $0.room == deleted })
        #expect(
            loaded.entries.count { $0.room == kept } == writers * perWriter,
            "\(writers * perWriter - loaded.entries.count { $0.room == kept }) appended entries were lost to a rewrite")
    }

    @Test("Concurrent saves leave one whole readable document")
    func concurrentSavesLeaveSomethingWhole() async throws {
        let directory = scratch()
        let url = directory.appending(path: "state.json")
        let stamp = OrganisationStamp(
            at: Date(timeIntervalSince1970: 0), device: DeviceKeys.generate().id)

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<8 {
                group.addTask {
                    let store = FileDocumentStore(url: url)
                    for index in 0..<25 {
                        var organisation = RoomsListOrganisation()
                        organisation.addTag(named: "writer-\(writer)-\(index)", stamp: stamp)
                        try? await store.save(organisation)
                    }
                }
            }
        }

        let loaded = try await FileDocumentStore(url: url).load(RoomsListOrganisation.self)
        #expect(loaded != nil, "the state file was left unreadable by concurrent saves")
        #expect(loaded?.orderedTags.count == 1, "the state file was left holding a blend of two saves")
    }
}
