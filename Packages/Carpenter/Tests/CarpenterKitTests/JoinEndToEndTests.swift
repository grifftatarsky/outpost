import Foundation
import Testing

@testable import CarpenterKit
@testable import CarpenterKitTesting

@Suite("A fourth member joins")
struct JoinEndToEndTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private struct Resident {
        var author: Author
        var replica = Replica()
        var roster: RoomRoster
        var chain: EpochChain

        var id: ParticipantID { author.identity.id }
    }

    private func room() throws -> (RoomID, EpochSecret, EpochChain) {
        let id = RoomID()
        let (chain, secret) = EpochChain.create(room: id)
        return (id, secret, chain)
    }

    private func confirm(
        _ attestation: MembershipAttestation, by joiner: Identity,
        relayedBy relay: Int, to residents: inout [Resident], at when: Date
    ) throws {
        let payload = try Payload.joinConfirmed(
            try JoinConfirmedBody.signed(confirming: attestation, by: joiner))
        let entry = try residents[relay].author.append(payload, at: when, room: attestation.room)
        try broadcast(entry, payload, to: &residents)
    }

    private func broadcast(
        _ entry: Entry, _ payload: Payload, to residents: inout [Resident]
    ) throws {
        for index in residents.indices {
            try residents[index].replica.integrate(entry)
            let rendered = Fold.render([entry], using: residents[index].chain)
            if let first = rendered.first {
                residents[index].roster.apply(first, body: payload)
            }
        }
    }

    @Test("Alice, Bob and Carol each verify Dave's attestation for themselves")
    func fourthMemberJoins() throws {
        let (roomID, founding, chain) = try room()

        var alice = Resident(
            author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain)
        var bob = Resident(
            author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain)
        var carol = Resident(
            author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain)
        var dave = Resident(
            author: Author(chain: EpochChain(room: roomID)), roster: RoomRoster(room: roomID),
            chain: EpochChain(room: roomID))

        var residents = [alice, bob, carol, dave]
        for index in residents.indices {
            for other in residents { try residents[index].replica.meet(other.author) }
        }

        let named = try residents[0].author.append(
            Payload.roomProfile(name: "Hangar 7"), at: start, room: roomID)
        try broadcast(named, try Payload.roomProfile(name: "Hangar 7"), to: &residents)

        for joiner in [1, 2] {
            let invite = try TestInvite.issue(
                joining: roomID,
                joinerKeys: residents[joiner].author.identity.publicKeys,
                by: residents[0].author.identity,
                at: start)
            let request = try Payload.joinRequest(invite)
            let requested = try residents[0].author.append(request, at: start, room: roomID)
            try broadcast(requested, request, to: &residents)

            try confirm(
                invite, by: residents[joiner].author.identity,
                relayedBy: 0, to: &residents, at: start)
        }

        let strict = try Payload.roomAccess(.unanimous)
        let strictEntry = try residents[0].author.append(strict, at: start, room: roomID)
        try broadcast(strictEntry, strict, to: &residents)

        for index in 0..<3 {
            #expect(residents[index].roster.members.count == 3, "tightening evicted somebody")
        }

        let secret = try Payload.post("door code changed again")
        let posted = try residents[0].author.append(secret, at: start.addingTimeInterval(60), room: roomID)
        try broadcast(posted, secret, to: &residents)

        let attestation = try TestInvite.issue(
            joining: roomID,
            joinerKeys: residents[3].author.identity.publicKeys,
            by: residents[0].author.identity,
            at: start.addingTimeInterval(120)
        )

        let request = try Payload.joinRequest(attestation)
        let requestEntry = try residents[0].author.append(
            request, at: start.addingTimeInterval(180), room: roomID)
        try broadcast(requestEntry, request, to: &residents)

        try confirm(
            attestation, by: residents[3].author.identity,
            relayedBy: 0, to: &residents, at: start.addingTimeInterval(190))

        var verifiedBy: [ParticipantID] = []
        for index in 0..<3 {
            #expect(residents[index].roster.pending(for: residents[index].id, at: start).count == 1)

            try residents[index].roster.verify(
                attestation,
                inviterKeys: residents[0].author.identity.publicKeys,
                at: start.addingTimeInterval(200)
            )
            verifiedBy.append(residents[index].id)

            let admission = try Payload.admission(of: residents[3].id, admitted: true)
            let entry = try residents[index].author.append(
                admission, at: start.addingTimeInterval(240), room: roomID)
            try broadcast(entry, admission, to: &residents)
        }

        #expect(verifiedBy.count == 3)
        #expect(Set(verifiedBy).count == 3)

        for index in 0..<4 {
            let seen = residents[index].roster.members
            #expect(
                seen.contains(residents[3].id),
                "member \(index) does not see the joiner")
        }
        #expect(residents[0].roster.isUnanimous(residents[3].id))

        alice = residents[0]
        bob = residents[1]
        carol = residents[2]
        dave = residents[3]
        _ = (alice, bob, carol)

        let advanced = try EpochChain.advance(from: founding, at: .initial, room: roomID)
        var daveChain = EpochChain(room: roomID)
        daveChain.adopt(advanced.secret, at: .initial.next)
        try daveChain.record(advanced.link)

        let history = Fold.render(dave.replica.entries(in: roomID), using: daveChain)
        let texts = history.compactMap { entry -> String? in
            if case .text(let value) = entry.content { return value }
            return nil
        }

        #expect(texts.contains("door code changed again"))
    }

    @Test("One member refusing withholds their keys without splitting the roster")
    func aRefusalIsLoud() throws {
        let (roomID, _, chain) = try room()

        var residents = [
            Resident(author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain),
            Resident(author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain),
            Resident(author: Author(chain: chain), roster: RoomRoster(room: roomID), chain: chain),
        ]
        for index in residents.indices {
            for other in residents { try residents[index].replica.meet(other.author) }
        }

        let named = try residents[0].author.append(
            Payload.roomProfile(name: "Hangar 7"), at: start, room: roomID)
        try broadcast(named, try Payload.roomProfile(name: "Hangar 7"), to: &residents)

        let admitBob = try Payload.admission(of: residents[1].id, admitted: true)
        try broadcast(
            try residents[0].author.append(admitBob, at: start, room: roomID), admitBob,
            to: &residents)

        let attestation = try TestInvite.issue(
            joining: roomID, joinerKeys: residents[2].author.identity.publicKeys,
            by: residents[0].author.identity, at: start)
        let request = try Payload.joinRequest(attestation)
        try broadcast(
            try residents[2].author.append(request, at: start.addingTimeInterval(10), room: roomID),
            request, to: &residents)
        try confirm(
            attestation, by: residents[2].author.identity,
            relayedBy: 0, to: &residents, at: start.addingTimeInterval(15))

        let yes = try Payload.admission(of: residents[2].id, admitted: true)
        try broadcast(
            try residents[0].author.append(yes, at: start.addingTimeInterval(20), room: roomID),
            yes, to: &residents)

        let no = try Payload.admission(of: residents[2].id, admitted: false)
        try broadcast(
            try residents[1].author.append(no, at: start.addingTimeInterval(30), room: roomID),
            no, to: &residents)

        for resident in residents {
            #expect(resident.roster.members.contains(residents[2].id))
        }

        #expect(residents[0].roster.rewrapTargets(of: residents[0].id).contains(residents[2].id))
        #expect(!residents[1].roster.rewrapTargets(of: residents[1].id).contains(residents[2].id))

        for resident in residents {
            #expect(resident.roster.whoRefused(residents[2].id) == [residents[1].id])
            #expect(!resident.roster.isUnanimous(residents[2].id))
        }
    }
}
