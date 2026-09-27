@testable import CarpenterApp
@testable import CarpenterKit
import CarpenterKitTesting
import CryptoKit
import Foundation
import Testing

@Suite("A clip is sealed and sent in pieces, never whole")
struct SealingAClipInPiecesTests {
    private func file(bytes: Int, seed: UInt8 = 7) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "clip-\(UUID().uuidString).mp4")
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            for index in 0..<bytes { raw[index] = UInt8(truncatingIfNeeded: index &* 31 &+ Int(seed)) }
        }
        try data.write(to: url)
        return url
    }

    private func sealed(_ url: URL) async throws -> (AttachmentReference, [AttachmentID: Data]) {
        let store = Pieces()
        let reference = try await SealedAttachment.sealParts(of: url) { part, ciphertext in
            await store.keep(part.id, ciphertext)
        }
        return (reference, await store.all)
    }

    private actor Pieces {
        var all: [AttachmentID: Data] = [:]
        func keep(_ id: AttachmentID, _ data: Data) { all[id] = data }
    }

    @Test("A clip larger than one piece comes back byte for byte")
    func aClipComesBackWhole() async throws {
        let source = try file(bytes: SealedAttachment.partPlaintextBytes * 2 + 12_345)
        let (reference, pieces) = try await sealed(source)
        #expect(reference.parts?.count == 3)
        #expect(pieces.count == 3)

        let out = URL.temporaryDirectory.appending(path: "opened-\(UUID().uuidString).mp4")
        let opened = try await SealedAttachment.openParts(reference, into: out) { pieces[$0.id] }
        #expect(opened)
        #expect(try Data(contentsOf: out) == Data(contentsOf: source))
    }

    @Test("Pieces swapped, missing or altered do not open")
    func piecesAreBound() async throws {
        let source = try file(bytes: SealedAttachment.partPlaintextBytes + 5_000)
        let (reference, pieces) = try await sealed(source)
        let parts = try #require(reference.parts)
        let out = URL.temporaryDirectory.appending(path: "opened-\(UUID().uuidString).mp4")

        let swapped = [parts[0].id: pieces[parts[1].id]!, parts[1].id: pieces[parts[0].id]!]
        await #expect(throws: AttachmentError.digestMismatch) {
            try await SealedAttachment.openParts(reference, into: out) { swapped[$0.id] }
        }

        #expect(try await SealedAttachment.openParts(reference, into: out) { $0.id == parts[1].id ? nil : pieces[$0.id] } == false)

        var tampered = pieces
        var bytes = tampered[parts[1].id]!
        bytes[bytes.startIndex + 40] ^= 0xFF
        tampered[parts[1].id] = bytes
        let altered = tampered
        await #expect(throws: AttachmentError.digestMismatch) {
            try await SealedAttachment.openParts(reference, into: out) { altered[$0.id] }
        }

        let reordered = AttachmentReference(
            id: reference.id, key: reference.key, digest: reference.digest, byteCount: reference.byteCount,
            parts: [parts[1], parts[0]])
        await #expect(throws: AttachmentError.digestMismatch) {
            try await SealedAttachment.openParts(reordered, into: out) { pieces[$0.id] }
        }
    }

    @Test("A clip over 287 MB is refused before anything is sealed")
    func overTheCapIsRefused() async throws {
        let url = URL.temporaryDirectory.appending(path: "huge-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SealedAttachment.maximumVideoBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = Pieces()
        await #expect(throws: AttachmentError.tooLarge) {
            try await SealedAttachment.sealParts(of: url) { part, ciphertext in await store.keep(part.id, ciphertext) }
        }
        #expect(await store.all.isEmpty)
    }
}

@MainActor
@Suite("Sending a clip in pieces", .serialized)
struct SendingAClipInPiecesTests {
    private func joined() async throws -> (alice: AppSession, bob: AppSession, mailbox: InMemoryMailbox, room: RoomID) {
        let mailbox = InMemoryMailbox()
        let alice = TestSession.make()
        let bob = TestSession.make()
        for member in [alice, bob] { await member.load() }
        try await alice.createIdentity(displayName: "Alice")
        try await bob.createIdentity(displayName: "Bob")
        let room = try await alice.createRoom(named: "Screening room")
        let invite = try await alice.invite(joinerCode: bob.identityCode(), joining: room, mailbox: nil)
        try await bob.redeem(inviteCode: try invite.encoded())
        try await alice.sync(through: mailbox)
        try await bob.accept(invite.attestation, from: try #require(alice.enrolment?.identity.publicKeys))
        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        return (alice, bob, mailbox, room)
    }

    @Test("A clip bigger than a piece reaches the other member as the same bytes, and the sender's file is gone")
    func aClipCrossesInPieces() async throws {
        let (alice, bob, mailbox, room) = try await joined()
        let source = URL.temporaryDirectory.appending(path: "prepared-\(UUID().uuidString).mp4")
        let original = Data((0..<(SealedAttachment.partPlaintextBytes + 70_000)).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        try original.write(to: source)
        let clip = PreparedMedia(
            kind: .video, width: 960, height: 540, file: source, preview: Data(repeating: 4, count: 500),
            duration: 95)

        try await alice.send(clip, to: room, through: mailbox)
        #expect(!FileManager.default.fileExists(atPath: source.path), "the prepared file was left behind")
        #expect(await mailbox.storedAttachmentCount == 2)

        for _ in 0..<4 {
            try await alice.sync(through: mailbox)
            try await bob.sync(through: mailbox)
        }
        let media = try #require(bob.messages(in: room).last?.media)
        #expect(media.reference.parts?.count == 2)
        #expect(media.duration == 95)

        let out = URL.temporaryDirectory.appending(path: "played-\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let alicesID = try #require(alice.enrolment?.identity.id)
        #expect(try await bob.writeClip(for: media, sentBy: alicesID, through: mailbox, to: out))
        #expect(try Data(contentsOf: out) == original)
    }
}
