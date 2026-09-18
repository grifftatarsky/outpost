@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A tag the app keeps")
struct ManagedTagTests {
    private let stamp = OrganisationStamp(
        at: Date(timeIntervalSince1970: 1_786_635_000), device: DeviceID(rawValue: WideID.of([1])))

    private func summary(_ id: RoomID, _ name: String) -> RoomSummary {
        RoomSummary(
            id: id, name: name, memberCount: 1, lastAuthor: nil, lastMessage: "",
            lastActivity: Date(timeIntervalSince1970: 1), hasUnread: false)
    }

    @Test("Its identifier is reserved, stable, and cannot collide with a member's")
    func theIdentifierIsReserved() {
        #expect(ManagedTagKind.invited.id == ManagedTagKind.invited.id)
        for _ in 0..<200 {
            #expect(TagID().rawValue != ManagedTagKind.invited.id.rawValue)
        }
    }

    @Test("Filtering by it shows the rooms it names, and no others")
    func filteringByAManagedTag() {
        let waiting = RoomID()
        let ordinary = RoomID()
        let organisation = RoomsListOrganisation()
        let invited = ManagedTag(kind: .invited, rooms: [waiting])

        let all = organisation.arrange(
            [summary(waiting, "Hangar"), summary(ordinary, "Lanterns")], managed: [invited])
        #expect(all.count == 2)

        let filtered = organisation.arrange(
            [summary(waiting, "Hangar"), summary(ordinary, "Lanterns")],
            filteredBy: ManagedTagKind.invited.id, managed: [invited])
        #expect(filtered.map(\.id) == [waiting])
    }

    @Test("A filter nothing answers to shows nothing, rather than everything")
    func anUnknownFilterShowsNothing() {
        let organisation = RoomsListOrganisation()
        let arranged = organisation.arrange(
            [summary(RoomID(), "Hangar")], filteredBy: ManagedTagKind.invited.id)
        #expect(arranged.isEmpty)
    }

    @Test("A member's own tag is unaffected")
    func memberTagsAreUnaffected() {
        let room = RoomID()
        let other = RoomID()
        var organisation = RoomsListOrganisation()
        let tag = organisation.addTag(named: "Work", stamp: stamp)
        organisation.setTag(tag, on: true, for: room, stamp: stamp)

        let filtered = organisation.arrange(
            [summary(room, "Hangar"), summary(other, "Lanterns")],
            filteredBy: tag, managed: [ManagedTag(kind: .invited, rooms: [other])])
        #expect(filtered.map(\.id) == [room])
    }

    @Test("It is not in the member's own tags, however it is drawn")
    func itIsNotFiledWithTheirs() {
        var organisation = RoomsListOrganisation()
        _ = organisation.addTag(named: "Work", stamp: stamp)
        _ = organisation.arrange([], managed: [ManagedTag(kind: .invited, rooms: [RoomID()])])

        #expect(organisation.tags.count == 1)
        #expect(organisation.orderedTags.allSatisfy { $0.id != ManagedTagKind.invited.id })
        #expect(organisation.rooms.isEmpty, "a managed tag filed itself against a room")
    }

    @Test("A managed tag with no rooms is not offered")
    func anEmptyOneIsNotOffered() {
        #expect(!ManagedTag(kind: .invited, rooms: []).isWorthShowing)
        #expect(ManagedTag(kind: .invited, rooms: [RoomID()]).isWorthShowing)
    }
}

@MainActor
@Suite("The Invited tag, through the session", .serialized)
struct SessionManagedTagTests {
    private func pair() async throws -> (
        alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox
    ) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        return (alice, bob, mailbox)
    }

    private func settle(
        _ everyone: [AppSession], _ mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox) }
        }
    }

    @Test("There is no tag until something is waiting")
    func nothingWaitingNoTag() async throws {
        let (alice, _, _) = try await pair()
        _ = try await alice.createRoom(named: "Hangar 7")
        #expect(alice.managedTags.isEmpty)
    }

    @Test("It names the inviter's room and the joiner's wait alike")
    func bothSides() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7", access: .founder)

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await settle([alice, bob], mailbox)

        let hers = try #require(alice.managedTags.first)
        #expect(hers.kind == .invited)
        #expect(hers.rooms == [room], "the inviter's room is not named")

        let his = try #require(bob.managedTags.first)
        #expect(his.rooms == [room], "the joiner's wait is not named")
        #expect(bob.rooms.isEmpty, "precondition: the joiner holds no room")
    }

    @Test("It goes when the join finishes")
    func itClears() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        try await join(bob, into: room, of: alice, through: mailbox)

        #expect(alice.roster(of: room).members.count == 2, "precondition: the join finished")
        #expect(alice.managedTags.isEmpty, "the tag outlived the join it was about")
        #expect(bob.managedTags.isEmpty)
    }

    @Test("It goes when the invitation is taken back")
    func rescindingClearsIt() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")

        let invite = try await alice.invite(
            joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await settle([alice], mailbox)
        #expect(!alice.managedTags.isEmpty, "precondition: it was outstanding")

        try await alice.rescind(invite.attestation)

        #expect(alice.managedTags.isEmpty)
    }

    @Test("It never reaches the member's own tags")
    func itIsNeverFiled() async throws {
        let (alice, bob, mailbox) = try await pair()
        let room = try await alice.createRoom(named: "Hangar 7")
        _ = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await settle([alice], mailbox)

        #expect(!alice.managedTags.isEmpty, "precondition: the tag exists")
        #expect(alice.organisation.tags.isEmpty, "the app filed a tag as though the member made it")
        #expect(
            alice.organisation.tags(of: room).isEmpty,
            "the app assigned a tag to a room on the member's behalf")
    }
}

@Suite("What the app's own filter says")
struct ManagedTagSummaryTests {
    @Test("It never leaves markup on the screen")
    func noMarkupEscapes() {
        for matching in [0, 1, 2, 17] {
            let line = TagFilterSummary.managedLine(matching: matching)
            #expect(!line.contains("inflect"), "\(matching): \(line)")
            #expect(!line.contains("^["), "\(matching): \(line)")
            #expect(!line.contains("%"), "\(matching): \(line)")
        }
    }

    @Test("Nothing waiting reads as nothing waiting")
    func nothingWaiting() {
        #expect(TagFilterSummary.managedLine(matching: 0).hasPrefix("Nothing is waiting"))
    }

    @Test("It says the app keeps it, and that it still goes nowhere")
    func itSaysWhoKeepsIt() {
        let line = TagFilterSummary.managedLine(matching: 2)
        #expect(line.contains("Kept by the app"))
        #expect(line.contains("only on your devices"))
    }
}
