import CarpenterKit
import CarpenterKitTesting
import CarpenterMedia
import Foundation
import Testing

@testable import CarpenterApp

@MainActor
@Suite("What preparing and sending a clip leaves on the phone", .serialized, .tags(.sync))
struct WhatPreparingAClipLeavesBehindTests {
    private let scratch = ScratchSpace(
        directory: TestScratch.root.appending(path: "scratch-\(UUID().uuidString)", directoryHint: .isDirectory),
        protection: ProtectionDial())

    private func preparedClip() throws -> PreparedMedia {
        let file = try scratch.newFile("prepared", extension: "mp4")
        try Data(repeating: 7, count: 4_096).write(to: file.url)
        return PreparedMedia(
            kind: .video, width: 640, height: 360, file: file, preview: Data(repeating: 1, count: 100), duration: 3)
    }

    private static func clipURL(of picked: PickedMedia?) -> URL? {
        guard case .video(let file) = picked else { return nil }
        return file.url
    }

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    @Test("A file somebody picked is deleted as soon as nothing holds it")
    func aPickedFileGoesWithItsOwner() throws {
        var picked: PickedMedia? = .video(try scratch.newFile("picked", extension: "mov"))
        let url = try #require(Self.clipURL(of: picked))
        try Data([1, 2, 3]).write(to: url)
        #expect(exists(url))
        picked = nil
        #expect(picked == nil)
        #expect(!exists(url), "a picked original stayed behind after the member let it go")
    }

    @Test("A prepared clip is gone after a send that was refused before it uploaded")
    func aRefusedSendLeavesNothing() async throws {
        let mailbox = InMemoryMailbox()
        let member = TestSession.make()
        await member.load()
        try await member.createIdentity(displayName: "Alice")
        let room = try await member.createRoom(named: "Kitchen")
        try await member.leave(room)
        let clip = try preparedClip()
        #expect(exists(clip.file))

        await #expect(throws: (any Error).self) { try await member.send(clip, to: room, through: mailbox) }

        #expect(!exists(clip.file), "the prepared clip of a refused send stayed on the phone")
    }

    @Test("Prepared clips are gone after a post that was refused")
    func aRefusedPostLeavesNothing() async throws {
        let mailbox = InMemoryMailbox()
        let member = TestSession.make()
        await member.load()
        try await member.createIdentity(displayName: "Alice")
        let clips = try (0...MediaBody.galleryLimit).map { _ in try preparedClip() }
        #expect(clips.allSatisfy { exists($0.file) })

        await #expect(throws: (any Error).self) { try await member.post(clips, through: mailbox) }

        #expect(clips.allSatisfy { !exists($0.file) }, "a refused post left its prepared clips on the phone")
    }

    @Test("A clip is prepared inside the scratch space, and nowhere else")
    func preparedInTheScratchSpace() async throws {
        let original = try await TestVideo.make(seconds: 1)
        defer { try? FileManager.default.removeItem(at: original) }

        let prepared = try await VideoPreparer.prepare(original)

        let file = try #require(prepared.file)
        #expect(file.deletingLastPathComponent().standardizedFileURL == ScratchSpace.shared.directory.standardizedFileURL)
    }

    @Test("Emptying the scratch space leaves nothing in it, and emptying it twice is not a failure")
    func emptyingIsComplete() throws {
        let kept = try scratch.newFile("picked", extension: "mov")
        try Data([1]).write(to: kept.url)
        try scratch.empty()
        #expect(!FileManager.default.fileExists(atPath: scratch.directory.path))
        try scratch.empty()
    }
}
