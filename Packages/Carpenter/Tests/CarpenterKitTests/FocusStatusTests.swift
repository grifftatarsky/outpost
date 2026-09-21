@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("Sharing Do Not Disturb", .serialized)
struct FocusStatusTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: ConversationID) {
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
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        try await settle(alice, bob, mailbox)
        return (alice, bob, mailbox, room)
    }

    private func settle(_ a: AppSession, _ b: AppSession, _ mailbox: InMemoryMailbox) async throws {
        for _ in 0..<2 {
            try await a.sync(through: mailbox)
            try await b.sync(through: mailbox)
        }
    }

    @Test("Silence reaches a peer only where it is shared and shown")
    func sharedAndShown() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)

        await alice.reportFocus(silenced: true)
        try await settle(alice, bob, mailbox)
        #expect(alice.isSilenced)
        #expect(bob.focusStatus(of: aliceID) == nil, "nothing is said while sharing is off")

        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID) == nil, "and nothing is drawn while showing is off")

        await bob.setFocusSharing(FocusSharing(showsOthersFocus: true))
        let status = try #require(bob.focusStatus(of: aliceID))
        #expect(status.silenced && status.message == nil, "the stock words")

        await alice.reportFocus(silenced: false)
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID) == nil, "a Focus that ended is not a line")
    }

    @Test("A custom message travels, cut to a line, and changing it while silenced says it again")
    func customMessage() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.setFocusSharing(FocusSharing(showsOthersFocus: true))
        await alice.setFocusSharing(
            FocusSharing(sharesFocus: true, usesCustomMessage: true, customMessage: "  Heads down till six  "))
        await alice.reportFocus(silenced: true)
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID)?.message == "Heads down till six")

        let long = String(repeating: "x", count: 200)
        await alice.setFocusSharing(
            FocusSharing(sharesFocus: true, usesCustomMessage: true, customMessage: long))
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID)?.message?.count == FocusStatusBody.messageLimit)

        await alice.setFocusSharing(FocusSharing(sharesFocus: true, usesCustomMessage: false, customMessage: long))
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID)?.message == nil, "off, the stock words again")
    }

    @Test("Turning sharing off ends the silence for everybody who was told")
    func sharingOffClears() async throws {
        let (alice, bob, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await bob.setFocusSharing(FocusSharing(showsOthersFocus: true))
        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        await alice.reportFocus(silenced: true)
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID) != nil)

        await alice.setFocusSharing(FocusSharing(sharesFocus: false))
        try await settle(alice, bob, mailbox)
        #expect(bob.focusStatus(of: aliceID) == nil)
        #expect(alice.isSilenced, "the device's own state is untouched; only what is said changed")
    }

    @Test("A room made during a silence is told of it")
    func lateRoomIsTold() async throws {
        let (alice, _, mailbox, _) = try await joined()
        let aliceID = try #require(alice.enrolment?.identity.id)
        await alice.setFocusSharing(FocusSharing(sharesFocus: true))
        await alice.reportFocus(silenced: true)
        try await alice.sync(through: mailbox)

        let later = try await alice.createRoom(named: "Kitchen")
        #expect(alice.lastFocusStatus(of: aliceID, in: later)?.silenced == true)
    }

    @Test("A status body never carries words for a silence that is over")
    func bodyShape() {
        #expect(FocusStatusBody(silenced: false, message: "Back soon").message == nil)
        #expect(FocusStatusBody(silenced: true, message: "   ").message == nil)
        #expect(FocusStatusBody(silenced: true, message: String(repeating: "a", count: 80)).message?.count == 60)
    }
}

@Suite("A Focus filter")
struct FocusFilterTests {
    @Test("The neutral filter lets everything through and is stored as nothing")
    func neutral() {
        let defaults = UserDefaults(suiteName: "focus-\(UUID().uuidString)")!
        let store = FocusFilterStore(defaults: defaults)
        let room = ConversationID.room(UUID())
        #expect(store.read().isNeutral)
        #expect(store.read().level(for: room, own: .everything) == .everything)

        store.write(FocusFilter(rooms: [room], showsPreviews: false))
        let filter = store.read()
        #expect(filter.allows(room))
        #expect(!filter.allows(ConversationID.room(UUID())))
        #expect(filter.level(for: room, own: .everything) == .whoAndWhere, "no previews caps the level")
        #expect(filter.level(for: room, own: .whereOnly) == .whereOnly, "and leaves a quieter one alone")
        #expect(filter.level(for: ConversationID.room(UUID()), own: .everything) == .nothing, "a room the Focus left out says nothing")

        store.write(FocusFilter())
        #expect(store.read().isNeutral, "the Focus turning off writes the defaults, which clear it")
    }

    @Test("The room directory round-trips")
    func directory() {
        let defaults = UserDefaults(suiteName: "focus-\(UUID().uuidString)")!
        let store = FocusFilterStore(defaults: defaults)
        let rooms = [FocusFilterStore.RoomEntry(id: ConversationID.room(UUID()), name: "Lanterns"), FocusFilterStore.RoomEntry(id: ConversationID.room(UUID()), name: "Kitchen")]
        store.writeRooms(rooms)
        #expect(store.rooms() == rooms)
    }
}
