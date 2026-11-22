import CarpenterCloudKit
import CarpenterKit
import CarpenterKitTesting
import CloudKit
import Foundation
import Testing

enum LiveCloudKit {
    static let flag = "CARPENTER_CLOUDKIT_TESTS"

    static var isAsked: Bool {
        ProcessInfo.processInfo.environment[flag] == "1"
    }

    static func mailbox() async throws -> CloudKitMailbox {
        let container = CKContainer.default()

        var status = try await container.accountStatus()
        var waited = 0
        while status == .temporarilyUnavailable || status == .couldNotDetermine, waited < 10 {
            try? await Task.sleep(for: .seconds(2))
            waited += 1
            status = try await container.accountStatus()
        }

        guard status == .available else {
            Issue.record(
                """
                \(flag) is set but this device's iCloud account is not usable (\(status)) after \
                \(waited) retr(ies). These tests are the only thing that reads the real wire \
                format; a skip here is a gap, not a pass. temporarilyUnavailable and \
                couldNotDetermine are retried because a simulator reports them for a while after \
                it boots; noAccount means sign in on the device.
                """)
            throw CancellationError()
        }
        return CloudKitMailbox(container: container)
    }

    static func afterWrite(_ cloud: CloudKitMailbox) -> MailboxContract.AfterWrite {
        {
            try await Task.sleep(for: .seconds(2.5))
            await cloud.lookAgain()
        }
    }

    static func tag() -> RecipientTag {
        RecipientTag(rawValue: Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    static func bytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }
}

@Suite(
    "Spaces of one's own against a real CloudKit account",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
struct CloudKitMailboxTests {
    private struct Two {
        let mailbox: CloudKitMailbox
        let me: Identity
        let them: Identity
        let toThem: Peer
        var pairs: Pairs { Pairs.of(toThem) }
    }

    private func two() async throws -> Two {
        let mailbox = try await LiveCloudKit.mailbox()
        try await mailbox.eraseEverySpace()
        let (me, them) = (Identity.generate(), Identity.generate())
        let toThem = Peer(secret: try PairwiseSecret.derive(mine: me, theirs: them.publicKeys), them: them.id, me: me.id)
        return Two(mailbox: mailbox, me: me, them: them, toThem: toThem)
    }

    private func share(_ url: URL, in mailbox: CloudKitMailbox) async throws -> CKShare {
        let metadata = try await CKContainer.default().shareMetadata(for: url)
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: metadata.share.recordID.zoneID)
        return try #require(try await CKContainer.default().privateCloudDatabase.record(for: id) as? CKShare)
    }

    @Test("A space for one person is shared with nobody until that person is named, and then with them alone")
    func aSpaceIsSharedWithOnePerson() async throws {
        let t = try await two()
        let url = try await t.mailbox.space(for: t.them.id, naming: nil, in: t.pairs)
        let bare = try await share(url, in: t.mailbox)
        #expect(bare.publicPermission == .none, "a space's link opens for anybody who holds it")
        #expect(bare.participants.filter { $0.role != .owner }.isEmpty, "a space named somebody before anybody was named")

        let exchange = URL(filePath: "/tmp/outpost-rig-exchange/pairs/beta-user.json")
        guard let data = try? Data(contentsOf: exchange), let beta = try? JSONDecoder().decode(String.self, from: data)
        else { return }
        _ = try await t.mailbox.space(for: t.them.id, naming: beta, in: t.pairs)
        let named = try await share(url, in: t.mailbox)
        let others = named.participants.filter { $0.role != .owner }
        #expect(others.count == 1)
        #expect(others.first?.userIdentity.userRecordID?.recordName == beta)
        #expect(others.first?.permission == .readOnly, "the person a space is for can write into it")
        #expect(named.publicPermission == .none)
    }

    private func fresh() async throws -> CloudKitMailbox {
        let cloud = try await LiveCloudKit.mailbox()
        try await cloud.eraseEverySpace()
        return cloud
    }

    @Test("A packet put is listed with the recipients and contents it was put with")
    func aPutPacketIsListed() async throws {
        let cloud = try await fresh()
        try await MailboxContract.aPutPacketIsListed(in: cloud, afterWrite: LiveCloudKit.afterWrite(cloud))
    }

    @Test("A packet over the record ceiling is refused before anything is stored, and one at the budget goes")
    func theRecordCeilingHolds() async throws {
        let cloud = try await fresh()
        try await MailboxContract.theRecordCeilingHolds(in: cloud, afterWrite: LiveCloudKit.afterWrite(cloud))
    }

    @Test("A withdrawn packet is no longer listed")
    func aWithdrawnPacketIsNoLongerListed() async throws {
        let cloud = try await fresh()
        try await MailboxContract.aWithdrawnPacketIsNoLongerListed(in: cloud, afterWrite: LiveCloudKit.afterWrite(cloud))
    }

    @Test("A person's space is found again, a space for a code is new each time, and claiming one makes it theirs")
    func spacesAreFoundAgainAndCodesAreNew() async throws {
        let cloud = try await fresh()
        try await MailboxContract.spacesAreFoundAgainAndCodesAreNew(in: cloud, afterWrite: LiveCloudKit.afterWrite(cloud))
    }

    @Test("A photo is stored once for each person it is for, and writing it again keeps when it was first stored")
    func aPhotoIsOneCopyPerPerson() async throws {
        let cloud = try await fresh()
        try await MailboxContract.aPhotoIsOneCopyPerPerson(in: cloud, afterWrite: LiveCloudKit.afterWrite(cloud))
    }

    @Test("A photo far over the record ceiling goes as an asset, one copy for each person it is for")
    func aPhotoGoesAsACopyEach() async throws {
        let t = try await two()
        let other = Identity.generate()
        let toOther = Peer(secret: try PairwiseSecret.derive(mine: t.me, theirs: other.publicKeys), them: other.id, me: t.me.id)
        let pairs = Pairs.of(t.toThem, toOther)
        let secrets = [t.them.id: t.toThem.secret, other.id: toOther.secret]
        let copies = try OutgoingAttachment(
            id: AttachmentID(), ciphertext: LiveCloudKit.bytes(3 * MailboxRules.recordByteCeiling),
            recipients: [t.them.id: t.toThem.outgoingTag(window: 1), other.id: toOther.outgoingTag(window: 1)]
        ).copies(between: { secrets[$0] })
        try await t.mailbox.upload(copies, in: pairs)
        let stored = try await t.mailbox.storedCopies(in: pairs)
        #expect(Set(stored.map(\.name)) == Set(copies.copies.values.map(\.name)), "a copy is missing, or named twice")
        #expect(Set(stored.flatMap(\.recipients)) == [t.toThem.outgoingTag(window: 1), toOther.outgoingTag(window: 1)])
        #expect(stored.allSatisfy { $0.receipts.isEmpty })

        try await t.mailbox.delete(copies: Set(stored.map(\.name)), in: pairs)
        #expect(try await t.mailbox.storedCopies(in: pairs).isEmpty, "a deleted photo left a copy behind")
    }

    @Test("Erasing every space leaves none of them, and none of their links")
    func erasingLeavesNothing() async throws {
        let t = try await two()
        _ = try await t.mailbox.space(for: t.them.id, naming: nil, in: t.pairs)
        _ = try await t.mailbox.spaceForACode(in: t.pairs)
        try await t.mailbox.eraseEverySpace()
        let left = try await CKContainer.default().privateCloudDatabase.allRecordZones().map(\.zoneID.zoneName)
        #expect(!left.contains { $0.hasPrefix("Pair-") }, "a space outlived erasing: \(left)")
    }
}
