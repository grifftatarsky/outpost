@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Everybody you could invite")
struct ConnectionTests {
    private func person(_ byte: UInt8, _ name: String) -> Member {
        Member(id: ParticipantID(rawValue: Data([byte])), displayName: name)
    }

    private func connections(
        rosters: [[Member]] = [], outposts: [Member] = [], viewer: Member,
        excluding: Set<ParticipantID> = []
    ) -> [Connection] {
        let everybody = (rosters.flatMap { $0 } + outposts + [viewer])
            .reduce(into: [ParticipantID: Member]()) { $0[$1.id] = $1 }
        return Connection.all(
            rosters: rosters.map { Set($0.map(\.id)) },
            outpostAuthors: outposts,
            viewer: viewer.id,
            excluding: excluding,
            naming: { everybody[$0] ?? Member(id: $0, displayName: "?") })
    }

    @Test("Somebody you share a room with is a connection")
    func roomMatesCount() {
        let me = person(1, "Me")
        let ada = person(2, "Ada")

        let found = connections(rosters: [[me, ada]], viewer: me)

        #expect(found.map(\.person.id) == [ada.id])
        #expect(found.first?.sharedRooms == 1)
        #expect(found.first?.seesTheirOutpost == false)
    }

    @Test("Somebody whose Outpost you can read is a connection even with no room in common")
    func outpostOnlyCounts() {
        let me = person(1, "Me")
        let bo = person(2, "Bo")

        let found = connections(outposts: [bo], viewer: me)

        #expect(found.map(\.person.id) == [bo.id])
        #expect(found.first?.sharedRooms == 0)
        #expect(found.first?.isOnlyByOutpost == true)
    }

    @Test("One person, however many rooms you share")
    func deduplicates() {
        let me = person(1, "Me")
        let ada = person(2, "Ada")

        let found = connections(
            rosters: [[me, ada], [me, ada], [me, ada]], outposts: [ada], viewer: me)

        #expect(found.count == 1)
        #expect(found.first?.sharedRooms == 3, "the count of shared rooms was lost in the union")
        #expect(found.first?.seesTheirOutpost == true)
    }

    @Test("You are never a connection to yourself")
    func excludesTheViewer() {
        let me = person(1, "Me")

        let found = connections(rosters: [[me]], outposts: [me], viewer: me)

        #expect(found.isEmpty)
    }

    @Test("Anybody already in the room is left out")
    func honoursExclusions() {
        let me = person(1, "Me")
        let ada = person(2, "Ada")
        let bo = person(3, "Bo")

        let found = connections(
            rosters: [[me, ada, bo]], viewer: me, excluding: [ada.id])

        #expect(found.map(\.person.id) == [bo.id])
    }

    @Test("Ordered the way a person reads a list of people")
    func ordering() {
        let me = person(1, "Me")
        let names = [person(2, "Zoë"), person(3, "alice"), person(4, "Bob")]

        let found = connections(rosters: [names + [me]], viewer: me)

        #expect(found.map(\.person.displayName) == ["alice", "Bob", "Zoë"])
    }

    @Test("Two people with the same name keep a stable order")
    func stableUnderDuplicateNames() {
        let me = person(1, "Me")
        let first = person(9, "Sam")
        let second = person(2, "Sam")

        let once = connections(rosters: [[me, first, second]], viewer: me).map(\.person.id)
        let again = connections(rosters: [[me, second, first]], viewer: me).map(\.person.id)

        #expect(once == again, "the same two people came back in a different order")
    }

    @Test("Searching finds a name, or the code shown on the row")
    func searching() {
        let me = person(1, "Me")
        let ada = person(2, "Ada")
        let unnamed = Member(
            id: ParticipantID(rawValue: WideID.of([0xAB, 0xCD])),
            displayName: ParticipantID(rawValue: WideID.of([0xAB, 0xCD])).shortCode)

        let all = connections(rosters: [[me, ada, unnamed]], viewer: me)

        #expect(all.matching("").count == 2, "a blank search hid people")
        #expect(all.matching("ad").map(\.person.id) == [ada.id])
        #expect(all.matching("ADA").map(\.person.id) == [ada.id], "search was case sensitive")
        #expect(
            all.matching(unnamed.displayName).map(\.person.id) == [unnamed.id],
            "somebody with no name could not be found by their code")
    }

    @Test("Sections are the letters, with everything else under a single last one")
    func sectioning() {
        let me = person(1, "Me")
        let people = [person(2, "Ada"), person(3, "alice"), person(4, "Bo"), person(5, "Zoë")]
        let code = Member(id: ParticipantID(rawValue: WideID.of([0x99])), displayName: "0C2F")

        let sections = connections(rosters: [[me] + people + [code]], viewer: me)
            .sectionedByInitial()

        #expect(sections.map(\.title) == ["A", "B", "Z", "#"])
        #expect(sections.first?.people.map(\.person.displayName) == ["Ada", "alice"])
        #expect(sections.last?.people.map(\.person.id) == [code.id], "a code was not filed under #")
    }

    @Test("A name starting with an accent is filed under its letter")
    func diacriticsFold() {
        let me = person(1, "Me")
        let sections = connections(rosters: [[me, person(2, "Émile")]], viewer: me)
            .sectionedByInitial()

        #expect(sections.map(\.title) == ["E"])
    }

    @Test("Nobody connected is an empty list, not a crash")
    func nobody() {
        let me = person(1, "Me")
        #expect(connections(viewer: me).isEmpty)
        #expect(connections(rosters: [[me]], viewer: me).isEmpty)
    }
}

@MainActor
@Suite("Everybody you could invite, asked of the session", .serialized)
struct SessionConnectionsTests {
    private func session() throws -> AppSession {
        TestSession.make()
    }

    @Test("Somebody you share a room with is offered, and you are not")
    func roomMateIsOffered() async throws {
        let alice = try session()
        let bob = try session()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        #expect(alice.connections().isEmpty, "a member who knows nobody was offered somebody")

        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        _ = try await alice.attest(
            code: JoinerCode(keys: bobKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: bobKeys))),
            joining: room)

        let found = alice.connections()
        #expect(found.map(\.person.id) == [bobKeys.participantID])
        #expect(found.first?.sharedRooms == 1)
        #expect(
            !found.contains { $0.person.id == alice.enrolment?.identity.id },
            "the viewer was offered an invitation to their own room")
    }

    @Test("Anybody already in the room is left out")
    func exclusionsApply() async throws {
        let alice = try session()
        let bob = try session()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let bobKeys = try #require(bob.enrolment?.identity.publicKeys)
        _ = try await alice.attest(
            code: JoinerCode(keys: bobKeys, commitment: JoinCommitment.of(TestInvite.nonce(for: bobKeys))),
            joining: room)

        #expect(alice.connections().count == 1)
        #expect(alice.connections(excluding: [bobKeys.participantID]).isEmpty)
    }

    @Test("Everybody offered has keys the app can invite them with")
    func everybodyOfferedIsInvitable() async throws {
        let alice = try session()
        let bob = try session()
        await alice.load()
        await bob.load()
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")

        let room = try await alice.createRoom(named: "Hangar 7")
        let keys = try #require(bob.enrolment?.identity.publicKeys)
        _ = try await alice.attest(
            code: JoinerCode(keys: keys, commitment: JoinCommitment.of(TestInvite.nonce(for: keys))),
            joining: room)

        for connection in alice.connections() {
            #expect(
                alice.publicKeys(of: connection.person.id) != nil,
                "\(connection.person.displayName) could be picked and could not be invited")
        }
    }
}
