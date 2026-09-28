@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("Who can tell your phone where to read somebody", .serialized)
@MainActor
struct WhoCanTellYouWhereToReadSomebodyTests {
    @MainActor
    private struct Rig {
        let mailbox: InMemoryMailbox
        let clock: TestClock
        let phone: AppSession
        let thief: AppSession
        let peer: AppSession
        let room: RoomID

        var griff: ParticipantID { phone.enrolment!.identity.id }
        var outie: ParticipantID { peer.enrolment!.identity.id }
        var away: SignedInMailbox { mailbox.signedIn(as: "_thief") }

        func rounds(_ count: Int, thiefToo: Bool = true) async throws {
            for _ in 0..<count {
                try await phone.sync(through: mailbox)
                try await peer.sync(through: mailbox)
                if thiefToo { _ = try? await thief.sync(through: away) }
                await phone.settleDeviceSync()
                await thief.settleDeviceSync()
            }
        }
    }

    private func rig() async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay(announces: true)
        let phone = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        phone.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [phone, peer] { await session.load() }
        try await phone.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")

        let room = try await phone.createRoom(named: "Kitchen")
        let invite = try await phone.invite(joinerCode: await peer.joinerCode(through: mailbox), joining: room, through: mailbox)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await phone.sync(through: mailbox)
        try await peer.accept(invite.attestation, from: try #require(phone.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [phone, peer] { try await session.sync(through: mailbox) }
        }
        await phone.settleDeviceSync()

        let thief = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        thief.syncDevices(through: InMemoryEntrySync(relay: relay))
        await thief.load()
        try await phone.approveNewDevice(thief)
        let deadline = Date().addingTimeInterval(5)
        while thief.rooms.isEmpty, Date() < deadline {
            await phone.refreshDeviceSync()
            await phone.settleDeviceSync()
            await thief.refreshDeviceSync()
            await thief.settleDeviceSync()
        }
        return Rig(mailbox: mailbox, clock: clock, phone: phone, thief: thief, peer: peer, room: room)
    }

    @Test("A link from a device the person then removes stops counting, and their contact reads them where they are again")
    func aRemovedDevicesLinkStopsCounting() async throws {
        let rig = try await rig()
        let real = LocalPairStore.account(of: rig.griff)
        #expect(rig.peer.link(for: rig.griff)?.account == real, "precondition: Outie names Griff's own account")

        rig.clock.advance(by: 60)
        try await rig.rounds(8)
        #expect(
            rig.peer.link(for: rig.griff)?.account == "_thief",
            "precondition: while the second device counts, the link it sends is Griff's newest")
        #expect(
            rig.peer.pairs()?.accounts[rig.griff]?.contains(real) == true,
            "while a second device's link is newest, Outie stopped reading the account Griff's first device writes from")

        let stolen = try #require(rig.thief.enrolment?.device.id)
        try await rig.phone.revoke(stolen)
        try await rig.rounds(8, thiefToo: false)

        #expect(
            rig.peer.link(for: rig.griff)?.account == real,
            "a link sent by a device Griff removed still decides who Outie lets read her space for him")
        #expect(
            rig.peer.pairs()?.accounts[rig.griff] == [real],
            "Outie still reads Griff from an account only a removed device named")

        try await rig.peer.send("after the removal", to: rig.room)
        try await rig.rounds(6, thiefToo: false)
        #expect(
            rig.phone.messages(in: rig.room).contains { $0.body == "after the removal" },
            "Griff's real phone never heard Outie again once the removed device's link stopped counting")

        let asGriff = try #require(rig.phone.pairs())
        let peer = try #require(rig.phone.peers().first { $0.them == rig.outie })
        #expect(
            try await rig.away.fetch(
                from: rig.outie, for: SyncSession.recentTags(for: peer, at: rig.clock.now), in: asGriff
            ).isEmpty,
            "the removed device's account still reads the space Outie keeps for Griff")
    }

    @Test("A code or an invite never replaces a link already held")
    func anIntroductionNeverReplacesALink() async throws {
        let rig = try await rig()
        let held = try #require(rig.peer.link(for: rig.griff))
        let other = try await rig.thief.createRoom(named: "Somewhere else")
        let invite = try await rig.thief.invite(
            joinerCode: await rig.peer.joinerCode(through: rig.mailbox), joining: other, through: rig.away)
        #expect(invite.verifiedPair?.account == "_thief", "precondition: the invite carries the other account's link")

        try await rig.peer.redeem(inviteCode: try invite.encoded())
        #expect(rig.peer.link(for: rig.griff) == held, "an invite replaced the link Outie already held for Griff")
        #expect(
            rig.peer.pairs()?.accounts[rig.griff]?.contains("_thief") == false,
            "an invite added an account Outie reads Griff from, with no device standing behind it")
    }

    @Test("A contact is read only from the account their link names, whatever else carries the mark of the pair")
    func onlyTheLinkedAccountIsRead() async throws {
        for _ in 0..<8 {
            let mailbox = InMemoryMailbox()
            let (alice, bob) = (Identity.generate(), Identity.generate())
            let (toBob, asBob) = try peers(alice, bob)
            let (asAlice, asBobPairs) = try await link(toBob, asBob, through: mailbox)

            let away = mailbox.signedIn(as: "_elsewhere")
            let forged = try await away.space(for: asBob.them, naming: LocalPairStore.account(of: alice.id), in: asBobPairs)
            _ = await mailbox.join(PairLink(account: "_elsewhere", url: forged), of: bob.id, in: asAlice)

            let tag = asBob.outgoingTag(window: 1)
            try await mailbox.put(SyncPacket(wraps: [tag: Data()], ciphertext: Data("real".utf8)), to: alice.id, in: asBobPairs)
            try await away.put(SyncPacket(wraps: [tag: Data()], ciphertext: Data("elsewhere".utf8)), to: alice.id, in: asBobPairs)

            let read = await mailbox.fetch(from: bob.id, for: [toBob.incomingTag(window: 1)], in: asAlice)
            #expect(read.map(\.ciphertext) == [Data("real".utf8)], "a space in an account Bob's link does not name was read as his")
        }
    }

    @Test("A code's space is written down as soon as it is made, so a relaunch does not make another")
    func aCodesSpaceSurvivesARelaunch() async throws {
        let mailbox = InMemoryMailbox()
        let keychain = InMemoryKeychainStore()
        let directory = TestScratch.root.appending(path: "code-space-\(UUID().uuidString)")
        let session = TestSession.make(keychain: keychain, at: directory)
        await session.load()
        try await session.createIdentity(displayName: "Alice")
        await session.pairUp(through: mailbox)
        let made = try #require(session.persisted.codeLink)

        let relaunched = TestSession.make(keychain: keychain, at: directory)
        await relaunched.load()
        await relaunched.pairUp(through: mailbox)
        #expect(relaunched.persisted.codeLink == made, "a relaunch made a second space for the same code")
        let me = try #require(session.enrolment?.identity.id)
        #expect(await mailbox.spaceCount(of: me) == 1)
    }

    @Test("A code's space is made once, however many callers ask for it at the same moment")
    func aCodesSpaceIsMadeOnce() async throws {
        let mailbox = InMemoryMailbox()
        let session = TestSession.make()
        await session.load()
        try await session.createIdentity(displayName: "Alice")

        async let first: Void = session.pairUp(through: mailbox)
        async let second = session.joinerCode(through: mailbox)
        async let third: Void = session.pairUp(through: mailbox)
        _ = await (first, second, third)

        let me = try #require(session.enrolment?.identity.id)
        #expect(await mailbox.spaceCount(of: me) == 1, "two callers each made a space for one code")
    }
}
