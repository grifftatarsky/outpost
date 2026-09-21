import Foundation
import Testing
import CarpenterKitTesting

@testable import CarpenterKit

@Suite("Membership attestations")
struct MembershipAttestationTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    @Test("An attestation verifies under the inviter's keys")
    func issueAndVerify() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        #expect(attestation.joiner == joiner.id)
        #expect(attestation.inviter == inviter.id)
        try attestation.verify(against: inviter.publicKeys, at: start)
    }

    @Test("It does not verify under anybody else's keys")
    func wrongInviter() throws {
        let inviter = Identity.generate()
        let impostor = Identity.generate()
        let joiner = Identity.generate()

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        #expect(throws: MembershipError.wrongInviter) {
            try attestation.verify(against: impostor.publicKeys, at: start)
        }
    }

    @Test("An expired attestation is refused")
    func expiry() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start, lifetime: 3_600)

        try attestation.verify(against: inviter.publicKeys, at: start.addingTimeInterval(3_599))
        #expect(throws: MembershipError.expired) {
            try attestation.verify(against: inviter.publicKeys, at: start.addingTimeInterval(3_601))
        }
    }

    @Test("Swapping the joiner's keys for someone else's breaks it")
    func joinerIsBound() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let interloper = Identity.generate()

        var attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        attestation.joinerKeys = interloper.publicKeys

        #expect(throws: MembershipError.wrongJoiner) {
            try attestation.verify(against: inviter.publicKeys, at: start)
        }
    }

    @Test("Every signed field is covered")
    func tamperDetection() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let original = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        var movedRoom = original
        movedRoom.room = ConversationID.room(UUID())
        #expect(throws: MembershipError.badSignature) {
            try movedRoom.verify(against: inviter.publicKeys, at: start)
        }

        var extended = original
        extended.expiresAt = start.addingTimeInterval(999_999)
        #expect(throws: MembershipError.badSignature) {
            try extended.verify(against: inviter.publicKeys, at: start)
        }
    }

    @Test("The verification phrase is a function of the whole attestation")
    func verificationPhrase() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        let other = try TestInvite.issue(
            joining: room, joinerKeys: Identity.generate().publicKeys, by: inviter, at: start)

        #expect(attestation.testPhrase.count == attestation.phraseLength.rawValue)
        #expect(attestation.testPhrase == attestation.testPhrase)
        #expect(attestation.testPhrase != other.testPhrase)
        #expect(attestation.testPhrase.allSatisfy(ShortAuthenticationString.alphabet.contains))
    }

    @Test("An attestation survives encoding, because it travels out of band")
    func codableRoundTrip() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)

        let restored = try JSONDecoder().decode(
            MembershipAttestation.self, from: JSONEncoder().encode(attestation))

        #expect(restored == attestation)
        try restored.verify(against: inviter.publicKeys, at: start)
        #expect(restored.testPhrase == attestation.testPhrase)
    }
}

@Suite("Room roster")
struct RoomRosterTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let room = ConversationID.room(UUID())

    private func rendered(
        _ author: ParticipantID, _ type: PayloadType, hash: UInt8
    ) -> RenderedEntry {
        RenderedEntry(
            id: EntryHash(rawValue: Data(repeating: hash, count: 32)),
            type: type,
            author: author,
            device: DeviceID(rawValue: WideID.of([])),
            wallTime: start,
            conversation: room,
            content: .text(""),
            editedAt: nil,
            replyingTo: nil,
            reactions: [:]
        )
    }

    @Test("Whoever names the room founded it, and needs no attestation")
    func founder() throws {
        let alice = Identity.generate()
        var roster = RoomRoster(room: room)

        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))

        #expect(roster.founder == alice.id)
        #expect(roster.members == [alice.id])
    }

    @Test("An attestation from someone outside the room is refused")
    func inviterMustBeAMember() throws {
        let alice = Identity.generate()
        let outsider = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))

        let forged = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: outsider, at: start)

        #expect(throws: MembershipError.inviterNotAMember) {
            try roster.verify(
                forged, inviterKeys: outsider.publicKeys, at: start)
        }
    }

    @Test("An attestation for a different room is refused")
    func roomIsBound() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))

        let elsewhere = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: alice, at: start)

        #expect(throws: MembershipError.wrongRoom) {
            try roster.verify(elsewhere, inviterKeys: alice.publicKeys, at: start)
        }
    }

    @Test("A join is pending until this member has answered it")
    func pendingUntilDecided() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .anyMember, by: alice.id)

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(joiner.id, .joinRequest, hash: 2), body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 102),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))

        #expect(roster.pending(for: alice.id, at: start).count == 1)

        roster.apply(
            rendered(alice.id, .admission, hash: 3),
            body: try Payload.admission(of: joiner.id, admitted: true))

        #expect(roster.pending(for: alice.id, at: start).isEmpty)
        #expect(roster.members.contains(joiner.id))
    }

    @Test("A refusal blocks that member's rewrap without changing who is in the room")
    func refusalBlocksRewrapNotMembership() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))
        let bobsInvite = try TestInvite.issue(
            joining: room, joinerKeys: bob.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 8), body: try Payload.joinRequest(bobsInvite))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 108),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: bobsInvite, by: bob)))

        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(joiner.id, .joinRequest, hash: 3), body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 103),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))

        roster.apply(
            rendered(alice.id, .admission, hash: 4),
            body: try Payload.admission(of: joiner.id, admitted: true))
        roster.apply(
            rendered(bob.id, .admission, hash: 5),
            body: try Payload.admission(of: joiner.id, admitted: false))

        #expect(roster.members.contains(joiner.id))

        #expect(roster.rewrapTargets(of: alice.id).contains(joiner.id))
        #expect(!roster.rewrapTargets(of: bob.id).contains(joiner.id))

        #expect(roster.whoRefused(joiner.id) == [bob.id])
        #expect(roster.hasRefused(joiner.id, by: bob.id))
        #expect(!roster.isUnanimous(joiner.id))
    }

    @Test("Members see each other without having to admit each other")
    func membersConverge() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let carol = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .anyMember, by: alice.id)

        for (offset, joiner) in [bob, carol].enumerated() {
            let attestation = try TestInvite.issue(
                joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)
            roster.apply(
                rendered(alice.id, .joinRequest, hash: UInt8(2 + offset)),
                body: try Payload.joinRequest(attestation))
            roster.apply(
                rendered(alice.id, .joinConfirmed, hash: UInt8(120 + offset)),
                body: try Payload.joinConfirmed(
                    try JoinConfirmedBody.signed(confirming: attestation, by: joiner)))
            let decides = offset == 0 ? alice : bob
            roster.apply(
                rendered(decides.id, .admission, hash: UInt8(10 + offset)),
                body: try Payload.admission(of: joiner.id, admitted: true))
        }

        #expect(roster.members == [alice.id, bob.id, carol.id])
    }

    @Test("Changing your mind replaces the earlier answer rather than counting twice")
    func decisionsAreReplaced() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 2),
            body: try Payload.joinRequest(attestation))
        roster.apply(
            rendered(alice.id, .admission, hash: 3),
            body: try Payload.admission(
                of: joiner.id, admitted: true, invitation: attestation.signature))
        roster.apply(
            rendered(alice.id, .admission, hash: 4),
            body: try Payload.admission(
                of: joiner.id, admitted: false, invitation: attestation.signature))

        #expect(roster.admissions[joiner.id]?.isEmpty != false)
        #expect(roster.refusals[joiner.id] == [alice.id])
    }

    @Test("A vote for one invitation does not admit on a later one")
    func decisionsDoNotCarryOver() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(
            rendered(alice.id, .roomProfile, hash: 1),
            body: try Payload.roomProfile(name: "Hangar 7"))
        roster.set(access: .anyMember, by: alice.id)

        let first = try TestInvite.issue(
            joining: room, joinerKeys: bob.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 2), body: try Payload.joinRequest(first))
        roster.apply(
            rendered(alice.id, .admission, hash: 3),
            body: try Payload.admission(
                of: bob.id, admitted: true, invitation: first.signature))
        #expect(
            !roster.members.contains(bob.id),
            "the fixture let them in before they had confirmed anything")

        let second = try TestInvite.issue(
            joining: room, joinerKeys: bob.publicKeys, by: alice, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 4), body: try Payload.joinRequest(second))
        roster.apply(
            rendered(alice.id, .joinConfirmed, hash: 5),
            body: try Payload.joinConfirmed(
                try JoinConfirmedBody.signed(confirming: second, by: bob)))

        #expect(
            !roster.members.contains(bob.id),
            """
            A vote cast for a superseded invitation let somebody into the room on the next one. \
            `admissions` and `refusals` were keyed by the person, so a decision outlived the offer \
            it answered — and nothing clears them when an invitation is replaced rather than \
            removed. Same shape as `confirmations`, which was fixed to key on what the body claims \
            and left these two behind.
            """)
        #expect(roster.admissions[bob.id]?.isEmpty != false)
    }

    @Test("A relayed join request is recorded against the joiner, not the messenger")
    func requestsMayBeRelayed() throws {
        let alice = Identity.generate()
        let joiner = Identity.generate()
        let relay = Identity.generate()

        var roster = RoomRoster(room: room)
        let attestation = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: alice, at: start)

        roster.apply(
            rendered(relay.id, .joinRequest, hash: 2), body: try Payload.joinRequest(attestation))

        #expect(roster.requests[joiner.id] == attestation)
        #expect(roster.requests[relay.id] == nil)
    }

    @Test("Relaying cannot launder an attestation from outside the room")
    func relayingDoesNotConferAuthority() throws {
        let alice = Identity.generate()
        let outsider = Identity.generate()
        let joiner = Identity.generate()

        var roster = RoomRoster(room: room)
        roster.apply(rendered(alice.id, .roomProfile, hash: 1), body: try Payload.roomProfile(name: "Hangar 7"))

        let forged = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: outsider, at: start)
        roster.apply(
            rendered(alice.id, .joinRequest, hash: 2), body: try Payload.joinRequest(forged))

        #expect(throws: MembershipError.inviterNotAMember) {
            try roster.verify(
                forged, inviterKeys: outsider.publicKeys, at: start)
        }
    }
}

@Suite("Invites out of band")
struct InviteCodecTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("An invite survives the trip out of band and back")
    func roundTrip() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)

        let restored = try MembershipAttestation.decoded(from: try attestation.encoded())

        #expect(restored == attestation)
        try restored.verify(against: inviter.publicKeys, at: start)
    }

    @Test("Whitespace picked up in transit does not break it")
    func toleratesWhitespace() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)

        let wrapped = try attestation.encoded().enumerated()
            .map { $0.offset % 40 == 39 ? "\($0.element)\n" : String($0.element) }
            .joined()
        let mangled = "  " + wrapped + "\n"

        #expect(try MembershipAttestation.decoded(from: mangled) == attestation)
    }

    @Test("Something that is not an invite is refused rather than half-decoded")
    func rejectsRubbish() throws {
        #expect(throws: (any Error).self) {
            try MembershipAttestation.decoded(from: "not an invite")
        }
    }

    @Test("Re-encoding does not launder a tampered invite")
    func tamperingSurvivesTheRoundTrip() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        var attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)
        attestation.room = ConversationID.room(UUID())

        let restored = try MembershipAttestation.decoded(from: try attestation.encoded())
        #expect(throws: MembershipError.badSignature) {
            try restored.verify(against: inviter.publicKeys, at: start)
        }
    }
}

@Suite("A joiner checking their own invite")
struct JoinerVerificationTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    @Test("A joiner can verify an invite with no prior knowledge of the inviter")
    func joinerVerifies() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)

        try attestation.verifyAsJoiner(at: start)
        #expect(attestation.inviterKeys == inviter.publicKeys)
    }

    @Test("An impostor's invite shows a different phrase")
    func impostorChangesThePhrase() throws {
        let room = ConversationID.room(UUID())
        let inviter = Identity.generate()
        let impostor = Identity.generate()
        let joiner = Identity.generate()

        let real = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: inviter, at: start)
        let forged = try TestInvite.issue(
            joining: room, joinerKeys: joiner.publicKeys, by: impostor, at: start)

        try forged.verifyAsJoiner(at: start)
        #expect(real.testPhrase != forged.testPhrase)
    }

    @Test("Swapping the carried keys for someone else's breaks it")
    func carriedKeysAreBound() throws {
        let inviter = Identity.generate()
        let impostor = Identity.generate()
        let joiner = Identity.generate()

        var attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)
        attestation.inviterKeys = impostor.publicKeys

        #expect(throws: MembershipError.wrongInviter) { try attestation.verifyAsJoiner(at: start) }
    }

    @Test("A member's check rejects an invite whose carried keys disagree with theirs")
    func memberCheckIsUnaffected() throws {
        let inviter = Identity.generate()
        let impostor = Identity.generate()
        let joiner = Identity.generate()

        var attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start)
        attestation.inviter = impostor.id
        attestation.inviterKeys = impostor.publicKeys

        #expect(throws: MembershipError.wrongInviter) {
            try attestation.verify(against: inviter.publicKeys, at: start)
        }
    }

    @Test("A joiner's check still refuses an expired invite")
    func joinerRespectsExpiry() throws {
        let inviter = Identity.generate()
        let joiner = Identity.generate()
        let attestation = try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: joiner.publicKeys, by: inviter, at: start,
            lifetime: 3_600)

        #expect(throws: MembershipError.expired) {
            try attestation.verifyAsJoiner(at: start.addingTimeInterval(3_601))
        }
    }
}

@Suite("The invite envelope")
struct InviteEnvelopeTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func attestation() throws -> MembershipAttestation {
        try TestInvite.issue(
            joining: ConversationID.room(UUID()), joinerKeys: Identity.generate().publicKeys,
            by: Identity.generate(), at: start)
    }

    @Test("An invite carries the mailbox address with the attestation")
    func carriesMailbox() throws {
        let url = URL(string: "https://www.icloud.com/share/abc123")!
        let invite = Invite(attestation: try attestation(), mailbox: url)

        let restored = try Invite.decoded(from: try invite.encoded())

        #expect(restored == invite)
        #expect(restored.mailbox == url)
    }

    @Test("An invite with no mailbox is still an invite")
    func mailboxIsOptional() throws {
        let invite = Invite(attestation: try attestation(), mailbox: nil)
        #expect(try Invite.decoded(from: try invite.encoded()) == invite)
    }

    @Test("A bare attestation decodes as an invite with no mailbox")
    func bareAttestationStillWorks() throws {
        let bare = try attestation()
        let restored = try Invite.decoded(from: try bare.encoded())

        #expect(restored.attestation == bare)
        #expect(restored.mailbox == nil)
    }

    @Test("Rubbish is still refused")
    func rejectsRubbish() throws {
        #expect(throws: (any Error).self) { try Invite.decoded(from: "nonsense") }
    }
}
