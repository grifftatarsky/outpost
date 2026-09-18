import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@MainActor
@Suite("A room that grows", .serialized)
struct MembersOverTimeTests {
    private func member(_ name: String, at directory: URL? = nil, keychain: InMemoryKeychainStore = InMemoryKeychainStore(), media: MemoryMediaStore = MemoryMediaStore()) async throws -> AppSession {
        let session = TestSession.make(keychain: keychain, at: directory, media: media)
        await session.load()
        try await session.createIdentity(displayName: name)
        return session
    }

    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func admit(
        _ joiner: AppSession, to room: RoomID, by inviter: AppSession,
        alongside everyone: [AppSession], through mailbox: InMemoryMailbox
    ) async throws {
        let invite = try await inviter.invite(
            joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
        try await joiner.redeem(inviteCode: try invite.encoded())
        try await settle(everyone + [joiner], through: mailbox)
    }

    @Test("Everybody who joins gets the whole room, whenever they arrived")
    func fourMembersEndUpWithTheSameRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member("Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")
        let dave = try await member("Dave")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("before anybody", to: room)
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)

        try await bob.send("before Carol", to: room)
        try await settle([alice, bob], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)

        try await carol.send("before Dave", to: room)
        try await settle([alice, bob, carol], through: mailbox)
        try await admit(dave, to: room, by: bob, alongside: [alice, bob, carol], through: mailbox)

        try await dave.send("everybody is here", to: room)
        try await settle([alice, bob, carol, dave], through: mailbox)

        let expected = ["before anybody", "before Carol", "before Dave", "everybody is here"]
        for (name, session) in [("Alice", alice), ("Bob", bob), ("Carol", carol), ("Dave", dave)] {
            let said = session.messages(in: room).map(\.body)
            for words in expected {
                #expect(said.contains(words), "\(name) is missing \"\(words)\"")
            }
            #expect(
                session.roster(of: room).members.count == 4,
                "\(name) sees \(session.roster(of: room).members.count) members, not four")
            #expect(
                session.rooms.contains { $0.id == room && $0.name == "Hangar 7" },
                "\(name) cannot read the room's own name")
            #expect(session.missingHistory(in: room).isEmpty, "\(name) is missing entries")
        }
    }

    @Test("The last to arrive can still read the first thing anybody said")
    func theLastToArriveReadsTheFounding() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member("Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")
        let dave = try await member("Dave")

        let room = try await alice.createRoom(named: "Lanterns")
        try await alice.send("the founding words", to: room)
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try await admit(dave, to: room, by: alice, alongside: [alice, bob, carol], through: mailbox)

        #expect(dave.messages(in: room).map(\.body).contains("the founding words"))
        #expect(dave.rooms.contains { $0.id == room && $0.name == "Lanterns" })
    }

    @Test("Everybody still holds the room after a relaunch")
    func everybodySurvivesARelaunch() async throws {
        let mailbox = InMemoryMailbox()
        var directories: [String: URL] = [:]
        var keychains: [String: InMemoryKeychainStore] = [:]
        var stores: [String: MemoryMediaStore] = [:]
        func scratch(_ name: String) -> URL {
            let url = URL.temporaryDirectory.appending(path: "carpenter-grow-\(name)-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            directories[name] = url
            keychains[name] = InMemoryKeychainStore()
            stores[name] = MemoryMediaStore()
            return url
        }

        let alice = try await member(
            "Alice", at: scratch("alice"), keychain: keychains["alice"]!, media: stores["alice"]!)
        let bob = try await member(
            "Bob", at: scratch("bob"), keychain: keychains["bob"]!, media: stores["bob"]!)
        let carol = try await member(
            "Carol", at: scratch("carol"), keychain: keychains["carol"]!, media: stores["carol"]!)

        let room = try await alice.createRoom(named: "Hangar 7")
        try await alice.send("first", to: room)
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await bob.send("second", to: room)
        try await settle([alice, bob], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        for name in ["alice", "bob", "carol"] {
            let again = TestSession.make(
                keychain: keychains[name]!, at: directories[name]!, media: stores[name]!)
            await again.load()
            let said = again.messages(in: room).map(\.body)
            #expect(said.contains("first"), "\(name) lost the founding words to a relaunch")
            #expect(said.contains("second"), "\(name) lost a message to a relaunch")
            #expect(again.roster(of: room).members.count == 3, "\(name) lost the roster")
            #expect(
                again.rooms.contains { $0.id == room && $0.name == "Hangar 7" },
                "\(name) could not read the room's name after a relaunch — the links did not rebuild")
        }
    }

    @Test("A photo sent once everybody is here reaches everybody")
    func aPhotoReachesTheWholeRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member("Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")

        let room = try await alice.createRoom(named: "Darkroom")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)

        try await alice.send(SendingPhotoTests.photo(caption: "all three"), to: room, through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        for (name, session) in [("Bob", bob), ("Carol", carol)] {
            let theirs = try #require(
                session.messages(in: room).first { $0.media != nil }, "\(name) has no photo")
            let media = try #require(theirs.media)
            #expect(theirs.body == "all three")
            #expect(await session.holdsAttachment(media.id), "\(name) has the entry and not the bytes")
        }
    }

    @Test("A photo from before you joined arrives as a photo, and answers about its bytes")
    func aPhotoFromBeforeYouJoined() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member("Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")

        let room = try await alice.createRoom(named: "Darkroom")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await alice.send(SendingPhotoTests.photo(caption: "before Carol"), to: room, through: mailbox)
        try await settle([alice, bob], through: mailbox)

        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        let theirs = try #require(carol.messages(in: room).first { $0.media != nil })
        #expect(theirs.body == "before Carol", "the entry did not reach the late joiner")
        #expect(carol.missingHistory(in: room).isEmpty)

        let media = try #require(theirs.media)
        #expect(
            await carol.holdsAttachment(media.id) == false,
            "precondition: the outbox let the bytes go once Bob had them")
        let bytes = try await carol.attachmentData(
            for: media, sentBy: theirs.author.id, through: mailbox)
        #expect(bytes == nil, "a late joiner got something other than a plain answer")
    }

    @Test("Somebody removed stops receiving, and the two who stay carry on")
    func removalWithThreeInTheRoom() async throws {
        let mailbox = InMemoryMailbox()
        let alice = try await member("Alice")
        let bob = try await member("Bob")
        let carol = try await member("Carol")

        let room = try await alice.createRoom(named: "Hangar 7")
        try await admit(bob, to: room, by: alice, alongside: [alice], through: mailbox)
        try await admit(carol, to: room, by: alice, alongside: [alice, bob], through: mailbox)
        try await alice.send("while all three", to: room)
        try await settle([alice, bob, carol], through: mailbox)
        #expect(carol.messages(in: room).map(\.body).contains("while all three"))

        let carolID = try #require(carol.enrolment?.identity.id)
        try await alice.remove(carolID, from: room)
        try await settle([alice, bob, carol], through: mailbox)

        try await alice.send("after Carol went", to: room)
        try await settle([alice, bob, carol], through: mailbox)

        #expect(bob.messages(in: room).map(\.body).contains("after Carol went"), "Bob lost the room")
        #expect(
            !carol.messages(in: room).map(\.body).contains("after Carol went"),
            "a removed member went on reading the room")
        #expect(carol.messages(in: room).map(\.body).contains("while all three"))
    }
}

@MainActor
@Suite("Who a device writes to", .serialized)
struct AddressedPeersTests {
    private func settle(
        _ everyone: [AppSession], through mailbox: InMemoryMailbox, rounds: Int = 6
    ) async throws {
        for _ in 0..<rounds {
            for session in everyone { try await session.sync(through: mailbox, media: mailbox) }
        }
    }

    private func joinRoom(
        _ joiner: AppSession, to room: RoomID, by inviter: AppSession,
        through mailbox: InMemoryMailbox
    ) async throws {
        let invite = try await inviter.invite(
            joinerCode: joiner.identityCode(), joining: room, mailbox: nil)
        try await joiner.redeem(inviteCode: try invite.encoded())
        for _ in 0..<4 {
            try await inviter.sync(through: mailbox)
            try await joiner.sync(through: mailbox)
        }
    }

    @Test("A friend of a friend is somebody this device never writes to")
    func theClosureIsNotAddressed() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        let carol = TestSession.make()
        for one in [alice, bob, carol] { await one.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        try await carol.createIdentity(displayName: "Carol")

        let ours = try await alice.createRoom(named: "Lanterns")
        try await joinRoom(bob, to: ours, by: alice, through: mailbox)
        let theirs = try await bob.createRoom(named: "Hangar 7")
        try await joinRoom(carol, to: theirs, by: bob, through: mailbox)
        try await settle([alice, bob, carol], through: mailbox)

        try await bob.send("said in theirs", to: theirs)
        try await settle([alice, bob, carol], through: mailbox)
        #expect(carol.messages(in: theirs).map(\.body).contains("said in theirs"),
            "precondition: the rooms themselves work")

        let before = Set(await mailbox.writtenPackets)
        try await alice.send("said in our room", to: ours)
        try await alice.sync(through: mailbox)
        let waiting = try await mailbox.pendingDeliveries()
        let fresh = await mailbox.writtenPackets.filter { !before.contains($0) }
        #expect(fresh.count == 1, "precondition: Alice's round wrote exactly one packet")
        let recipients = try #require(fresh.first.flatMap { waiting[$0] })
        #expect(
            recipients.count == 1,
            "Alice addressed somebody she has never met — every entry she writes reaches them")

        try await settle([alice, bob, carol], through: mailbox)
        #expect(bob.messages(in: ours).map(\.body).contains("said in our room"))
        #expect(
            !carol.rooms.contains { $0.id == ours },
            "a room Carol is not in appeared on her device")
        #expect(
            !alice.connections().contains { $0.person.id == carol.enrolment?.identity.id },
            "somebody Alice has never met was offered as a connection")
    }
}
