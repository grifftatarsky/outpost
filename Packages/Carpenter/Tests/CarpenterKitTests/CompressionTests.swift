@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import Foundation
import Testing

@Suite("What goes to iCloud is compressed, and nothing can make a phone expand it without limit")
struct CompressionTests {
    @Test("Whatever goes in comes back out, and what would not get smaller is left as it is")
    func roundTrips() throws {
        let words = Data(String(repeating: "the mooring mast drawings are 1:200, ", count: 400).utf8)
        let packed = Compressed.pack(words)
        #expect(packed.count < words.count / 4)
        #expect(try Compressed.unpack(packed) == words)

        var random = Data(count: 4_096)
        random.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        #expect(Compressed.pack(random) == random, "data that does not compress was wrapped anyway")
        #expect(try Compressed.unpack(random) == random)
        #expect(try Compressed.unpack(Data()) == Data())
    }

    @Test("A body written before compression still opens")
    func olderBodiesOpen() throws {
        let json = Data(#"{"entries":[],"certificates":[]}"#.utf8)
        #expect(try Compressed.unpack(json) == json)
    }

    @Test("A body that swells past what it claims, or past the cap, is refused rather than opened")
    func bombsAreRefused() throws {
        let zeros = Data(count: 2 * 1024 * 1024)
        let squeezed = Compressed.pack(zeros)
        #expect(squeezed.count < 20_000, "precondition: the bomb is small on the wire")

        #expect(throws: Compressed.Failure.tooLarge(2 * 1024 * 1024)) {
            try Compressed.unpack(squeezed, cap: 1024 * 1024)
        }

        var lying = squeezed
        let claim = UInt32(4_096).bigEndian
        withUnsafeBytes(of: claim) { lying.replaceSubrange(3..<7, with: $0) }
        #expect(throws: Compressed.Failure.self) { try Compressed.unpack(lying) }

        var huge = squeezed
        withUnsafeBytes(of: UInt32.max.bigEndian) { huge.replaceSubrange(3..<7, with: $0) }
        #expect(throws: Compressed.Failure.tooLarge(Int(UInt32.max))) { try Compressed.unpack(huge) }
    }

    @Test("A cut-off or scrambled body is refused")
    func damageIsRefused() throws {
        let packed = Compressed.pack(Data(String(repeating: "abc", count: 1_000).utf8))
        #expect(throws: Compressed.Failure.self) { try Compressed.unpack(packed.prefix(packed.count / 2)) }
        #expect(throws: Compressed.Failure.damaged) { try Compressed.unpack(Compressed.mark + Data([0, 0])) }
    }

    @MainActor
    @Test("A real round of short messages goes out much smaller than its words, and arrives whole")
    func aRoundShrinks() async throws {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for (session, name) in [(alice, "Alice"), (bob, "Bob")] {
            await session.load()
            try await session.createIdentity(displayName: name)
        }
        let room = try await alice.createRoom(named: "Lanterns")
        try await join(bob, into: room, of: alice, through: mailbox)
        let before = Set(await mailbox.writtenPackets)
        for index in 0..<60 { try await alice.send("Running late, be there in ten (\(index))", to: room) }
        try await alice.sync(through: mailbox)
        let fresh = await mailbox.writtenPackets.filter { !before.contains($0) }
        let entries = alice.replica.allEntries.filter { $0.room == room }.suffix(60)
        let asJSON = try JSONEncoder().encode(Array(entries)).count
        let written = try await mailbox.storedCiphertextBytes(of: fresh)
        #expect(written < asJSON / 2, "sixty messages went out at \(written) bytes against \(asJSON) as JSON")

        try await bob.sync(through: mailbox)
        #expect(bob.messages(in: room).filter { $0.body.hasPrefix("Running late") }.count == 60)
    }
}
