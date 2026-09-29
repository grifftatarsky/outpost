@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("A phone writes only under a key made by somebody the room shows as in", .serialized)
struct AMadeUpKeyTests {
    @Test(
        "A key somebody made up before being removed stops being written under when the removal arrives, and the room's real key is taken beside it",
        arguments: [true, false])
    func aMadeUpKeyStopsAtTheRemoval(withARecord: Bool) async throws {
        let t = try await RoomOfThree.make()
        let before = try #require(t.key(of: t.alice))
        let madeUp = try await t.samHandsCarolAKeyOfHisOwn(after: before, withARecord: withARecord)
        try #require(t.carol.writingKey(of: t.room)?.secret == madeUp, "precondition: Carol writes under Sam's key while he is in")
        try await t.carol.send("while Sam was in", to: t.room)

        try await t.alice.remove(t.samID, from: t.room)
        try #require(t.key(of: t.alice) == before.next, "precondition: the room's new key has the number Sam's took")
        try await t.settle()

        let writing = try #require(t.carol.writingKey(of: t.room))
        #expect(writing.secret != madeUp, "Carol kept writing under the key Sam made up after his removal reached her")
        #expect(
            writing.secret == t.alice.writingKey(of: t.room)?.secret,
            "Carol did not take the room's real key, because she already held one for that number")

        try await t.carol.send("after Sam", to: t.room)
        let sent = try #require(t.carol.replica.allEntries.last { $0.author == t.carolID && $0.room == t.room })
        var samsKeys = try #require(t.sam.chains[t.room])
        samsKeys.hold(madeUp, at: before.next)
        #expect(sent.opened(using: samsKeys) == nil, "Sam can read what Carol wrote after his removal reached her")

        try await t.settle()
        #expect(
            t.alice.messages(in: t.room).contains { $0.body == "after Sam" },
            "Alice cannot read what Carol wrote under the room's real key")
        #expect(
            t.carol.messages(in: t.room).contains { $0.body == "while Sam was in" },
            "Carol lost what she wrote under Sam's key once the real one was taken beside it")
    }

    @Test("Two members who turn the key at the same moment end up writing under the same one, and read both")
    func rivalKeysConverge() async throws {
        let t = try await RoomOfThree.make()
        let before = try #require(t.key(of: t.alice))
        try await t.turnTheKeyTogether()

        let chosen = try #require(t.alice.writingKey(of: t.room))
        #expect(chosen.epoch == before.next)
        for session in [t.carol, t.sam] {
            #expect(
                session.writingKey(of: t.room)?.secret == chosen.secret,
                "two phones in one room write under different keys for the same number")
        }
        for session in [t.alice, t.carol, t.sam] {
            let bodies = session.messages(in: t.room).map { $0.body }
            #expect(bodies.contains("under Alice's key") && bodies.contains("under Carol's key"))
        }
    }

    @Test("Every key a phone holds for one number is still held after a relaunch")
    func everyKeySurvivesARelaunch() async throws {
        let t = try await RoomOfThree.make()
        try await t.turnTheKeyTogether()

        let relaunched = TestSession.make(keychain: t.carolKeychain, at: t.carolFolder)
        await relaunched.load()
        let bodies = relaunched.messages(in: t.room).map { $0.body }
        #expect(
            bodies.contains("under Alice's key") && bodies.contains("under Carol's key"),
            "a key held beside another for the same number was lost on relaunch")
    }

    @Test("A phone keeps every key it holds for a number, and a single key in the form it always had")
    func theKeychainKeepsEveryKey() {
        let one = EpochSecret.random()
        let two = EpochSecret.random()
        #expect(AppSession.keychainForm(of: [one]) == one.material)
        #expect(AppSession.keys(inKeychainForm: one.material) == [one])
        #expect(AppSession.keys(inKeychainForm: AppSession.keychainForm(of: [one, two])) == [one, two])
    }
}

@MainActor
extension RoomOfThree {
    fileprivate func samHandsCarolAKeyOfHisOwn(after current: EpochNumber, withARecord: Bool) async throws -> EpochSecret {
        let chain = try #require(sam.chains[room])
        let (madeUp, link) = try EpochChain.advance(from: try chain.secret(for: current), at: current, room: room)
        if withARecord {
            try await sam.append(
                try Payload.epochChange(link, heads: sam.lastEntries(in: room), under: madeUp), to: room)
            try await sam.sync(through: mailbox, media: mailbox)
            try await carol.sync(through: mailbox, media: mailbox)
        }
        let grant = try EpochGrant.issue(
            madeUp, at: current.next, in: room, link: link,
            to: try #require(sam.pairwiseSecret(with: carolID)), devices: sam.deviceRecipients(of: carolID)
        ).signed(by: try #require(sam.enrolment?.device), from: samID, to: carolID)
        let secret = try #require(carol.pairwiseSecret(with: samID))
        try await carol.adopt(grant, from: Peer(secret: secret, them: samID, me: carolID), storedAt: .distantFuture)
        return madeUp
    }

    fileprivate func turnTheKeyTogether() async throws {
        try await alice.advanceEpoch(of: room)
        try await carol.advanceEpoch(of: room)
        let alices = try #require(alice.writingKey(of: room)?.secret)
        let carols = try #require(carol.writingKey(of: room)?.secret)
        try #require(alices != carols, "precondition: two keys for one number")
        try await alice.send("under Alice's key", to: room)
        try await carol.send("under Carol's key", to: room)
        let chosenFirst = alices.fingerprint.lexicographicallyPrecedes(carols.fingerprint) ? alice : carol
        try await chosenFirst.sync(through: mailbox, media: mailbox)
        try await settle()
    }

    fileprivate func friend(of host: AppSession, named name: String) async throws -> AppSession {
        let friend = TestSession.make()
        await friend.load()
        try await friend.createIdentity(displayName: name)
        try await join(friend, into: try await host.createRoom(named: "Kitchen"), of: host, through: mailbox)
        for _ in 0..<3 {
            for session in [alice, carol, sam, friend] { try await session.sync(through: mailbox, media: mailbox) }
        }
        return friend
    }

    fileprivate func invite(_ joiner: AppSession, by host: AppSession) async throws {
        let invite = try await host.invite(
            joinerCode: await joiner.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await joiner.redeem(inviteCode: try invite.encoded())
    }

    fileprivate func letIn(_ joiner: AppSession, by host: AppSession) async throws {
        for _ in 0..<5 {
            try await host.sync(through: mailbox, media: mailbox)
            try await joiner.sync(through: mailbox, media: mailbox)
        }
    }

    fileprivate func hand(_ key: TrustedKey, from giver: AppSession, to receiver: AppSession) async throws {
        let giverID = try #require(giver.enrolment?.identity.id)
        let receiverID = try #require(receiver.enrolment?.identity.id)
        let devices = giver.deviceRecipients(of: receiverID)
        try #require(!devices.isEmpty, "precondition: the giver can seal a key to the receiver's phone")
        let grant = try EpochGrant.issue(
            key.secret, at: key.epoch, in: room, link: key.link,
            to: try #require(giver.pairwiseSecret(with: receiverID)), devices: devices
        ).signed(by: try #require(giver.enrolment?.device), from: giverID, to: receiverID)
        let secret = try #require(receiver.pairwiseSecret(with: giverID))
        try await receiver.adopt(grant, from: Peer(secret: secret, them: giverID, me: receiverID), storedAt: .distantFuture)
    }
}

@MainActor
@Suite("A key that reaches a joining phone before it can check who gave it waits", .serialized)
struct AKeyThatWaitsTests {
    @Test("Somebody who joins during a tie gets both keys when another member's comes before the inviter's")
    func anotherMembersKeyBeforeTheInviters() async throws {
        let t = try await RoomOfThree.make()
        try await t.turnTheKeyTogether()
        let dave = try await t.friend(of: t.alice, named: "Dave")
        try await t.invite(dave, by: t.carol)
        let alices = try #require(t.alice.keyToPassOn(in: t.room))
        let carols = try #require(t.carol.keyToPassOn(in: t.room))
        try await t.hand(alices, from: t.alice, to: dave)
        try #require(dave.chains[t.room] == nil, "precondition: Dave holds no key for the room yet")

        try await t.letIn(dave, by: t.carol)
        let held = Set(dave.chains[t.room]?.heldSecrets(at: alices.epoch) ?? [])
        #expect(held == [alices.secret, carols.secret], "Dave dropped the key Alice sent before his inviter's")
        let bodies = dave.messages(in: t.room).map { $0.body }
        #expect(bodies.contains("under Alice's key") && bodies.contains("under Carol's key"))
    }

    @Test("A key from a member the joining phone does not know is in yet waits until it does")
    func aKeyBeforeTheHistory() async throws {
        let t = try await RoomOfThree.make()
        try await t.turnTheKeyTogether()
        let dave = try await t.friend(of: t.alice, named: "Dave")
        try await t.invite(dave, by: t.carol)
        let alices = try #require(t.alice.keyToPassOn(in: t.room))
        let carols = try #require(t.carol.keyToPassOn(in: t.room))
        try await t.hand(carols, from: t.carol, to: dave)
        try #require(dave.chains[t.room] != nil, "precondition: Dave took his inviter's key")
        try #require(
            !dave.roster(of: t.room).members.contains(t.aliceID), "precondition: Dave's phone does not know Alice is in")
        try await t.hand(alices, from: t.alice, to: dave)

        try await t.letIn(dave, by: t.carol)
        let held = Set(dave.chains[t.room]?.heldSecrets(at: alices.epoch) ?? [])
        #expect(
            held == [alices.secret, carols.secret],
            "Dave dropped Alice's key because his phone did not yet know she was in the room")
    }

    @Test("A key from somebody the room removed never counts on a joining phone, and one person can leave only one waiting")
    func aRemovedMembersKeyNeverCounts() async throws {
        let t = try await RoomOfThree.make()
        try await t.alice.remove(t.samID, from: t.room)
        try await t.settle()
        let dave = try await t.friend(of: t.sam, named: "Dave")
        try await t.invite(dave, by: t.carol)
        let number = try #require(t.key(of: t.carol))
        let madeUp = (0..<3).map { _ in EpochSecret.random() }
        for secret in madeUp {
            try await t.hand(TrustedKey(epoch: number, secret: secret, link: nil, maker: t.samID), from: t.sam, to: dave)
        }
        #expect(
            dave.persisted.grantsWaiting.filter { $0.from == t.samID }.count == 1,
            "more than one key from one person waited")

        try await t.letIn(dave, by: t.carol)
        try #require(dave.roster(of: t.room).absent.contains(t.samID), "precondition: Dave's phone knows Sam was removed")
        let held = dave.chains[t.room]?.heldSecrets(at: number) ?? []
        #expect(madeUp.allSatisfy { !held.contains($0) }, "Dave took a key from somebody the room had removed")
        #expect(!dave.persisted.grantsWaiting.contains(where: { $0.from == t.samID }))
    }
}

@Suite("Several keys for one number")
struct SeveralKeysForOneNumberTests {
    @Test("A second key for a number is held beside the first, and what either sealed opens")
    func aSecondKeyIsHeldBesideTheFirst() throws {
        let room = RoomID()
        let (created, first) = EpochChain.create(room: room)
        var chain = created
        let next = EpochNumber.initial.next
        let (mine, _) = try EpochChain.advance(from: first, at: .initial, room: room)
        let (theirs, _) = try EpochChain.advance(from: first, at: .initial, room: room)
        chain.adopt(mine, at: next)
        chain.hold(theirs, at: next, from: Identity.generate().id)
        #expect(try chain.secret(for: next) == mine)
        #expect(Set(chain.heldSecrets(at: next)) == [mine, theirs])

        let sealed = try Payload.post("under theirs").sealed(at: next, using: chain.choosing(theirs, at: next))
        #expect(try sealed.opened(using: chain).type == .post)
    }

    @Test("One person can put only one key beside a number, so a flood cannot crowd out the real one")
    func oneKeyPerGiver() throws {
        let room = RoomID()
        let (created, first) = EpochChain.create(room: room)
        var chain = created
        let next = EpochNumber.initial.next
        let (sams, _) = try EpochChain.advance(from: first, at: .initial, room: room)
        let sam = Identity.generate().id
        chain.hold(sams, at: next, from: sam)
        for _ in 0..<EpochChain.mostRivals { chain.hold(EpochSecret.random(), at: next, from: sam) }
        #expect(chain.heldSecrets(at: next) == [sams])

        let real = EpochSecret.random()
        chain.hold(real, at: next, from: Identity.generate().id)
        #expect(chain.heldSecrets(at: next) == [sams, real])
    }

    @Test("No second key is held for a room's first number")
    func noSecondKeyAtTheStart() {
        let (created, first) = EpochChain.create(room: RoomID())
        var chain = created
        chain.hold(EpochSecret.random(), at: .initial, from: Identity.generate().id)
        #expect(chain.heldSecrets(at: .initial) == [first])
    }
}
