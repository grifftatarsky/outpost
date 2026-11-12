@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite(
    "A photo whose copies land for some of the room", .serialized, .timeLimit(.minutes(10)),
    .tags(.sync, .manyDevices))
struct APhotoWhoseCopiesLandForSomeTests {
    @Test(
        "A photo whose copies land for two of four and fail for two reaches all four, and no copy stays",
        arguments: [["Bob", "Carol"], ["Dave", "Erin"], ["Bob", "Erin"]])
    func aPhotoThatHalfUploadedReachesEveryoneAndLeavesNoCopy(landedFor: [String]) async throws {
        let g = try await Gathering.of("Alice", "Bob", "Carol", "Dave", "Erin")
        let friends = ["Bob", "Carol", "Dave", "Erin"]
        let room = try await g.room("Lanterns", host: "Alice", guests: friends)
        let photo = SendingPhotoTests.photo(caption: "the lake")
        let copiesBefore = await g.cloud.storedCopyCount

        await g.door("Alice").landOnlyTheCopies(for: Set(landedFor.map(g.id)))
        var toldItFailed = false
        do { try await g["Alice"].send(photo, to: room, through: g.door("Alice")) } catch { toldItFailed = true }
        #expect(toldItFailed, "Alice was not told her photo failed to send")
        #expect(await g.door("Alice").faultsPending == 0, "the partial upload never fired")
        try #require(
            await g.cloud.storedCopyCount == copiesBefore + landedFor.count,
            "precondition: copies landed for \(landedFor.joined(separator: " and ")) and nobody else")
        #expect(
            !g["Alice"].messages(in: room).contains { $0.media != nil },
            "Alice's phone shows a photo that never finished sending")

        try await g["Alice"].send(photo, to: room, through: g.door("Alice"))
        try await g.settle()

        let sent = try #require(g["Alice"].messages(in: room).last { $0.media != nil }, "Alice shows no photo")
        let media = try #require(sent.media)
        for friend in friends {
            let shown = g[friend].messages(in: room).filter { $0.media != nil }
            #expect(shown.count == 1, "\(friend) shows \(shown.count) photos, not one")
            #expect(await g[friend].holdsAttachment(media.id), "\(friend) never collected the photo")
            let opened = try await g[friend].attachmentData(
                for: media, sentBy: g.id("Alice"), through: g.door(friend))
            #expect(opened == photo.bytes, "\(friend) holds bytes that are not the photo Alice sent")
        }
        g.sameRoom(room, on: ["Alice"] + friends)

        g.advance(by: MailboxRules.sweepAge + 60)
        await g.relaunch("Alice")
        try await g.settle()
        let left = await g.cloud.storedCopyCount
        #expect(left == 0, "\(left) copies of Alice's photo stay in iCloud after everybody collected it")
    }
}
