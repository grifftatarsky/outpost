import CloudKit
import Foundation
import Testing

@testable import CarpenterCloudKit
@testable import CarpenterKit

@Suite("CloudKit packet serialisation")
struct CloudKitPacketRecordTests {
    @Test("A packet round-trips through a CKRecord with its grant intact")
    func grantSurvivesRecordRoundTrip() throws {
        let alice = Identity.generate()
        let bob = Identity.generate()
        let toBob = try PairwiseSecret.derive(mine: alice, theirs: bob.publicKeys)
        let peerToBob = Peer(secret: toBob, them: bob.id, me: alice.id)

        let room = ConversationID.room(UUID())
        let (_, secret) = EpochChain.create(room: room)
        let grant = try EpochGrant.issue(secret, at: .initial, in: room, link: nil, to: toBob)

        let packet = try SyncEngine.pack(
            [], for: [peerToBob], granting: [(to: peerToBob, grant: grant)], window: 0)
        #expect(!packet.grants.isEmpty, "precondition: pack produced a grant to carry")

        let record = CKRecord(
            recordType: PacketRecord.type,
            recordID: CKRecord.ID(
                recordName: packet.id.recordName, zoneID: CKRecordZone.ID(zoneName: "Outbox")))
        try PacketRecord.write(packet, into: record)
        let restored = try #require(PacketRecord.read(record))

        #expect(restored.grants == packet.grants, "the CloudKit mapping dropped the grant")

        let bobPeer = Peer(secret: toBob, them: alice.id, me: bob.id)
        let delivery = try SyncEngine.unpack(restored, as: bobPeer, window: 0)
        #expect(delivery.grants.count == 1)
        #expect(try delivery.grants.first?.open(with: toBob) == secret)
    }
}
