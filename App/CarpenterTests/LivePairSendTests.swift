@testable import CarpenterApp
import CarpenterCloudKit
import CarpenterKit
import CarpenterKitTesting
import CloudKit
import Foundation
import Testing

@Suite(
    "Two people on two iCloud accounts: a Solo from the list of people, and collecting before a message is written",
    .enabled(if: LiveCloudKit.isAsked && !LivePairRun.role.isEmpty),
    .serialized)
@MainActor
struct LivePairSendTests {
    private func keyLastWrittenUnder(by session: AppSession, in room: RoomID) -> EpochNumber? {
        let me = session.enrolment?.identity.id
        return session.replica.allEntries.filter { $0.author == me && $0.room == room }
            .max { $0.seq < $1.seq }?.payload.epoch
    }

    private func rounds(_ count: Int, _ session: AppSession, through cloud: CloudKitMailbox) async throws {
        for _ in 0..<count {
            try await session.sync(through: cloud, media: cloud)
            try await Task.sleep(for: .seconds(2))
        }
    }

    @Test(.enabled(if: LivePairRun.role == "ann"))
    func ann() async throws {
        let cloud = try await LiveCloudKit.mailbox()
        try? await cloud.eraseEverySpace()
        let ann = LivePair.session()
        await ann.load()
        try await ann.createIdentity(displayName: "Ann")
        let room = try await ann.createRoom(named: "Kettle")

        let code = try await LivePair.waitFor("ben-code")
        let invite = try await ann.invite(joinerCode: code, joining: room, through: cloud)
        try LivePair.leave(try invite.encoded(), as: "ann-invite")
        let benID = try JoinerCode.decoded(from: code).participantID
        try await LivePair.until("Ben to join the room", ann, through: cloud) {
            ann.roster(of: room).members.contains(benID)
        }

        let solo = try await ann.startSolo(with: benID)
        let direct = try await ann.invite(benID, joining: solo, through: cloud)
        try LivePair.leave(try direct.encoded(), as: "ann-solo-invite")
        try await LivePair.until("Ben to be in the Solo", ann, through: cloud) {
            ann.roster(of: solo).members.contains(benID)
        }
        try LivePair.leave(try #require(ann.phrase(for: direct.attestation)), as: "ann-phrase")
        try await LivePair.until("Ben to say he is in the Solo", ann, through: cloud) {
            FileManager.default.fileExists(atPath: LivePair.folder.appending(path: "ben-in-solo").path)
        }

        _ = try await LivePair.waitFor("ben-is-quiet")
        let before = try #require(ann.epoch(of: room))
        try await ann.oweKeyRotation(in: room)
        try await ann.rotateOwedKey(in: room)
        try await ann.send("under the new key", to: room)
        let newest = try #require(ann.epoch(of: room))
        #expect(newest > before, "the room's key did not change")
        try await rounds(2, ann, through: cloud)
        try LivePair.leave(String(newest.rawValue), as: "ann-new-key")

        #expect(try await LivePair.waitFor("ben-wrote-under") == String(newest.rawValue))
        try await LivePair.until("Ben's message under the new key", ann, through: cloud) {
            ann.messages(in: room).contains { $0.body == "after the key change" }
        }

        try await ann.remove(benID, from: room)
        try await rounds(2, ann, through: cloud)
        try LivePair.leave("removed", as: "ann-removed-ben")
        _ = try await LivePair.waitFor("ben-refused")
        try? await cloud.eraseEverySpace()
    }

    @Test(.enabled(if: LivePairRun.role == "ben"))
    func ben() async throws {
        let cloud = try await LiveCloudKit.mailbox()
        try? await cloud.eraseEverySpace()
        let ben = LivePair.session()
        await ben.load()
        try await ben.createIdentity(displayName: "Ben")
        let me = try #require(ben.enrolment?.identity.id)
        try LivePair.leave(await ben.joinerCode(through: cloud), as: "ben-code")

        let invite = try await ben.redeem(inviteCode: try await LivePair.waitFor("ann-invite"))
        let room = invite.attestation.room
        let annID = invite.attestation.inviterKeys.participantID
        try await LivePair.until("to be let in to the room", ben, through: cloud) {
            ben.roster(of: room).members.contains(me)
        }

        let direct = try await ben.redeem(inviteCode: try await LivePair.waitFor("ann-solo-invite"))
        let solo = direct.attestation.room
        try await LivePair.until("to be let in to the Solo", ben, through: cloud) {
            ben.roster(of: solo).members.isSuperset(of: [me, annID])
        }
        #expect(
            ben.phrase(for: direct.attestation) == (try await LivePair.waitFor("ann-phrase")),
            "the two ends of the Solo read different phrases")
        try LivePair.leave("yes", as: "ben-in-solo")

        try await ben.send("before the key change", to: room)
        try await rounds(2, ben, through: cloud)
        let held = try #require(keyLastWrittenUnder(by: ben, in: room))
        try LivePair.leave("yes", as: "ben-is-quiet")

        let newest = try await LivePair.waitFor("ann-new-key")
        #expect(ben.epoch(of: room) == held, "precondition: Ben had already heard of the new key")
        let took = try await ContinuousClock().measure {
            try await ben.send("after the key change", to: room, after: cloud)
        }
        print("LIVE PAIR ben: collecting first and then writing took \(took)")
        let sealed = try #require(keyLastWrittenUnder(by: ben, in: room))
        #expect(String(sealed.rawValue) == newest, "the message was sealed under the key Ben held before the fetch")
        try LivePair.leave(String(sealed.rawValue), as: "ben-wrote-under")
        try await rounds(2, ben, through: cloud)

        _ = try await LivePair.waitFor("ann-removed-ben")
        let last = ben.head?.hash
        await #expect(throws: MembershipError.removedFromThisRoom) {
            try await ben.send("am I still here", to: room, after: cloud)
        }
        #expect(ben.head?.hash == last, "a removed member's message was written")
        try LivePair.leave("yes", as: "ben-refused")
        try? await cloud.eraseEverySpace()
    }
}
