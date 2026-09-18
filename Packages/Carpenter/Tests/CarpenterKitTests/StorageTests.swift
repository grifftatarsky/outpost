import Foundation
import Testing

@testable import CarpenterKit

@Suite("Log storage", .serialized)
struct LogStoreTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func scratch() -> URL {
        URL.temporaryDirectory
            .appending(path: "carpenter-tests-\(UUID().uuidString)")
            .appending(path: "log.carpenter")
    }

    @Test("Entries survive a reload")
    func roundTrip() async throws {
        let url = scratch()
        var alice = Author()
        let entries = [
            try alice.post("one", at: start),
            try alice.post("two", at: start.addingTimeInterval(1)),
        ]

        try await FileLogStore(url: url).append(entries)
        let loaded = try await FileLogStore(url: url).loadAll()

        #expect(loaded.entries == entries)
        #expect(!loaded.wasTruncated)
        try await FileLogStore(url: url).removeAll()
    }

    @Test("Nothing stored reads as nothing, not as an error")
    func emptyStore() async throws {
        let loaded = try await FileLogStore(url: scratch()).loadAll()

        #expect(loaded.entries.isEmpty)
        #expect(!loaded.wasTruncated)
    }

    @Test("Appending adds to what is there rather than replacing it")
    func appendsAccumulate() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        try await store.append([try alice.post("one", at: start)])
        try await store.append([try alice.post("two", at: start.addingTimeInterval(1))])

        #expect(try await store.loadAll().entries.count == 2)
        try await store.removeAll()
    }

    @Test("Appending does not rewrite the history already on disk")
    func appendsAreIncremental() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        try await store.append(
            try (0..<20).map { try alice.post("entry \($0)", at: start.addingTimeInterval(Double($0))) })
        let sizeBefore = try Data(contentsOf: url).count

        try await store.append([try alice.post("one more", at: start.addingTimeInterval(100))])
        let sizeAfter = try Data(contentsOf: url).count

        #expect(sizeAfter > sizeBefore)
        #expect(sizeAfter - sizeBefore < sizeBefore)
        try await store.removeAll()
    }

    @Test("A torn tail loses only the record being written")
    func tornTail() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        let good = [
            try alice.post("kept", at: start),
            try alice.post("also kept", at: start.addingTimeInterval(1)),
        ]
        try await store.append(good)
        try await store.append([try alice.post("torn", at: start.addingTimeInterval(2))])

        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count - 40).write(to: url)

        let loaded = try await store.loadAll()

        #expect(loaded.entries == good)
        #expect(loaded.termination == .tornTail)
        try await store.removeAll()
    }

    @Test("Compacting repairs the damage so it is not re-reported every launch")
    func compaction() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        try await store.append([try alice.post("kept", at: start)])
        try await store.append([try alice.post("torn", at: start.addingTimeInterval(1))])

        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count - 40).write(to: url)

        try await store.compact()
        let loaded = try await store.loadAll()

        #expect(loaded.entries.count == 1)
        #expect(loaded.termination == .complete)
        try await store.removeAll()
    }

    @Test("A record length past the ceiling is refused even when it fits in the file")
    func lengthCeiling() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url, maximumRecordBytes: 1_024)
        try await store.append([try alice.post("kept", at: start)])

        var data = try Data(contentsOf: url)
        data.append(withUnsafeBytes(of: UInt32(2_000).bigEndian) { Data($0) })
        data.append(Data(repeating: 0x41, count: 2_000))
        try data.write(to: url)

        let loaded = try await FileLogStore(url: url, maximumRecordBytes: 1_024).loadAll()

        #expect(loaded.entries.count == 1)
        #expect(loaded.termination == .recordTooLarge)
        #expect(loaded.discardedTrailingBytes == 2_004)
        try await store.removeAll()
    }

    @Test("A whole week of conversation reloads intact")
    func volume() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        let entries = try (0..<600).map {
            try alice.post("entry \($0)", at: start.addingTimeInterval(Double($0 * 60)))
        }
        try await store.append(entries)

        let loaded = try await store.loadAll()

        #expect(loaded.entries.count == 600)
        #expect(loaded.entries == entries)
        try await store.removeAll()
    }

    @Test("A reloaded log rebuilds a replica that renders the same thing")
    func rebuildsAReplica() async throws {
        let url = scratch()
        var alice = Author()
        let store = FileLogStore(url: url)

        var live = Replica()
        try live.meet(alice)
        let entries = [
            try alice.post("hydrogen, obviously", at: start),
            try alice.post("helium coward", at: start.addingTimeInterval(1)),
        ]
        for entry in entries { try live.integrate(entry) }
        try await store.append(entries)

        var restored = Replica()
        try restored.meet(alice)
        for entry in try await store.loadAll().entries { try restored.integrate(entry) }

        #expect(
            Fold.render(restored.ordered(), using: alice.chain)
                == Fold.render(live.ordered(), using: alice.chain))
        try await store.removeAll()
    }
}

@Suite("Document storage", .serialized)
struct DocumentStoreTests {
    private func scratch() -> URL {
        URL.temporaryDirectory
            .appending(path: "carpenter-tests-\(UUID().uuidString)")
            .appending(path: "organisation.json")
    }

    @Test("A value survives a reload")
    func roundTrip() async throws {
        let url = scratch()
        let store = FileDocumentStore(url: url)

        var organisation = RoomsListOrganisation()
        let stamp = OrganisationStamp(at: Date(timeIntervalSince1970: 0), device: DeviceKeys.generate().id)
        organisation.addTag(named: "Airships", stamp: stamp)

        try await store.save(organisation)
        let loaded = try await store.load(RoomsListOrganisation.self)

        #expect(loaded?.orderedTags.map(\.name.value) == ["Airships"])
        try await store.clear()
    }

    @Test("Nothing stored reads as nil rather than as an empty value")
    func absent() async throws {
        #expect(try await FileDocumentStore(url: scratch()).load(RoomsListOrganisation.self) == nil)
    }

    @Test("Saving twice replaces rather than appending")
    func overwrite() async throws {
        let url = scratch()
        let store = FileDocumentStore(url: url)
        let stamp = OrganisationStamp(at: Date(timeIntervalSince1970: 0), device: DeviceKeys.generate().id)

        var first = RoomsListOrganisation()
        first.addTag(named: "Airships", stamp: stamp)
        try await store.save(first)

        var second = RoomsListOrganisation()
        second.addTag(named: "Projects", stamp: stamp)
        try await store.save(second)

        #expect(try await store.load(RoomsListOrganisation.self)?.orderedTags.count == 1)
        try await store.clear()
    }

    @Test("A save replaces the file rather than writing into it")
    func savesAreAtomicReplacements() async throws {
        let url = scratch()
        let store = FileDocumentStore(url: url)
        let stamp = OrganisationStamp(at: Date(timeIntervalSince1970: 0), device: DeviceKeys.generate().id)

        var organisation = RoomsListOrganisation()
        organisation.addTag(named: "Airships", stamp: stamp)
        try await store.save(organisation)

        func fileIdentity() throws -> UInt64 {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.systemFileNumber] as? UInt64 ?? 0
        }
        let before = try fileIdentity()

        organisation.addTag(named: "Projects", stamp: stamp)
        try await store.save(organisation)

        #expect(try fileIdentity() != before)
        #expect(try await store.load(RoomsListOrganisation.self)?.orderedTags.count == 2)
        try await store.clear()
    }

    @Test("A save leaves no scratch files behind")
    func atomicSaveIsTidy() async throws {
        let url = scratch()
        let store = FileDocumentStore(url: url)
        let stamp = OrganisationStamp(at: Date(timeIntervalSince1970: 0), device: DeviceKeys.generate().id)

        var organisation = RoomsListOrganisation()
        organisation.addTag(named: "Airships", stamp: stamp)
        try await store.save(organisation)
        try await store.save(organisation)

        let contents = try FileManager.default.contentsOfDirectory(
            atPath: url.deletingLastPathComponent().path)

        #expect(!contents.contains { $0.hasPrefix(".\(url.lastPathComponent).") },
            "a save left its scratch file behind")
        #expect(Set(contents) == [url.lastPathComponent, ".carpenter.lock"])
        try await store.clear()
    }
}
