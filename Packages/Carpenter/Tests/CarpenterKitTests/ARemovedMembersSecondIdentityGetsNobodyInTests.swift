@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A removed member's second identity gets nobody in", .serialized, .timeLimit(.minutes(10)),
    .tags(.membership, .manyDevices))
struct ARemovedMembersSecondIdentityGetsNobodyInTests {
    static let stayers = ["Alice", "Bob", "Carol", "Dave"]

    @Test(
        "Erin, removed, invites a second identity of her own and nobody in the room ever shows Eve or hands her a key",
        arguments: [false, true], [false, true])
    func erinsSecondIdentityGetsNobodyIn(afterSheHears: Bool, reachesDaveBeforeTheRemoval: Bool) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin", "Eve")
        let room = try await g.room("Lanterns", host: "Alice", guests: ["Bob", "Carol", "Dave", "Erin"])
        let friends = ["Alice", "Bob", "Carol"]

        let before = Set(await g.cloud.writtenPackets)
        if reachesDaveBeforeTheRemoval { g.away("Dave") }
        if !afterSheHears { for stayer in Self.stayers { await g.door(stayer).cannotReach(g.id("Erin")) } }
        try await g["Alice"].remove(g.id("Erin"), from: room)
        await g.takeTurns(friends)
        if afterSheHears {
            for _ in 0..<4 where !heardOfTheRemoval(on: "Erin", in: room, g) { await g.takeTurns(friends + ["Erin"]) }
            try #require(heardOfTheRemoval(on: "Erin", in: room, g), "precondition: Erin heard she was removed")
        } else {
            try #require(!heardOfTheRemoval(on: "Erin", in: room, g), "precondition: Erin has not heard yet")
        }
        if !reachesDaveBeforeTheRemoval {
            await g.takeTurns("Dave")
            try #require(heardOfTheRemoval(on: "Dave", in: room, g), "precondition: Dave heard Erin was removed")
        }

        let erinsEntriesOnDave = entries(by: "Erin", on: "Dave", g)
        let beforeTheInvitation = Set(await g.cloud.writtenPackets)
        let evesCode = await g["Eve"].joinerCode(through: g.door("Eve"))
        if afterSheHears {
            try await invitationWrittenByAModifiedApp(for: evesCode, to: room, in: g)
        } else {
            let invite = try await g["Erin"].invite(joinerCode: evesCode, joining: room, through: g.door("Erin"))
            try await g["Eve"].redeem(inviteCode: try invite.encoded())
            await g.takeTurns("Erin", "Eve", "Erin", "Erin")
            try #require(
                g["Erin"].roster(of: room).hasConfirmed(invite.attestation),
                "precondition: Erin wrote down Eve's confirmation before she heard she was removed")
        }
        if reachesDaveBeforeTheRemoval {
            for id in await g.cloud.writtenPackets where !before.contains(id) {
                let toDave = await g.cloud.everySentPacket[id]?.to == g.id("Dave")
                let invitation = await g.cloud.sender(of: id) == g.id("Erin") && !beforeTheInvitation.contains(id)
                if toDave, !invitation { await g.door("Dave").skip(id) }
            }
            g.back("Dave")
        }
        await g.takeTurns("Dave")
        try #require(
            entries(by: "Erin", on: "Dave", g) > erinsEntriesOnDave, "precondition: Dave collected Erin's invitation")
        let when = reachesDaveBeforeTheRemoval ? "before" : "after"
        try #require(
            heardOfTheRemoval(on: "Dave", in: room, g) != reachesDaveBeforeTheRemoval,
            "precondition: Dave collected Erin's invitation \(when) the removal")

        for name in Self.stayers + ["Erin"] { await g.door(name).reachesEveryone() }
        try await g.settle()
        try await g["Alice"].send("after Eve was invited", to: room)
        try await g.settle()

        let four = Set(Self.stayers.map(g.id))
        g.sameRoom(room, on: Self.stayers)
        for viewer in Self.stayers {
            let roster = g[viewer].roster(of: room)
            #expect(roster.members == four, "\(viewer) does not show exactly Alice, Bob, Carol and Dave")
            #expect(!roster.members.contains(g.id("Eve")), "\(viewer) shows Eve in Lanterns")
            #expect(
                roster.pendingInvitations(at: g.clock(viewer).now).isEmpty, "\(viewer) shows an invitation still open")
            #expect(
                roster.pending(for: g.id(viewer), at: g.clock(viewer).now).isEmpty,
                "\(viewer) is asked to let somebody in")
            #expect(g.shows("after Eve was invited", in: room, on: viewer), "\(viewer) never read Alice's message")
        }
        withKnownIssue("Erin, not yet told, hands Eve every key to Lanterns she held before her removal") {
            #expect(g["Eve"].chains[room]?.heldKeyCount ?? 0 == 0, "Eve holds a key to Lanterns")
        } when: {
            !afterSheHears
        }
        #expect(!g.shows("after Eve was invited", in: room, on: "Eve"), "Eve read Alice's message")
        let alicesMessage = try #require(g.entry(saying: "after Eve was invited", in: room, on: "Alice"))
        if let evesChain = g["Eve"].chains[room] {
            #expect(alicesMessage.opened(using: evesChain) == nil, "Eve's keys open Alice's message")
        }
    }

    private func heardOfTheRemoval(on name: String, in room: RoomID, _ g: Gathering) -> Bool {
        g[name].roster(of: room).removal(of: g.id("Erin")) != nil
    }

    private func entries(by person: String, on name: String, _ g: Gathering) -> Int {
        g[name].replica.allEntries.count { $0.author == g.id(person) }
    }

    private func invitationWrittenByAModifiedApp(for code: String, to room: RoomID, in g: Gathering) async throws {
        let erin = g["Erin"]
        let enrolment = try #require(erin.enrolment)
        let chain = try #require(erin.chains[room])
        let now = g.clock("Erin").now
        let attestation = try MembershipAttestation.issue(
            joining: room, code: try JoinerCode.decoded(from: code), by: enrolment.identity, at: now)
        try await g["Eve"].redeem(inviteCode: try Invite(attestation: attestation).encoded())
        let confirmation = try JoinConfirmedBody.signed(
            confirming: attestation, opening: try #require(g["Eve"].nonce(opening: attestation.joinerCommitment)),
            by: try #require(g["Eve"].enrolment?.identity))
        let epoch = erin.writingKey(of: room)?.epoch ?? chain.highestKnownEpoch ?? .initial
        let request = try Entry.append(
            after: erin.head, author: enrolment.identity.id, device: enrolment.device, clock: erin.replica.frontier,
            wallTime: now, room: room, payload: try Payload.joinRequest(attestation), at: epoch, sealedWith: chain,
            roomLink: RoomLink(previous: erin.roomHeads[room]?.hash))
        let confirmed = try Entry.append(
            after: request.link, author: enrolment.identity.id, device: enrolment.device,
            clock: erin.replica.frontier, wallTime: now, room: room, payload: try Payload.joinConfirmed(confirmation),
            at: epoch, sealedWith: chain, roomLink: RoomLink(previous: request.hash))
        for stayer in Self.stayers {
            let them = g.id(stayer)
            let pairwise = try PairwiseSecret.derive(
                mine: enrolment.identity, theirs: try #require(erin.publicKeys(of: them)))
            let peer = Peer(secret: pairwise, them: them, me: enrolment.identity.id)
            try await g.cloud.put(
                try SyncEngine.pack([request, confirmed], for: [peer], window: SyncSession.window(at: g.iCloud.now)),
                to: them, in: Pairs(me: enrolment.identity.id, hints: [them: pairwise.pairHint]))
        }
    }
}
