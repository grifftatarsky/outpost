@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@MainActor
@Suite("An Outpost with four readers", .serialized, .timeLimit(.minutes(10)), .tags(.sync, .manyDevices))
struct AnOutpostWithFourReadersTests {
    private static let readers = ["Bob", "Carol", "Dave", "Erin"]
    private static let photo = SendingPhotoTests.photo(caption: "the harbour")

    @Test(
        "A post, a photo and comments reach four readers, and a reader turned away reads nothing posted afterwards",
        arguments: 0..<4)
    func everyReaderReadsAndTheOneTurnedAwayReadsNothingNew(rotation: Int) async throws {
        let g = try await Gathering.of(["Alice"] + Self.readers)
        _ = try await g.room("Lanterns", host: "Alice", guests: Self.readers)
        for reader in Self.readers { try await g["Alice"].allowOutpost(g.id(reader), everything: true) }
        try await g.settle()
        let order = ["Alice"] + Array(Self.readers[rotation...] + Self.readers[..<rotation])

        let packetsBefore = Set(await g.cloud.writtenPackets)
        try await g["Alice"].send("first light", to: nil)
        try await g["Alice"].post(Self.photo, through: g.door("Alice"))
        await g.takeTurns("Alice")
        let sent = await g.cloud.everySentPacket
        let forCarol = await g.cloud.writtenPackets.filter {
            !packetsBefore.contains($0) && sent[$0]?.to == g.id("Carol")
        }
        let skipped = try #require(forCarol.first, "precondition: Alice wrote Carol a packet")
        await g.door("Carol").skip(skipped)
        await g.takeTurns("Carol")
        #expect(await g.door("Carol").faultsPending == 0, "Carol's first read never left out Alice's packet")
        try #require(
            !g.reads("first light", onTheOutpostOf: "Alice", on: "Carol")
                || !g.reads("the harbour", onTheOutpostOf: "Alice", on: "Carol"),
            "precondition: Carol's first read missed something Alice posted")
        try await g.settle(inOrder: order)

        for reader in order.dropFirst() {
            let post = try #require(
                g.post(saying: "first light", onTheOutpostOf: "Alice", on: reader),
                "precondition: \(reader) reads Alice's post")
            try await g[reader].comment(on: post, text: "from \(reader)")
        }
        let photoPost = try #require(
            g.post(saying: "the harbour", onTheOutpostOf: "Alice", on: "Dave"), "precondition: Dave reads the photo")
        try await g["Dave"].comment(on: photoPost, text: "what a sky")
        try await g.settle(inOrder: order)

        g.away("Erin")
        try await g["Alice"].revokeOutpost(g.id("Erin"))
        try await g["Alice"].send("after Erin", to: nil)
        try await g["Alice"].post(SendingPhotoTests.photo(caption: "after Erin, a photo"), through: g.door("Alice"))
        try await g.settle(inOrder: order)
        g.back("Erin")
        try await g.settle(inOrder: order)

        for reader in ["Alice"] + Self.readers {
            let post = try #require(
                g.post(saying: "first light", onTheOutpostOf: "Alice", on: reader), "\(reader) lost Alice's post")
            let comments = Set(g[reader].comments(on: post).map(\.body))
            for commenter in Self.readers {
                #expect(comments.contains("from \(commenter)"), "\(reader) never read \(commenter)'s comment")
            }
            let photoPost = try #require(
                g.post(saying: "the harbour", onTheOutpostOf: "Alice", on: reader), "\(reader) lost the photo post")
            #expect(
                g[reader].comments(on: photoPost).map(\.body) == ["what a sky"],
                "\(reader) does not show Dave's comment on the photo")
            guard reader != "Alice" else { continue }
            let media = try #require(photoPost.media.first, "\(reader)'s copy of the photo post has no picture")
            let bytes = try await g[reader].attachmentData(for: media, sentBy: g.id("Alice"), through: g.door(reader))
            #expect(bytes == Self.photo.bytes, "\(reader) could not open Alice's photo")
        }
        for reader in ["Bob", "Carol", "Dave"] {
            for body in ["after Erin", "after Erin, a photo"] {
                #expect(g.reads(body, onTheOutpostOf: "Alice", on: reader), "\(reader) never read \"\(body)\"")
            }
        }
        let erinHeld = try #require(g["Erin"].chains[g.outpost(of: "Alice")], "precondition: Erin held Alice's keys")
        for body in ["after Erin", "after Erin, a photo"] {
            #expect(!g.reads(body, onTheOutpostOf: "Alice", on: "Erin"), "Erin, turned away, read \"\(body)\"")
            let entry = try #require(g.entry(ofPostSaying: body, by: "Alice"))
            #expect(entry.opened(using: erinHeld) == nil, "Erin's keys open \"\(body)\"")
        }
    }
}
