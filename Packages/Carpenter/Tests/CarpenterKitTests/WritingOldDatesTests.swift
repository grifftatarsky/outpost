@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("A removed device cannot write itself back in with old dates")
struct WhatTheRegistryCountsTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)
    private let identity = Identity.generate()

    private struct Devices {
        let phone = DeviceKeys.generate()
        let tablet = DeviceKeys.generate()
        let stolen = DeviceKeys.generate()
        let fresh = DeviceKeys.generate()
    }

    private func removedStolenDevice(_ devices: Devices) throws -> DeviceRegistry {
        var registry = DeviceRegistry(identity: identity.publicKeys)
        try registry.admit(
            DeviceCertificate.recovered(for: devices.phone, by: identity, at: start), storedAt: start)
        try registry.admit(
            DeviceCertificate.issue(for: devices.tablet, by: identity, at: start + 10, approvedBy: devices.phone),
            storedAt: start + 10)
        try registry.admit(
            DeviceCertificate.issue(for: devices.stolen, by: identity, at: start + 20, approvedBy: devices.phone),
            storedAt: start + 20)
        try registry.revoke(
            DeviceRevocation.issue(for: devices.stolen.id, by: identity, at: start + 1000, from: devices.phone),
            storedAt: start + 1000)
        return registry
    }

    @Test("An approval stored after its approver was removed does not count, whatever date it carries")
    func aBackDatedApprovalDoesNotCount() throws {
        let devices = Devices()
        var registry = try removedStolenDevice(devices)
        try registry.admit(
            DeviceCertificate.issue(for: devices.fresh, by: identity, at: start + 500, approvedBy: devices.stolen),
            storedAt: start + 2000)
        #expect(!registry.activeDevices.contains(devices.fresh.id))
        #expect(registry.standing(of: devices.fresh.id) == nil)
    }

    @Test("Removals stored after their author was removed do not count, and the author stays removed")
    func backDatedRemovalsDoNotCount() throws {
        let devices = Devices()
        var registry = try removedStolenDevice(devices)
        for target in [devices.phone.id, devices.tablet.id] {
            try registry.revoke(
                DeviceRevocation.issue(for: target, by: identity, at: start + 900, from: devices.stolen),
                storedAt: start + 2000)
        }
        #expect(registry.activeDevices == [devices.phone.id, devices.tablet.id])
        #expect(registry.standing(of: devices.stolen.id)?.revokedAt != nil)
    }

    @Test("An approval stored before its approver was removed still counts")
    func anApprovalBeforeTheRemovalCounts() throws {
        let devices = Devices()
        var registry = try removedStolenDevice(devices)
        try registry.admit(
            DeviceCertificate.issue(for: devices.fresh, by: identity, at: start + 500, approvedBy: devices.stolen),
            storedAt: start + 500)
        #expect(registry.activeDevices.contains(devices.fresh.id))
    }

    @Test("The order things arrive in does not change what counts")
    func arrivalOrderDoesNotMatter() throws {
        let devices = Devices()
        let events: [(AuthorityEvent, Date)] = [
            (.added(try DeviceCertificate.recovered(for: devices.phone, by: identity, at: start)), start),
            (.added(try DeviceCertificate.issue(
                for: devices.stolen, by: identity, at: start + 20, approvedBy: devices.phone)), start + 20),
            (.removed(try DeviceRevocation.issue(
                for: devices.stolen.id, by: identity, at: start + 1000, from: devices.phone)), start + 1000),
            (.added(try DeviceCertificate.issue(
                for: devices.fresh, by: identity, at: start + 500, approvedBy: devices.stolen)), start + 2000),
            (.removed(try DeviceRevocation.issue(
                for: devices.phone.id, by: identity, at: start + 900, from: devices.stolen)), start + 2001),
        ]
        var results: Set<Set<DeviceID>> = []
        for _ in 0..<20 {
            var registry = DeviceRegistry(identity: identity.publicKeys)
            var remaining = events.shuffled()
            var stalled = 0
            while !remaining.isEmpty, stalled < 50 {
                let (event, at) = remaining.removeFirst()
                do {
                    switch event {
                    case .added(let certificate): try registry.admit(certificate, storedAt: at)
                    case .removed(let revocation): try registry.revoke(revocation, storedAt: at)
                    }
                } catch CryptoError.unknownDevice {
                    remaining.append((event, at))
                    stalled += 1
                }
            }
            results.insert(registry.activeDevices)
        }
        #expect(results == [[devices.phone.id]])
    }

    @Test("Hearing of an approval again, later, never moves it later")
    func aLaterSightingDoesNotMoveAnEvent() throws {
        let devices = Devices()
        var registry = try removedStolenDevice(devices)
        let approval = try DeviceCertificate.issue(
            for: devices.fresh, by: identity, at: start + 500, approvedBy: devices.stolen)
        try registry.admit(approval, storedAt: start + 500)
        try registry.admit(approval, storedAt: start + 5000)
        #expect(registry.storedAt(approval.digest) == start + 500)
        #expect(registry.activeDevices.contains(devices.fresh.id))
    }

    @Test("A removal signed by the identity key alone is refused")
    func aRemovalNeedsADevice() throws {
        let devices = Devices()
        var registry = try removedStolenDevice(devices)
        #expect(throws: CryptoError.notAuthorized) {
            try registry.revoke(
                DeviceRevocation.issue(for: devices.phone.id, by: identity, at: start + 3000),
                storedAt: start + 3000)
        }
        #expect(registry.activeDevices.contains(devices.phone.id))
    }

    @Test("A stored approval whose contents do not match its name is refused")
    func aRewrittenRecordIsRefused() throws {
        let devices = Devices()
        let real = AuthorityEvent.added(
            try DeviceCertificate.issue(for: devices.tablet, by: identity, at: start, approvedBy: devices.phone))
        let forged = AuthorityEvent.added(
            try DeviceCertificate.issue(for: devices.fresh, by: identity, at: start, approvedBy: devices.stolen))
        let name = try real.record(sealedFor: identity, by: devices.phone.id).name
        let rewritten = SiblingRecord(
            name: name,
            sealed: try SealedSiblingFeed.seal(
                SiblingFeed(entries: [], certificates: [forged.certificate!], member: identity.id),
                for: identity, on: devices.phone.id, as: name.kind))
        #expect(throws: CryptoError.openFailed) {
            try AuthorityEvent(record: rewritten, openedWith: identity)
        }
        #expect(try AuthorityEvent(record: try real.record(sealedFor: identity, by: devices.phone.id), openedWith: identity) == real)
    }

    @Test("Another member counts a removed device's approval by when its packet was stored, not by its date")
    func aPeerOrdersByStoredPackets() throws {
        let devices = Devices()
        var replica = Replica()
        replica.introduce(identity.publicKeys)
        let phone = try DeviceCertificate.recovered(for: devices.phone, by: identity, at: start)
        let stolen = try DeviceCertificate.issue(for: devices.stolen, by: identity, at: start + 20, approvedBy: devices.phone)
        let removal = try DeviceRevocation.issue(for: devices.stolen.id, by: identity, at: start + 1000, from: devices.phone)
        let backDated = try DeviceCertificate.issue(
            for: devices.fresh, by: identity, at: start + 500, approvedBy: devices.stolen)

        func packet(_ certificates: [DeviceCertificate], _ revocations: [DeviceRevocation], storedAt: Date)
            -> SyncSession.CollectedPackets.Opened
        {
            SyncSession.CollectedPackets.Opened(
                id: PacketID(),
                delivery: SyncEngine.Delivery(
                    entries: [], certificates: certificates, revocations: revocations, grants: []),
                storedAt: storedAt)
        }
        let collected = SyncSession.CollectedPackets(
            tags: [],
            packets: [
                packet([phone, stolen], [], storedAt: start + 30),
                packet([backDated], [], storedAt: start + 2000),
                packet([], [removal], storedAt: start + 1000),
            ])
        SyncSession.integrate(collected, into: &replica)
        let registry = try #require(replica.registry(for: identity.id))
        #expect(!registry.activeDevices.contains(devices.fresh.id))
        #expect(registry.activeDevices == [devices.phone.id])
    }
}

extension AuthorityEvent {
    fileprivate var certificate: DeviceCertificate? {
        if case .added(let certificate) = self { return certificate }
        return nil
    }
}

@Suite("Your devices ignore a removed device writing old dates into iCloud", .serialized)
@MainActor
struct WritingOldDatesIntoICloudTests {
    private struct Rig {
        let original: AppSession
        let second: AppSession
        let stolen: AppSession
        let relay: InMemoryEntrySync.Relay
        let identity: Identity
        let stolenKeys: DeviceKeys
        let keychain: InMemoryKeychainStore
    }

    private func settle(_ sessions: [AppSession], rounds: Int = 4) async {
        for _ in 0..<rounds {
            for session in sessions {
                await session.refreshDeviceSync()
                await session.settleDeviceSync()
            }
        }
    }

    private func rig() async throws -> Rig {
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let original = TestSession.make(keychain: keychain)
        original.syncDevices(through: InMemoryEntrySync(relay: relay))
        await original.load()
        try await original.createIdentity(displayName: "Griff")

        let second = TestSession.make(keychain: await keychain.sibling())
        second.syncDevices(through: InMemoryEntrySync(relay: relay))
        await second.load()
        try await original.approveNewDevice(second)

        let stolen = TestSession.make(keychain: await keychain.sibling())
        stolen.syncDevices(through: InMemoryEntrySync(relay: relay))
        await stolen.load()
        try await original.approveNewDevice(stolen)
        await settle([original, second, stolen])

        let identity = try #require(original.enrolment?.identity)
        let stolenKeys = try #require(stolen.enrolment?.device)
        try await original.revoke(stolenKeys.id)
        await settle([original, second, stolen])
        return Rig(
            original: original, second: second, stolen: stolen, relay: relay, identity: identity,
            stolenKeys: stolenKeys, keychain: keychain)
    }

    private func active(_ session: AppSession, _ identity: Identity) -> Set<DeviceID> {
        session.replica.registry(for: identity.id)?.activeDevices ?? []
    }

    @Test("Approvals and removals a removed device dates in the past change nothing, and nothing is erased")
    func oldDatesChangeNothing() async throws {
        let rig = try await rig()
        #expect(rig.stolen.state == .removed, "precondition: the stolen device heard it was removed")
        let original = try #require(rig.original.enrolment?.device.id)
        let second = try #require(rig.second.enrolment?.device.id)
        let fresh = DeviceKeys.generate()
        let past = TestSession.now.addingTimeInterval(-3_600)

        let approval = AuthorityEvent.added(
            try DeviceCertificate.issue(for: fresh, by: rig.identity, at: past, approvedBy: rig.stolenKeys))
        let removals = try [original, second].map {
            AuthorityEvent.removed(
                try DeviceRevocation.issue(for: $0, by: rig.identity, at: past, from: rig.stolenKeys))
        }
        for event in [approval] + removals {
            let record = try event.record(sealedFor: rig.identity, by: rig.stolenKeys.id)
            try await rig.relay.place(record.name, record.sealed)
        }
        let forgedState = try SealedSiblingFeed.seal(
            SiblingFeed(
                entries: [], certificates: [approval.certificate!], member: rig.identity.id,
                revocations: removals.compactMap(\.revocation)),
            for: rig.identity, on: rig.stolenKeys.id, as: .state)
        try await rig.relay.place(SiblingRecord.Name(writer: rig.stolenKeys.id, kind: .state), forgedState)
        await settle([rig.original, rig.second])

        for session in [rig.original, rig.second] {
            #expect(session.state != .removed, "a back-dated removal erased one of the member's devices")
            #expect(session.enrolment != nil)
            #expect(active(session, rig.identity) == [original, second])
            #expect(!session.devices.contains { $0.id == fresh.id && $0.isActive })
        }
    }

    @Test("Rewriting an approval iCloud already holds keeps its old time but not its new contents")
    func aRewrittenApprovalIsRefused() async throws {
        let rig = try await rig()
        let second = try #require(rig.second.enrolment?.device.id)
        let registry = try #require(rig.original.replica.registry(for: rig.identity.id))
        let secondsApproval = try #require(registry.certificates.first { $0.device == second })
        let name = SiblingRecord.Name(
            writer: try #require(rig.original.enrolment?.device.id), kind: .authority(secondsApproval.digest))
        let created = try #require(await rig.relay.created(name), "precondition: the approval was stored")

        let fresh = DeviceKeys.generate()
        let forged = try DeviceCertificate.issue(
            for: fresh, by: rig.identity, at: TestSession.now, approvedBy: rig.stolenKeys)
        try await rig.relay.rewrite(
            name,
            try SealedSiblingFeed.seal(
                SiblingFeed(entries: [], certificates: [forged], member: rig.identity.id),
                for: rig.identity, on: name.writer, as: name.kind))
        #expect(await rig.relay.created(name) == created, "the fake did not keep the first-stored time")

        let newcomer = TestSession.make(keychain: await rig.keychain.sibling())
        newcomer.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await newcomer.load()
        try await rig.original.approveNewDevice(newcomer)
        await settle([rig.original, rig.second, newcomer])

        for session in [rig.original, rig.second, newcomer] {
            #expect(!active(session, rig.identity).contains(fresh.id))
            #expect(!active(session, rig.identity).contains(rig.stolenKeys.id))
        }
    }

    @Test("A device approved after the removal sees the same devices as the others")
    func aLaterDeviceAgrees() async throws {
        let rig = try await rig()
        let newcomer = TestSession.make(keychain: await rig.keychain.sibling())
        newcomer.syncDevices(through: InMemoryEntrySync(relay: rig.relay))
        await newcomer.load()
        try await rig.second.approveNewDevice(newcomer)
        await settle([rig.original, rig.second, newcomer])
        #expect(active(newcomer, rig.identity) == active(rig.original, rig.identity))
        #expect(!active(newcomer, rig.identity).contains(rig.stolenKeys.id))
    }

    @Test("Your devices learn from iCloud when their own approvals and removals were stored")
    func ownEventsTakeICloudsTime() async throws {
        let rig = try await rig()
        let original = try #require(rig.original.enrolment?.device.id)
        let removal = try #require(
            rig.original.replica.registry(for: rig.identity.id)?.knownRevocations.first {
                $0.device == rig.stolenKeys.id
            })
        let name = SiblingRecord.Name(writer: original, kind: .authority(removal.digest))
        let created = try #require(await rig.relay.created(name), "the removal never reached iCloud")
        #expect(rig.original.replica.registry(for: rig.identity.id)?.storedAt(removal.digest) == created)
    }
}

extension AuthorityEvent {
    fileprivate var revocation: DeviceRevocation? {
        if case .removed(let revocation) = self { return revocation }
        return nil
    }
}

@Suite("Another member remembers your removals", .serialized)
@MainActor
struct RemembersRemovalsTests {
    @Test("A member still knows another member's removed device after relaunching")
    func removalsSurviveARelaunch() async throws {
        let mailbox = InMemoryMailbox()
        let relay = InMemoryEntrySync.Relay()
        let keychain = InMemoryKeychainStore()
        let griff = TestSession.make(keychain: keychain)
        griff.syncDevices(through: InMemoryEntrySync(relay: relay))
        let peerKeychain = InMemoryKeychainStore()
        let directory = TestScratch.root.appending(path: "carpenter-peer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let peer = TestSession.make(keychain: peerKeychain, at: directory)
        for session in [griff, peer] { await session.load() }
        try await griff.createIdentity(displayName: "Griff")
        try await peer.createIdentity(displayName: "Outie")

        let tablet = TestSession.make(keychain: await keychain.sibling())
        tablet.syncDevices(through: InMemoryEntrySync(relay: relay))
        await tablet.load()
        try await griff.approveNewDevice(tablet)

        let room = try await griff.createRoom(named: "Kitchen")
        let invite = try await griff.invite(joinerCode: peer.identityCode(), joining: room, mailbox: nil)
        try await peer.redeem(inviteCode: try invite.encoded())
        try await griff.sync(through: mailbox)
        try await peer.accept(invite.attestation, from: try #require(griff.enrolment?.identity.publicKeys))
        for _ in 0..<6 {
            for session in [griff, peer] { try await session.sync(through: mailbox) }
        }
        let identity = try #require(griff.enrolment?.identity)
        let tabletID = try #require(tablet.enrolment?.device.id)
        #expect(peer.replica.registry(for: identity.id)?.activeDevices.contains(tabletID) == true)

        try await griff.revoke(tabletID)
        for _ in 0..<6 {
            for session in [griff, peer] { try await session.sync(through: mailbox) }
        }
        #expect(peer.replica.registry(for: identity.id)?.activeDevices.contains(tabletID) == false)

        let relaunched = TestSession.make(keychain: peerKeychain, at: directory)
        await relaunched.load()
        #expect(
            relaunched.replica.registry(for: identity.id)?.activeDevices.contains(tabletID) == false,
            "after relaunching, the other member counted a removed device again")
    }
}
