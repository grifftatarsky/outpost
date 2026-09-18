import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterApp
@testable import CarpenterKit

private actor GatedDocumentStore: DocumentStore {
    private var held: Data?
    private var gateIsArmed = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var released = false

    private(set) var writes: [Data] = []

    func arm() {
        gateIsArmed = true
        released = false
    }

    func release() {
        released = true
        waiting?.resume()
        waiting = nil
    }

    func load<Value: Decodable & Sendable>(_ type: Value.Type) async throws -> Value? {
        guard let held else { return nil }
        return try JSONDecoder().decode(Value.self, from: held)
    }

    func save(_ value: some Encodable & Sendable) async throws {
        let encoded = try JSONEncoder().encode(value)
        if gateIsArmed {
            gateIsArmed = false
            if !released {
                await withCheckedContinuation { waiting = $0 }
            }
        }
        held = encoded
        writes.append(encoded)
    }

    func clear() async throws {
        held = nil
    }

    func lastWritten() throws -> PersistedState? {
        guard let last = writes.last else { return nil }
        return try JSONDecoder().decode(PersistedState.self, from: last)
    }
}

@Suite("Arranging the rooms list does not roll back what else was written", .serialized)
@MainActor
struct ArrangingRoomsDoesNotRollBackTests {
    @Test("A save that started before another change still writes the change")
    func arrangingDoesNotClobberALaterChange() async throws {
        let documents = GatedDocumentStore()
        let session = AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(), log: MemoryLogStore(), documents: documents,
                media: MemoryMediaStore()),
            clock: TestClock(now: TestSession.now))
        await session.load()
        try await session.createIdentity(displayName: "Griff")
        let room = try await session.createRoom(named: "Kitchen")
        let somebody = ParticipantID(rawValue: Data(repeating: 7, count: 32))

        await documents.arm()
        session.updateOrganisation {
            $0.rooms[room] = RoomOrganisation(pin: Stamped(1, stamp: session.stamp()))
        }
        await Task.yield()

        let naming = Task { await session.setNickname("Outie", for: somebody) }
        await Task.yield()
        await documents.release()
        await naming.value
        await Task.yield()

        let written = try #require(try await documents.lastWritten())
        #expect(
            written.organisation.isPinned(room),
            "the pin never reached the file at all")
        #expect(
            written.preferences.nickname(for: somebody) == "Outie",
            """
            A nickname set while the rooms list was being saved was rolled back on disk. \
            `updateOrganisation` used to capture the whole `PersistedState` and hand the copy to a \
            detached save, so anything written between the capture and the write — a sync round's \
            frontier, an acknowledgement, a preference — was overwritten by the older copy. The \
            copy-modify-write trap, one layer down: the actor is free across the `await` inside \
            `save`, and what runs there is the rest of the app.
            """)
    }
}
