@testable import CarpenterApp
import CarpenterKitTesting
import Foundation
import Testing

@testable import CarpenterKit

@Suite("Being told that somebody came back", .serialized)
@MainActor
struct BeingToldAboutARestoreTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Rig {
        let original: AppSession
        let peer: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let relay: InMemoryEntrySync.Relay
        let clock: TestClock
        let key: String
    }

    private func rig(
        peerIsTold: Bool, peerHolds: Bool = false, namesShared: Bool = true
    ) async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")
        await peer.setToldAboutRestores(peerIsTold)
        await peer.setHoldsHistoryForRestores(peerHolds)
        if namesShared {
            for session in [original, peer] {
                await session.setSharing(
                    NameAndAvatarSharing(
                        sharesName: true, sharesAvatar: false, showsOthersNames: true,
                        showsOthersAvatars: false))
            }
        }

        let room = try await original.createRoom(named: "Kitchen")
        let invite = try await original.invite(
            joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await original.sync(through: mailbox)
        try await peer.accept(
            invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }

        await settle(original) { false }
        let key = try #require(original.recoveryKeyText())
        return Rig(
            original: original, peer: peer, room: room, mailbox: mailbox, relay: relay,
            clock: clock, key: key)
    }

    private func restoreAndSettle(_ rig: Rig) async throws -> AppSession {
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: rig.clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: rig.key)
        await settle(fresh) { !fresh.rooms.isEmpty }
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }
        return fresh
    }

    @Test("Being told is what happens to somebody who never chose")
    func beingToldIsTheDefault() async throws {
        let fresh = MemberPreferences()
        #expect(
            fresh.isToldAboutRestores,
            """
            A member who has never opened the check-up is not told when somebody restores and asks \
            them for history. Ruled 2026-09-13 that this is "not a setting — everybody gets it", \
            and it read `== true` until 2026-09-14, so nil meant no. It is the one notice about a \
            device signing as somebody and collecting everything they ever said.
            """)

        var off = MemberPreferences()
        off.setToldAboutRestores(
            false, stamp: OrganisationStamp(at: Date(), device: DeviceID(rawValue: WideID.of([1]))))
        #expect(!off.isToldAboutRestores, "turning it off has to still turn it off")
    }

    @Test("The person who was asked is told who came back, and which conversation")
    func thePersonAskedIsTold() async throws {
        let rig = try await rig(peerIsTold: true)
        _ = try await restoreAndSettle(rig)

        let ask = try #require(
            rig.peer.latestRestoreAsk(),
            """
            Nothing told the peer that a restore had asked them for history. Griff ruled on \
            2026-09-13 that a restore is not silent: "you're requesting to fill history you've \
            lost which means you're asking for it".
            """)
        #expect(ask.person == rig.original.enrolment?.identity.id)
        #expect(ask.personName == "Griff", "the banner would not name who came back")
        #expect(ask.room == rig.room)
        #expect(ask.roomName == "Kitchen", "the banner would not name what was asked for")
    }

    @Test("Somebody who does not share their name is still named, by their code")
    func somebodyWhoDoesNotShareTheirNameIsNamedByCode() async throws {
        let rig = try await rig(peerIsTold: true, namesShared: false)
        _ = try await restoreAndSettle(rig)

        let ask = try #require(rig.peer.latestRestoreAsk())
        #expect(
            !ask.personName.isEmpty,
            """
            The banner would have had nobody in it. Names are not shared by default, so the person             who came back is often only a code — which is still who to tell somebody about.
            """)
        #expect(ask.personName != "Griff", "a name that was never shared reached the banner")
    }

    @Test("Somebody who did not ask to be told is not told")
    func somebodyWhoDidNotAskIsNotTold() async throws {
        let rig = try await rig(peerIsTold: false)
        _ = try await restoreAndSettle(rig)

        #expect(
            rig.peer.latestRestoreAsk() == nil,
            "a banner was raised for somebody whose answer to being told was no")
    }

    @Test("History goes either way, whatever the answer about being told")
    func historyGoesEitherWay() async throws {
        for told in [true, false] {
            let rig = try await rig(peerIsTold: told)
            try await rig.peer.send("said while the phone was gone", to: rig.room)
            for _ in 0..<6 { try await rig.peer.sync(through: rig.mailbox) }

            let fresh = try await restoreAndSettle(rig)
            #expect(
                fresh.messages(in: rig.room).contains { $0.body == "said while the phone was gone" },
                """
                Turning the banner \(told ? "on" : "off") changed whether history came back. \
                Griff's ruling is that it does not: "History goes by default and waits only if \
                they have said to wait", and waiting is the other setting.
                """)
        }
    }

    @Test("An ordinary repair is not announced as somebody coming back")
    func anOrdinaryRepairIsNotAnnounced() async throws {
        let rig = try await rig(peerIsTold: true)
        _ = await rig.original.startRepair(in: rig.room)
        for _ in 0..<6 {
            for session in [rig.original, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            rig.peer.latestRestoreAsk() == nil,
            """
            A repair somebody started by hand was announced as a recovery. The two are different \
            events and only one of them is worth waking somebody for.
            """)
    }

    @Test("The reason survives the round trip, and the round that asks again")
    func theReasonSurvivesTheRoundTrip() throws {
        let asked = RepairRequest(
            authors: [], heads: VectorClock(), gaps: [], room: nil, reason: .recovery)
        let coded = try JSONDecoder().decode(
            RepairRequest.self, from: try JSONEncoder().encode(asked))
        #expect(coded.reason == .recovery, "the reason did not survive the wire")

        var fields = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(asked))
                as? [String: Any])
        #expect(fields.removeValue(forKey: "reason") != nil, "the reason is not on the wire at all")
        let older = try JSONSerialization.data(withJSONObject: fields)
        let fromAnOlderBuild = try JSONDecoder().decode(RepairRequest.self, from: older)
        #expect(
            fromAnOlderBuild.reason == .gap,
            """
            A request written by a build that predates the reason did not read as an ordinary \
            repair. Anything else would announce every old request as somebody coming back.
            """)
    }

    @Test("The banner says what was seen and does not name a recovery key")
    func theBannerSaysWhatWasSeen() {
        let copy = RestoreNotification.ofAsk(
            person: ParticipantID(rawValue: WideID.of([1])), name: "Griff", roomName: "Kitchen")
        #expect(copy.title.contains("Griff"))
        #expect(copy.body.contains("Kitchen"))
        #expect(
            !copy.title.lowercased().contains("recovery key")
                && !copy.body.lowercased().contains("recovery key"),
            """
            The banner claimed to know a recovery key was used. What this device observed is a \
            device it has not seen before asking for history, which is all it may say.
            """)
    }

    @Test("A banner that may not name people does not name them")
    func aQuietBannerNamesNeither() {
        let copy = RestoreNotification.ofAsk(
            person: ParticipantID(rawValue: WideID.of([1])), name: "Griff", roomName: "Kitchen",
            level: .whereOnly)
        #expect(
            !copy.title.contains("Griff"),
            "a banner set never to name the sender named who came back")
        #expect(copy.body.contains("Kitchen"), "a banner that may name the room did not")
        #expect(
            RestoreNotification.ofAsk(
                person: ParticipantID(rawValue: WideID.of([1])), name: "Griff", roomName: "Kitchen",
                level: .nothing
            ).isGeneric,
            "somebody who asked for no banners got one")
    }
}

@Suite("Holding history until the person asked has checked", .serialized)
@MainActor
struct HoldingHistoryForARestoreTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Rig {
        let original: AppSession
        let peer: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let relay: InMemoryEntrySync.Relay
        let clock: TestClock
        let key: String
        let said: String
    }

    private func rig(peerHolds: Bool) async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")
        await peer.setToldAboutRestores(true)
        await peer.setHoldsHistoryForRestores(peerHolds)
        for session in [original, peer] {
            await session.setSharing(
                NameAndAvatarSharing(
                    sharesName: true, sharesAvatar: false, showsOthersNames: true,
                    showsOthersAvatars: false))
        }

        let room = try await original.createRoom(named: "Kitchen")
        let invite = try await original.invite(
            joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await original.sync(through: mailbox)
        try await peer.accept(
            invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }

        await settle(original) { false }
        let key = try #require(original.recoveryKeyText())

        let said = "said while the phone was gone"
        try await peer.send(said, to: room)
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }
        return Rig(
            original: original, peer: peer, room: room, mailbox: mailbox, relay: relay,
            clock: clock, key: key, said: said)
    }

    private func restoreAndSettle(_ rig: Rig, rounds: Int = 10) async throws -> AppSession {
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: rig.clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: rig.key)
        await settle(fresh) { !fresh.rooms.isEmpty }
        for _ in 0..<rounds {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }
        return fresh
    }

    @Test("Nothing crosses while it is held")
    func nothingCrossesWhileHeld() async throws {
        let rig = try await rig(peerHolds: true)
        let fresh = try await restoreAndSettle(rig)

        #expect(
            !fresh.messages(in: rig.room).contains { $0.body == rig.said },
            """
            History went to a restored device while the person asked had said to hold it. \
            Griff's ruling, 2026-09-13: "nothing crosses until the solo check passes with the \
            restored device".
            """)
        let held = try #require(
            rig.peer.heldRestore(in: rig.room),
            "nothing was put in front of the member to check, so the hold is a silent black hole")
        #expect(held.personName == "Griff")
        #expect(
            held.phrase?.count == PhraseLength.standard.rawValue,
            "the characters to read out were not offered")
    }

    @Test("Saying it matched sends the history")
    func sayingItMatchedSendsIt() async throws {
        let rig = try await rig(peerHolds: true)
        let fresh = try await restoreAndSettle(rig)
        #expect(!fresh.messages(in: rig.room).contains { $0.body == rig.said })

        let held = try #require(rig.peer.heldRestore(in: rig.room))
        await rig.peer.letHistoryThrough(to: held.person)
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            fresh.messages(in: rig.room).contains { $0.body == rig.said },
            "the member said it matched and their history still did not go")
        #expect(
            rig.peer.heldRestore(in: rig.room) == nil,
            "the prompt stayed up after it had been answered")
    }

    @Test("Saying no keeps it, and keeps it after a relaunch")
    func sayingNoKeepsIt() async throws {
        let rig = try await rig(peerHolds: true)
        let fresh = try await restoreAndSettle(rig)

        let held = try #require(rig.peer.heldRestore(in: rig.room))
        await rig.peer.refuseHistory(to: held.person)
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            !fresh.messages(in: rig.room).contains { $0.body == rig.said },
            "history went to somebody the member had refused")
        #expect(rig.peer.heldRestore(in: rig.room) == nil, "a refused ask was still being asked")

        await rig.peer.load()
        for _ in 0..<6 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }
        #expect(
            !fresh.messages(in: rig.room).contains { $0.body == rig.said },
            """
            A relaunch forgot the refusal and sent the history anyway. A decision about somebody \
            else's history has to outlive the process that made it.
            """)
    }

    @Test("Somebody who did not ask to hold sends it straight away")
    func notHoldingSendsStraightAway() async throws {
        let rig = try await rig(peerHolds: false)
        let fresh = try await restoreAndSettle(rig)

        #expect(
            fresh.messages(in: rig.room).contains { $0.body == rig.said },
            "history was held for somebody who never asked for it to be")
        #expect(
            rig.peer.heldRestore(in: rig.room) == nil,
            "a prompt to check was raised for somebody who had not asked to check")
    }

    @Test("Turning the hold off lets what is already waiting through")
    func turningItOffReleasesWhatWaits() async throws {
        let rig = try await rig(peerHolds: true)
        let fresh = try await restoreAndSettle(rig)
        #expect(rig.peer.heldRestore(in: rig.room) != nil)

        await rig.peer.setHoldsHistoryForRestores(false)
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            fresh.messages(in: rig.room).contains { $0.body == rig.said },
            """
            Somebody turned the setting off and the ask that was already waiting stayed stuck. \
            Turning it off has to mean what it says, or the only way out is a prompt they have \
            just told the app to stop showing.
            """)
    }

    @Test("An ordinary repair is never held")
    func anOrdinaryRepairIsNeverHeld() async throws {
        let rig = try await rig(peerHolds: true)
        _ = await rig.original.startRepair(in: rig.room)
        for _ in 0..<8 {
            for session in [rig.original, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            rig.peer.heldRestore(in: rig.room) == nil,
            "a repair that was nobody coming back was held as though somebody had")
    }
}

@Suite("Choosing not to ask anybody for your history", .serialized)
@MainActor
struct NotAskingForHistoryTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Rig {
        let original: AppSession
        let peer: AppSession
        let room: RoomID
        let mailbox: InMemoryMailbox
        let relay: InMemoryEntrySync.Relay
        let clock: TestClock
        let key: String
        let said: String
    }

    private func rig() async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")
        await peer.setToldAboutRestores(true)

        let room = try await original.createRoom(named: "Kitchen")
        let invite = try await original.invite(
            joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await original.sync(through: mailbox)
        try await peer.accept(
            invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }

        await settle(original) { false }
        let key = try #require(original.recoveryKeyText())

        let said = "said while the phone was gone"
        try await peer.send(said, to: room)
        for _ in 0..<6 {
            for session in [original, peer] { try await session.sync(through: mailbox) }
        }
        return Rig(
            original: original, peer: peer, room: room, mailbox: mailbox, relay: relay,
            clock: clock, key: key, said: said)
    }

    private func restore(_ rig: Rig, askingPeers: Bool) async throws -> AppSession {
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: rig.clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: rig.key, askingPeers: askingPeers)
        await settle(fresh) { !fresh.rooms.isEmpty }
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }
        return fresh
    }

    @Test("Nobody is asked, and nobody is told")
    func nobodyIsAskedAndNobodyIsTold() async throws {
        let rig = try await rig()
        let fresh = try await restore(rig, askingPeers: false)

        #expect(
            !fresh.messages(in: rig.room).contains { $0.body == rig.said },
            "a restore that asked nobody was handed history anyway")
        #expect(
            rig.peer.latestRestoreAsk() == nil,
            """
            Somebody was told about a restore that chose not to announce itself. Griff's ruling: \
            off is "for somebody who would rather not announce a restore to everybody they know", \
            so a silent restore has to actually be silent.
            """)
    }

    @Test("The rooms still come back, just empty")
    func theRoomsStillComeBack() async throws {
        let rig = try await rig()
        let fresh = try await restore(rig, askingPeers: false)

        #expect(
            !fresh.rooms.isEmpty,
            """
            Choosing not to ask peers took the rooms away too. The ruling is that the key restores \
            the identity and "the rooms come back empty" — empty, not absent.
            """)
    }

    @Test("Asking is what happens if you do not say otherwise")
    func askingIsTheDefault() async throws {
        let rig = try await rig()
        let fresh = try await restore(rig, askingPeers: true)

        #expect(fresh.isAskingPeersForHistory, "the default is not on")
        #expect(
            fresh.messages(in: rig.room).contains { $0.body == rig.said },
            "the ordinary restore stopped asking for history")
    }

    @Test("Changing your mind afterwards asks after all")
    func changingYourMindAsksAfterAll() async throws {
        let rig = try await rig()
        let fresh = try await restore(rig, askingPeers: false)
        #expect(!fresh.messages(in: rig.room).contains { $0.body == rig.said })

        await fresh.setAsksPeersForHistory(true)
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            fresh.messages(in: rig.room).contains { $0.body == rig.said },
            """
            Turning it back on did nothing, so a member who said no at the restore screen can \
            never get their history — and the screen's own copy promises they can.
            """)
    }

    @Test("A device that never restored does not start asking")
    func aDeviceThatNeverRestoredDoesNotAsk() async throws {
        let rig = try await rig()
        #expect(rig.peer.isAskingPeersForHistory, "the default is not on")

        await rig.peer.setAsksPeersForHistory(false)
        await rig.peer.setAsksPeersForHistory(true)
        for _ in 0..<6 {
            for session in [rig.original, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            rig.original.latestRestoreAsk() == nil,
            """
            Toggling the setting on a device that never came back from a key announced a restore \
            that never happened.
            """)
    }
}

@Suite("Turning every key after a device was lost", .serialized)
@MainActor
struct TurningEveryKeyAfterALossTests {
    private func settle(_ session: AppSession, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            await session.refreshDeviceSync()
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private struct Rig {
        let original: AppSession
        let peer: AppSession
        let kitchen: RoomID
        let hangar: RoomID
        let mailbox: InMemoryMailbox
        let relay: InMemoryEntrySync.Relay
        let clock: TestClock
        let key: String
    }

    private func rig() async throws -> Rig {
        let mailbox = InMemoryMailbox()
        let clock = TestClock(now: TestSession.now)
        let relay = InMemoryEntrySync.Relay()

        let original = TestSession.make(keychain: InMemoryKeychainStore(), clock: clock)
        let peer = TestSession.make(clock: clock)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        for session in [original, peer] { await session.load() }
        try await original.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")

        var made: [RoomID] = []
        for name in ["Kitchen", "Hangar"] {
            let room = try await original.createRoom(named: name)
            let invite = try await original.invite(
                joinerCode: peer.identityCode(), joining: room, mailbox: nil)
            try await peer.redeem(inviteCode: try invite.encoded())
            try await original.sync(through: mailbox)
            try await peer.accept(
                invite.attestation, from: try #require(original.enrolment?.identity.publicKeys))
            for _ in 0..<6 {
                for session in [original, peer] { try await session.sync(through: mailbox) }
            }
            made.append(room)
        }

        await settle(original) { false }
        return Rig(
            original: original, peer: peer, kitchen: made[0], hangar: made[1], mailbox: mailbox,
            relay: relay, clock: clock, key: try #require(original.recoveryKeyText()))
    }

    private func restore(_ rig: Rig, afterALoss: Bool) async throws -> AppSession {
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: rig.clock)
        fresh.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: rig.key, afterALoss: afterALoss)
        await settle(fresh) { fresh.rooms.count == 2 }
        for _ in 0..<12 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }
        return fresh
    }

    private func epoch(_ session: AppSession, _ room: RoomID) -> Int {
        session.epochsHeld(in: room)
    }

    @Test("Saying a device was lost turns the key in every room, not just one")
    func sayingLostTurnsEveryKey() async throws {
        let rig = try await rig()
        let before = [
            rig.kitchen: epoch(rig.original, rig.kitchen),
            rig.hangar: epoch(rig.original, rig.hangar),
        ]
        let fresh = try await restore(rig, afterALoss: true)

        for room in [rig.kitchen, rig.hangar] {
            #expect(
                epoch(fresh, room) > (before[room] ?? 0),
                """
                A room's key did not turn after the member said a device was lost. Griff's ruling, \
                2026-09-13: "a yes turns the key in every room" — every one, because a stolen phone \
                is in every room the member is in.
                """)
        }
        #expect(
            !fresh.isTurningEveryKeyAfterALoss,
            "the turn was never marked done, so every round would turn the keys again")
    }

    @Test("Saying no turns nothing")
    func sayingNoTurnsNothing() async throws {
        let rig = try await rig()
        let before = epoch(rig.original, rig.kitchen)
        let fresh = try await restore(rig, afterALoss: false)

        #expect(
            epoch(fresh, rig.kitchen) == before,
            """
            A key turned on a restore where nothing was lost. A turn is not free and not \
            reversible, and "I restored onto a new laptop" is not "my phone was taken".
            """)
    }

    @Test("The peer keeps up with the new key")
    func thePeerKeepsUp() async throws {
        let rig = try await rig()
        let fresh = try await restore(rig, afterALoss: true)

        try await fresh.send("after the key turned", to: rig.kitchen)
        for _ in 0..<10 {
            for session in [fresh, rig.peer] { try await session.sync(through: rig.mailbox) }
        }

        #expect(
            rig.peer.messages(in: rig.kitchen).contains { $0.body == "after the key turned" },
            """
            Turning every key locked the people still in the room out of it. The turn is meant to \
            cut off a device that is gone, not the members who are still there.
            """)
    }

    @Test("The answer outlives a relaunch before the rooms arrive")
    func theAnswerOutlivesARelaunch() async throws {
        let rig = try await rig()
        let fresh = TestSession.make(keychain: InMemoryKeychainStore(), clock: rig.clock)
        await fresh.load()
        try await fresh.restore(fromRecoveryKey: rig.key, afterALoss: true)

        #expect(
            fresh.isTurningEveryKeyAfterALoss,
            "nothing recorded the answer, so a relaunch before the rooms arrive loses it")

        await fresh.load()
        #expect(
            fresh.isTurningEveryKeyAfterALoss,
            """
            The answer was forgotten on a relaunch. The rooms come back from the member's own \
            iCloud several rounds after the restore, so the answer has to outlive the launch that \
            took it or the keys never turn.
            """)
    }
}
