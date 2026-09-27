import CarpenterCloudKit
import CarpenterKit
import CloudKit
import Foundation
import Testing

@Suite(
    "A deathmark on a real CloudKit account",
    .enabled(if: LiveCloudKit.isAsked),
    .serialized)
struct LiveDeathmarkTests {
    @Test("A deathmark is stored with iCloud's time, gathers check-offs, and is gone when cleared")
    func aDeathmarkRoundTrips() async throws {
        _ = try await LiveCloudKit.mailbox()
        let board = CloudKitDeathmarkBoard(container: .default())
        try await board.clear()
        #expect(try await board.read() == nil, "precondition: no deathmark before the test")

        let identity = Identity.generate()
        let (phone, tablet) = (DeviceKeys.generate(), DeviceKeys.generate())
        let mark = try Deathmark.issue(for: identity.id, listing: [phone.id, tablet.id], by: phone, at: Date())
        let before = Date().addingTimeInterval(-120)
        try await board.post(try mark.sealed(for: identity))
        try await board.checkOff(phone.id, sealed: try Deathmark.sealedCheckOff(phone.id, for: identity))

        let posted = try #require(try await board.read(), "a posted deathmark did not come back")
        #expect(Deathmark.open(posted.sealed, for: identity) == mark)
        let stored = try #require(posted.storedAt, "iCloud gave the deathmark no stored time")
        #expect(stored > before && stored < Date().addingTimeInterval(120))
        #expect(posted.checkedOff == [phone.id])

        try await board.checkOff(tablet.id, sealed: try Deathmark.sealedCheckOff(tablet.id, for: identity))
        #expect(try await board.read()?.checkedOff == [phone.id, tablet.id])

        try await board.clear()
        #expect(try await board.read() == nil, "clearing left the deathmark on the server")
    }

    @Test("Posting again starts a new deathmark with a new stored time and no check-offs")
    func aSecondDeathmarkIsNew() async throws {
        _ = try await LiveCloudKit.mailbox()
        let board = CloudKitDeathmarkBoard(container: .default())
        let identity = Identity.generate()
        let phone = DeviceKeys.generate()
        let first = try Deathmark.issue(for: identity.id, listing: [phone.id], by: phone, at: Date())
        try await board.post(try first.sealed(for: identity))
        try await board.checkOff(phone.id, sealed: try Deathmark.sealedCheckOff(phone.id, for: identity))
        let firstStored = try #require(try await board.read()?.storedAt)
        try await Task.sleep(for: .seconds(2))

        let second = try Deathmark.issue(for: identity.id, listing: [phone.id], by: phone, at: Date())
        try await board.post(try second.sealed(for: identity))
        let again = try #require(try await board.read())
        #expect(Deathmark.open(again.sealed, for: identity) == second)
        #expect(again.checkedOff.isEmpty, "check-offs from the old deathmark carried over")
        #expect(try #require(again.storedAt) > firstStored, "the new deathmark kept the old one's stored time")
        try await board.clear()
    }
}
