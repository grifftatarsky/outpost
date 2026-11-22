@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("What a chain walks is what it holds", .tags(.crypto, .sync))
struct WhatAChainWalksTests {
    private let room = RoomID(rawValue: UUID())

    @Test("A key at a number nobody could count to is one number held")
    func aFarNumberIsOneNumber() {
        var chain = EpochChain(room: room)
        chain.hold(.random(), at: .initial)
        chain.hold(.random(), at: EpochNumber(rawValue: 1 << 62))
        #expect(chain.heldNumbers == [EpochNumber(rawValue: 1 << 62), .initial])
    }

    @Test("A link holds the number it opens as well as its own")
    func aLinkHoldsTheNumberBelowIt() throws {
        let (_, link) = try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: 4), room: room)
        var chain = EpochChain(room: room)
        try chain.record(link)
        #expect(chain.heldNumbers == [EpochNumber(rawValue: 5), EpochNumber(rawValue: 4)])
    }

    @Test("A key at the very top of the numbers does not trap")
    func theLastNumberDoesNotTrap() throws {
        var chain = EpochChain(room: room)
        chain.hold(.random(), at: EpochNumber(rawValue: .max))
        #expect(chain.heldNumbers == [EpochNumber(rawValue: .max)])
        #expect(throws: CryptoError.self) {
            _ = try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: .max), room: room)
        }
    }
}

@MainActor
@Suite("A key's number is not a loop bound", .serialized, .tags(.crypto, .sync))
struct AKeysNumberIsNotALoopBoundTests {
    private func grant(
        at epoch: EpochNumber, links: [EpochLink] = [], from giver: AppSession, to taker: AppSession, in room: RoomID
    ) throws -> (grant: EpochGrant, peer: Peer) {
        let giverID = try #require(giver.enrolment?.identity.id)
        let takerID = try #require(taker.enrolment?.identity.id)
        let issued = try EpochGrant.issue(
            EpochSecret.random(), at: epoch, in: room, link: nil,
            to: try #require(giver.pairwiseSecret(with: takerID)), devices: giver.deviceRecipients(of: takerID))
        let carrying = EpochGrant(
            room: room, epoch: epoch, link: nil, links: links, wrapped: issued.wrapped, sealedFor: issued.sealedFor)
        return (
            try carrying.signed(by: try #require(giver.enrolment?.device), from: giverID, to: takerID),
            Peer(secret: try #require(taker.pairwiseSecret(with: giverID)), them: giverID, me: takerID)
        )
    }

    private func walkOf(_ session: AppSession, _ room: RoomID) -> Duration {
        session.cachedKeysToPassOn = [:]
        return ContinuousClock().measure { _ = session.keysToPassOn(in: room) }
    }

    private func poison(_ t: RoomOfThree, at number: UInt64) throws {
        var chain = try #require(t.carol.chains[t.room])
        chain.hold(.random(), at: try #require(chain.highestKnownEpoch), from: t.samID)
        chain.hold(.random(), at: EpochNumber(rawValue: number), from: t.samID)
        t.carol.chains[t.room] = chain
    }

    private func shownRotations(_ t: RoomOfThree) -> Int {
        Set(t.carol.projection.keyChanges(in: t.room, opening: t.carol.payloadOpener()).map(\.change.link.epoch)).count
    }

    private func fill(_ t: RoomOfThree, upTo count: Int) throws -> UInt64 {
        var chain = try #require(t.carol.chains[t.room])
        var number = try #require(chain.highestKnownEpoch).rawValue + 1
        for _ in 0..<(count - chain.heldNumbers.count) {
            chain.hold(.random(), at: EpochNumber(rawValue: number))
            number += 1
        }
        t.carol.chains[t.room] = chain
        return number
    }

    @Test("A key far above a room's others costs no more to pass on than the keys a phone holds", .tags(.timing))
    func aFarKeyCostsNothingToWalk() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.advanceEpoch(of: t.room)
        try await t.settle()
        try poison(t, at: 1 << 24)

        #expect(walkOf(t.carol, t.room) < .milliseconds(100), "the walk counted down from a number Sam chose")
    }

    @Test("A chain already holding a key at two to the sixty-two still passes on keys after a relaunch", .tags(.timing))
    func aPoisonedChainSurvivesARelaunch() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.advanceEpoch(of: t.room)
        try await t.settle()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch)
        let far = EpochNumber(rawValue: 1 << 62)
        try poison(t, at: far.rawValue)
        try await t.carol.persistEpoch(try #require(t.carol.chains[t.room]?.heldSecrets(at: far).first), at: far, for: t.room)
        try await t.carol.persistEpoch(try #require(t.carol.chains[t.room]?.heldSecrets(at: top).first), at: top, for: t.room)

        let relaunched = TestSession.make(keychain: t.carolKeychain, at: t.carolFolder)
        await relaunched.load()

        #expect(relaunched.chains[t.room]?.heldNumbers.first == far, "precondition: the key came back")
        #expect(walkOf(relaunched, t.room) < .milliseconds(100))
        _ = try relaunched.grantsOwed()
    }

    @Test("A key at two to the sixty-two with nothing under it is refused")
    func aKeyFromNowhereIsRefused() async throws {
        let t = try await RoomOfThree.make()
        let before = try #require(t.carol.chains[t.room]?.heldNumbers)
        let far = try grant(at: EpochNumber(rawValue: 1 << 62), from: t.sam, to: t.carol, in: t.room)

        try await t.carol.adopt(far.grant, from: far.peer, storedAt: .distantFuture)

        #expect(t.carol.chains[t.room]?.heldNumbers == before, "a number Sam chose went into Carol's chain")
    }

    @Test("A key at the last number there is does not trap")
    func theLastNumberIsRefusedWithoutATrap() async throws {
        let t = try await RoomOfThree.make()
        let far = try grant(at: EpochNumber(rawValue: .max), from: t.sam, to: t.carol, in: t.room)

        try await t.carol.adopt(far.grant, from: far.peer, storedAt: .distantFuture)

        #expect(t.carol.chains[t.room]?.highestKnownEpoch != EpochNumber(rawValue: .max))
    }

    @Test("A key a few numbers ahead is taken with no links, and one past that is not")
    func aFewNumbersAheadIsTheStep() async throws {
        let t = try await RoomOfThree.make()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch).rawValue
        let past = try grant(
            at: EpochNumber(rawValue: top + EpochChain.mostNumbersSkipped + 1), from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(past.grant, from: past.peer, storedAt: .distantFuture)
        #expect(t.carol.chains[t.room]?.highestKnownEpoch?.rawValue == top)

        let within = try grant(
            at: EpochNumber(rawValue: top + EpochChain.mostNumbersSkipped), from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(within.grant, from: within.peer, storedAt: .distantFuture)
        #expect(t.carol.chains[t.room]?.highestKnownEpoch?.rawValue == top + EpochChain.mostNumbersSkipped)
    }

    @Test("Links at one number, repeated, do not count as links for many")
    func repeatedLinksAreOneNumber() async throws {
        let t = try await RoomOfThree.make()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch).rawValue
        let (_, link) = try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: top), room: t.room)
        let far = try grant(
            at: EpochNumber(rawValue: top + 100), links: Array(repeating: link, count: 200), from: t.sam, to: t.carol,
            in: t.room)

        try await t.carol.adopt(far.grant, from: far.peer, storedAt: .distantFuture)

        #expect(t.carol.chains[t.room]?.highestKnownEpoch?.rawValue == top)
    }

    @Test("A link above the key that carried it is not kept")
    func aLinkAboveItsKeyIsDropped() async throws {
        let t = try await RoomOfThree.make()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch)
        let (_, above) = try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: 1 << 40), room: t.room)
        let carrying = try grant(at: top.next, links: [above], from: t.sam, to: t.carol, in: t.room)

        try await t.carol.adopt(carrying.grant, from: carrying.peer, storedAt: .distantFuture)

        #expect(t.carol.chains[t.room]?.highestKnownEpoch == top.next, "precondition: the key itself was fine")
        #expect(t.carol.chains[t.room]?.link(at: above.epoch) == nil, "a link at a made-up number went into the chain")
    }

    @Test("A grant carrying more links than any grant can is refused, and one being written stops at that many")
    func tooManyLinksIsRefused() async throws {
        let t = try await RoomOfThree.make()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch)
        var links: [EpochLink] = []
        for number in 0...UInt64(EpochChain.mostLinksInAGrant) {
            links.append(try EpochChain.advance(from: .random(), at: EpochNumber(rawValue: number), room: t.room).link)
        }
        let heavy = try grant(at: top.next, links: links, from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(heavy.grant, from: heavy.peer, storedAt: .distantFuture)
        #expect(t.carol.chains[t.room]?.highestKnownEpoch == top)

        let carolID = t.carolID
        let issued = try EpochGrant.issue(
            .random(), at: EpochNumber(rawValue: 9_000), in: t.room, link: nil, links: links,
            to: try #require(t.sam.pairwiseSecret(with: carolID)), devices: t.sam.deviceRecipients(of: carolID))
        #expect(issued.links.count == EpochChain.mostLinksInAGrant)
        #expect(issued.links.last == links.last, "the links kept are the newest")
    }

    @Test("A member cannot add more numbers than the log shows plus the allowance, one small step at a time")
    func theChainStopsGrowing() async throws {
        let t = try await RoomOfThree.make()
        let allowed = EpochChain.mostNumbersTheLogHasNotShown + shownRotations(t)
        let number = try fill(t, upTo: allowed)

        let last = try grant(at: EpochNumber(rawValue: number), from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(last.grant, from: last.peer, storedAt: .distantFuture)

        #expect(t.carol.chains[t.room]?.heldNumbers.count == allowed)
    }

    @Test("Rotations the log shows do not count against the allowance")
    func aRoomThatRotatedALotIsNotRefused() async throws {
        let t = try await RoomOfThree.make()
        for _ in 0..<3 { try await t.alice.advanceEpoch(of: t.room) }
        try await t.settle()
        let shown = shownRotations(t)
        try #require(shown >= 3, "precondition: Carol reads the rotations")
        let number = try fill(t, upTo: EpochChain.mostNumbersTheLogHasNotShown + shown - 1)

        let within = try grant(at: EpochNumber(rawValue: number), from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(within.grant, from: within.peer, storedAt: .distantFuture)
        #expect(t.carol.chains[t.room]?.highestKnownEpoch?.rawValue == number, "a number within the allowance was refused")

        let past = try grant(at: EpochNumber(rawValue: number + 1), from: t.sam, to: t.carol, in: t.room)
        try await t.carol.adopt(past.grant, from: past.peer, storedAt: .distantFuture)
        #expect(t.carol.chains[t.room]?.highestKnownEpoch?.rawValue == number, "one past the allowance was let in")
    }

    @Test("A phone that sat out many rotations catches up from one key and reads the room")
    func aDeviceBehindCatchesUp() async throws {
        let t = try await RoomOfThree.make()
        let top = try #require(t.carol.chains[t.room]?.highestKnownEpoch)
        let rotations = Int(EpochChain.mostNumbersSkipped) * 3
        for index in 0..<rotations {
            try await t.alice.advanceEpoch(of: t.room)
            try await t.alice.send("rotation \(index)", to: t.room)
        }
        let newest = try #require(t.alice.chains[t.room]?.highestKnownEpoch)
        #expect(newest.rawValue >= top.rawValue + UInt64(rotations))

        for _ in 0..<4 {
            try await t.alice.sync(through: t.mailbox, media: t.mailbox)
            try await t.carol.sync(through: t.mailbox, media: t.mailbox)
        }

        #expect(t.carol.chains[t.room]?.highestKnownEpoch == newest, "a phone that fell behind was refused the key")
        let bodies = t.carol.messages(in: t.room).map(\.body)
        #expect(
            (0..<rotations).allSatisfy { bodies.contains("rotation \($0)") },
            "a phone that caught up cannot read what it missed")
    }

    @Test("The first key a phone is given for a room can sit at any number, because there is nothing to measure it from")
    func aFirstKeyHasNothingToBeMeasuredFrom() async throws {
        let t = try await RoomOfThree.make()
        let elsewhere = RoomID(rawValue: UUID())
        let first = try grant(at: EpochNumber(rawValue: 50), from: t.sam, to: t.carol, in: elsewhere)
        var chain = EpochChain(room: elsewhere)

        try chain.adopt(first.grant, using: first.peer.secret, as: t.carol.enrolment?.device)

        #expect(chain.highestKnownEpoch?.rawValue == 50)
    }
}
