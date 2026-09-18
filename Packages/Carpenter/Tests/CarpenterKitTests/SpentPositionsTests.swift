@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A deleted conversation leaves its positions spent, not empty")
struct SpentPositionsTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func interleaved() throws -> (
        replica: Replica, author: Author, kept: RoomID, deleted: RoomID, entries: [Entry]
    ) {
        var author = Author()
        let kept = RoomID()
        let deleted = RoomID()
        var entries: [Entry] = []
        for index in 0..<6 {
            let room = index.isMultiple(of: 2) ? kept : deleted
            entries.append(
                try author.append(
                    try Payload.post("line \(index)"), at: start.addingTimeInterval(Double(index)),
                    room: room))
        }
        var replica = Replica()
        try replica.meet(author)
        for entry in entries { try replica.integrate(entry) }
        return (replica, author, kept, deleted, entries)
    }

    @Test("Closing a room takes its entries out and leaves no hole in a feed it shared")
    func closingLeavesNoHole() throws {
        var (replica, author, kept, deleted, entries) = try interleaved()

        let taken = replica.close(deleted)

        #expect(Set(taken.map(\.hash)) == Set(entries.filter { $0.room == deleted }.map(\.hash)))
        #expect(replica.entries(in: deleted).isEmpty)
        #expect(replica.entries(in: kept).count == 3, "closing one room took entries from another")
        #expect(
            replica.gaps(from: [author.identity.id]).isEmpty,
            "the positions a deleted room held read as missing, so repair would ask for them back")
        #expect(replica.frontier[author.feedKey] == 6)
    }

    @Test("A deleted room's entry offered again is not kept, whether this device had it or not")
    func offeredAgainIsNotKept() throws {
        var author = Author()
        let deleted = RoomID()
        let first = try author.append(try Payload.post("one"), at: start, room: deleted)
        let second = try author.append(
            try Payload.post("two"), at: start.addingTimeInterval(1), room: deleted)

        var replica = Replica()
        try replica.meet(author)
        try replica.integrate(first)
        replica.close(deleted)

        #expect(try replica.integrate(first) == .alreadyPresent, "a spent entry came back")
        #expect(try replica.integrate(second) == .alreadyPresent, "a late entry reopened the room")
        #expect(replica.entryCount == 0)
        #expect(replica.gaps().isEmpty)
        #expect(replica.spentEntries.map(\.seq) == [1, 2], "the late arrival's position was not recorded")
    }

    @Test("The next entry this device writes follows the spent one, rather than reusing its number")
    func theNextEntryFollowsTheSpentOne() throws {
        var (replica, author, _, deleted, entries) = try interleaved()
        replica.close(deleted)

        let top = try #require(replica.spentLink(atTopOf: author.feedKey))
        #expect(top == entries[5].link)

        let next = try Entry.append(
            after: top, author: author.identity.id, device: author.device,
            clock: replica.frontier, wallTime: start.addingTimeInterval(10), room: RoomID(),
            payload: try Payload.post("after"), at: .initial, sealedWith: author.chain)
        #expect(next.seq == 7)
        #expect(try replica.integrate(next) == .accepted)
        #expect(replica.forks.isEmpty)
    }

    @Test("A relaunch restores what was spent, so nothing reads as missing")
    func aRelaunchRestoresTheSpent() throws {
        var (replica, author, kept, deleted, entries) = try interleaved()
        replica.close(deleted)

        var relaunched = Replica()
        try relaunched.meet(author)
        relaunched.restore(spent: replica.spentEntries, closing: replica.closedRooms)
        for entry in entries where entry.room == kept { try relaunched.integrate(entry) }

        #expect(relaunched.gaps().isEmpty)
        #expect(relaunched.frontier == replica.frontier)
        #expect(relaunched.closedRooms == [deleted])
        for entry in entries where entry.room == deleted {
            #expect(try relaunched.integrate(entry) == .alreadyPresent)
        }
        #expect(relaunched.entries(in: deleted).isEmpty)
    }

    @Test("Reopening a room gives its positions back, so they can be filled again")
    func reopeningGivesPositionsBack() throws {
        var (replica, author, _, deleted, entries) = try interleaved()
        replica.close(deleted)

        replica.reopen(deleted)

        let missing = replica.gaps(from: [author.identity.id])
        #expect(missing.total == 3, "a reopened room's history cannot be asked for")
        for entry in entries where entry.room == deleted {
            #expect(try replica.integrate(entry) == .accepted)
        }
        #expect(replica.gaps().isEmpty)
        #expect(replica.spentEntries.isEmpty)
    }
}

@Suite("Taking a room's entries out of the log on disk", .serialized)
struct LogRemovalTests {
    @Test("Removing entries keeps every other entry, in order, across a reload")
    func removalKeepsTheRest() async throws {
        let url = URL.temporaryDirectory.appending(path: "carpenter-\(UUID().uuidString)/log.carpenter")
        let store = FileLogStore(url: url)
        var author = Author()
        let kept = RoomID()
        let deleted = RoomID()
        var entries: [Entry] = []
        for index in 0..<5 {
            entries.append(
                try author.append(
                    try Payload.post("\(index)"), at: Date(timeIntervalSince1970: Double(index)),
                    room: index == 1 || index == 3 ? deleted : kept))
        }
        try await store.append(entries)

        let removed = try await store.removeEntries { $0.room == deleted }

        #expect(removed == 2)
        let reloaded = try await FileLogStore(url: url).loadAll()
        #expect(reloaded.termination == .complete)
        #expect(reloaded.entries.map(\.hash) == entries.filter { $0.room == kept }.map(\.hash))

        let appended = try author.append(
            try Payload.post("after"), at: Date(timeIntervalSince1970: 10), room: kept)
        try await store.append([appended])
        #expect(try await store.loadAll().entries.last?.hash == appended.hash)
    }

    @Test("Removing nothing leaves the file alone")
    func removingNothingWritesNothing() async throws {
        let url = URL.temporaryDirectory.appending(path: "carpenter-\(UUID().uuidString)/log.carpenter")
        let store = FileLogStore(url: url)
        var author = Author()
        try await store.append([try author.post("kept", at: Date(timeIntervalSince1970: 0))])
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber]

        #expect(try await store.removeEntries { _ in false } == 0)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int == before as? Int)
    }
}
