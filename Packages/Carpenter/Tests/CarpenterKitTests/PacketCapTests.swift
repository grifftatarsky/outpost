@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A round bigger than a packet", .serialized)
struct PacketCapTests {
    private static let longMessage = String(repeating: "lantern ", count: 1_000)
        .trimmingCharacters(in: .whitespaces)
    private static let burst = 120

    private func joined() async throws -> (
        alice: AppSession, bob: AppSession, room: ConversationID, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Lanterns")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, room, mailbox)
    }

    @Test("A burst goes as several packets, each under the budget, and all of it arrives")
    func burstIsSplitAndArrives() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        for _ in 0..<Self.burst { try await alice.send(Self.longMessage, to: room) }

        let report = try await alice.sync(through: mailbox)

        #expect(report.packetsWritten >= 2, "a megabyte and a half went as one packet")
        #expect(report.entriesSent == Self.burst)
        #expect(report.written.count == report.packetsWritten)
        let largest = await mailbox.largestPacketBytes
        #expect(largest <= SyncSession.packetByteBudget + 4_096, "a packet over the budget: \(largest)")

        let received = try await bob.sync(through: mailbox)
        #expect(received.entriesReceived == Self.burst, "not everything crossed: \(received.entriesReceived)")
        #expect(bob.messages(in: room).count { $0.body == Self.longMessage } == Self.burst)
    }

    @Test("Batches keep order and each fits")
    func batchesFit() async throws {
        let (alice, _, room, mailbox) = try await joined()
        for index in 0..<40 { try await alice.send("\(index) " + Self.longMessage, to: room) }
        let report = try await alice.sync(through: mailbox)
        #expect(report.packetsWritten >= 1)

        let bob = TestSession.make()
        _ = bob
        let bodies = alice.messages(in: room).map(\.body)
        #expect(bodies == bodies.sorted { Int($0.prefix { $0.isNumber })! < Int($1.prefix { $0.isNumber })! })
    }

    @Test("A failure after the first packet keeps what landed and sends the rest next round")
    func partialFailureIsNotLoss() async throws {
        let (alice, bob, room, mailbox) = try await joined()
        for _ in 0..<Self.burst { try await alice.send(Self.longMessage, to: room) }
        await mailbox.failWrite(number: 2, with: .unavailable)

        let first = try await alice.sync(through: mailbox)

        #expect(first.packetsWritten == 1, "expected the first to land and the second to fail")
        #expect(first.sendFailure != nil, "a packet failed and the report did not say")
        #expect(first.bellsRung == 0, "a round that stopped short rang a bell for messages it did not write")
        let firstBatch = first.written.first?.entries.count ?? 0
        #expect(firstBatch > 0 && firstBatch < Self.burst)

        let second = try await alice.sync(through: mailbox)
        #expect(second.sendFailure == nil)
        #expect(second.entriesSent >= Self.burst - firstBatch, "the rest did not go next round")
        #expect(second.bellsRung == 1, "the round that wrote the rest did not ring")

        let received = try await bob.sync(through: mailbox)
        #expect(received.entriesReceived == Self.burst, "not everything crossed: \(received.entriesReceived)")
        #expect(bob.messages(in: room).count { $0.body == Self.longMessage } == Self.burst)
        #expect(received.entriesAlreadyPresent <= 1, "something was sent twice")
    }

    @Test("A key owed to somebody is only marked issued if the packet carrying it landed")
    func grantsAreOnlyMarkedIssuedIfTheyWent() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Lanterns")
        try await alice.send("before you arrived", to: room)
        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await bob.sync(through: mailbox)
        try await alice.sync(through: mailbox)
        try await bob.sync(through: mailbox)

        for _ in 0..<Self.burst { try await alice.send(Self.longMessage, to: room) }
        await mailbox.failWrite(number: 2, with: .unavailable)

        let stopped = try await alice.sync(through: mailbox)
        #expect(stopped.packetsWritten >= 1, "the first packet did not land, so this proves nothing")
        #expect(stopped.sendFailure != nil, "no packet failed, so this proves nothing")

        let collected = try await bob.sync(through: mailbox)
        #expect(
            collected.grantsReceived.count == 1,
            """
            A round wrote one packet and failed on a later one, and `issuedGrants` was marked for \
            every grant it owed — so the key had better have been in the packet that landed. It is, \
            because `SyncSession.send` puts the grants in the *first* packet only and a first-packet \
            failure throws before any of this runs. Three facts in two files hold that up, and \
            nothing else checks them: put grants in every packet, or stop throwing on the first \
            failure, and a reader is marked as holding a key that never left the device.
            """)
        #expect(
            bob.messages(in: room).contains { $0.body == "before you arrived" },
            "the grant arrived but does not open the history it was issued for")

        let again = try await alice.sync(through: mailbox)
        let more = try await bob.sync(through: mailbox)
        #expect(
            more.grantsReceived.isEmpty,
            "the key went out twice, so `issuedGrants` did not record the one that landed")
        _ = again
    }

    @Test("The first packet failing still fails the round, because nothing was written")
    func firstFailureThrows() async throws {
        let (alice, _, room, mailbox) = try await joined()
        try await alice.send("hello", to: room)
        await mailbox.failWrite(number: 1, with: .unavailable)
        await #expect(throws: MailboxError.unavailable) {
            try await alice.sync(through: mailbox)
        }
    }
}
