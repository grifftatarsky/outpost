import CarpenterApp
import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("Ringing a bell", .serialized)
@MainActor
struct MessageBellTests {
    private func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "carpenter-bell-\(UUID().uuidString)")
    }

    private func session(_ clock: TestClock) throws -> AppSession {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return AppSession(
            storage: SessionStorage(
                keychain: InMemoryKeychainStore(),
                log: FileLogStore(url: directory.appending(path: "log.carpenter")),
                documents: FileDocumentStore(url: directory.appending(path: "state.json"))
            ),
            clock: clock
        )
    }

    private func pairInARoom(
        _ clock: TestClock, _ mailbox: InMemoryMailbox
    ) async throws -> (alice: AppSession, bob: AppSession, room: ConversationID) {
        let alice = try session(clock)
        let bob = try session(clock)
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        await alice.optIntoNames()
        try await bob.createIdentity(displayName: "Bob")
        await bob.optIntoNames()

        let room = try await alice.createRoom(named: "Hangar 7")
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())

        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)
        return (alice, bob, room)
    }

    @Test("Sending a message rings the recipient")
    func messageRings() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, room) = try await pairInARoom(clock, mailbox)

        let before = await mailbox.bells.count
        try await alice.send("are you coming", to: room)
        let report = try await alice.sync(through: mailbox)
        let after = await mailbox.bells.count

        #expect(report.bellsRung == 1, "a message was sent and nobody was told")
        #expect(after == before + 1)
    }

    @Test("Grants, renames, reactions and profiles ring nobody")
    func plumbingIsSilent() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, room) = try await pairInARoom(clock, mailbox)

        let before = await mailbox.bells.count

        try await alice.setDisplayName("Alice Liddell")
        let renamed = try await alice.sync(through: mailbox)
        #expect(renamed.packetsWritten > 0, "precondition: the rename actually went out")

        _ = try await alice.createRoom(named: "Quiet Room")
        try await alice.sync(through: mailbox)

        let after = await mailbox.bells.count
        #expect(
            after == before,
            "\(after - before) notification(s) for something nobody said — the original defect")
        _ = room
    }

    @Test("Collecting and acknowledging a message rings nobody")
    func acknowledgementRingsNobody() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, bob, room) = try await pairInARoom(clock, mailbox)

        try await alice.send("are you coming", to: room)
        try await alice.sync(through: mailbox)

        let before = await mailbox.bells.count
        let acknowledgements = await mailbox.acknowledgeCount
        let collected = try await bob.sync(through: mailbox)
        let after = await mailbox.bells.count

        #expect(collected.entriesReceived > 0, "precondition: Bob actually collected the message")
        #expect(
            await mailbox.acknowledgeCount > acknowledgements,
            "precondition: collecting really did acknowledge, which is the write in question")
        #expect(after == before, "acknowledging a message announced it to somebody")
    }

    @Test("One message rings each peer exactly once")
    func oneRingPerPeer() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, room) = try await pairInARoom(clock, mailbox)

        try await alice.send("first", to: room)
        let first = try await alice.sync(through: mailbox)
        #expect(first.bellsRung == 1)

        let second = try await alice.sync(through: mailbox)
        #expect(second.bellsRung == 0, "an idle sync re-announced a message already delivered")

        try await alice.send("second", to: room)
        let third = try await alice.sync(through: mailbox)
        #expect(third.bellsRung == 1)
    }

    @Test("A message rings the room's members, not everyone the packet reached")
    func ringsOnlyTheRoom() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, shared) = try await pairInARoom(clock, mailbox)

        let private_ = try await alice.createRoom(named: "Just Me")
        try await alice.sync(through: mailbox)

        try await alice.send("talking to myself", to: private_)
        let alone = try await alice.sync(through: mailbox)
        #expect(
            alone.packetsWritten > 0, "precondition: the entry went out in a packet Bob receives")
        #expect(alone.bellsRung == 0, "a member outside the room was notified about it")

        try await alice.send("talking to you", to: shared)
        let together = try await alice.sync(through: mailbox)
        #expect(together.bellsRung == 1)
    }

    @Test("A room whose roster names nobody still rings the people in it")
    func ringsWhenTheRosterIsEmpty() async throws {
        let clock = TestClock(now: TestSession.now)
        let mailbox = InMemoryMailbox()
        let (alice, _, room) = try await pairInARoom(clock, mailbox)

        try await alice.send("can you hear me", to: room)
        let report = try await alice.sync(through: mailbox)

        #expect(
            report.bellsRung >= 1,
            "a message went out with nobody rung — delivered, and silent")
    }

    @Test("A bell name is stable, shared by both ends, and different per direction")
    func bellNaming() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()

        let aliceToBob = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)
        let bobToAlice = try PairwiseSecret.derive(mine: bob, theirs: alice.publicKeys)
        let aliceToCarol = try PairwiseSecret.derive(mine: alice, theirs: carol.publicKeys)

        #expect(aliceToBob.bellName(for: bob.id) == bobToAlice.bellName(for: bob.id))
        #expect(aliceToBob.bellName(for: alice.id) == bobToAlice.bellName(for: alice.id))

        #expect(aliceToBob.bellName(for: bob.id) != aliceToBob.bellName(for: alice.id))

        #expect(aliceToBob.bellName(for: bob.id) != aliceToCarol.bellName(for: carol.id))

        #expect(aliceToBob.bellName(for: bob.id) == aliceToBob.bellName(for: bob.id))

        let name = aliceToBob.bellName(for: bob.id)
        #expect(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(name.count < 64)
    }
}
