import AVFoundation
import CarpenterKit
import CarpenterMedia
import Foundation
import Testing

@Suite("Preparing a clip to send", .serialized)
struct VideoPreparerTests {
    @Test("A clip is re-encoded at the sending size, keeps its length and its shape")
    func reencoded() async throws {
        let original = try await TestVideo.make(seconds: 3)
        defer { try? FileManager.default.removeItem(at: original) }

        let prepared = try await VideoPreparer.prepare(original)

        #expect(prepared.kind == .video)
        #expect(prepared.width == 960 && prepared.height == 540, "\(prepared.width)×\(prepared.height)")
        let duration = try #require(prepared.duration)
        #expect(abs(duration - 3) < 0.2, "ran \(duration)s")
        let file = try #require(prepared.file, "a clip is handed over as a file")
        defer { try? FileManager.default.removeItem(at: file) }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)
        #expect(size <= VideoPreparer.maximumBytes)
        #expect(prepared.bytes.isEmpty, "a clip was read into memory")
    }

    @Test("Location and camera are stripped")
    func metadataIsStripped() async throws {
        let original = try await TestVideo.make(seconds: 2)
        defer { try? FileManager.default.removeItem(at: original) }
        let before = try await VideoPreparer.identifyingMetadata(of: original)
        try #require(!before.isEmpty, "the fixture carries no identifying tags, so this test proves nothing")

        let prepared = try await VideoPreparer.prepare(original)

        let output = try #require(prepared.file)
        defer { try? FileManager.default.removeItem(at: output) }
        let after = try await VideoPreparer.identifyingMetadata(of: output)
        #expect(after.isEmpty, "identifying metadata survived: \(after)")
    }

    @Test("The first frame becomes a preview that fits the entry")
    func previewFits() async throws {
        let original = try await TestVideo.make(seconds: 1)
        defer { try? FileManager.default.removeItem(at: original) }
        let prepared = try await VideoPreparer.prepare(original)
        let preview = try #require(prepared.preview)
        #expect(preview.count <= MediaBody.previewByteCap)
        let size = try #require(ImagePreparer.size(of: preview))
        #expect(max(size.width, size.height) <= ImagePreparer.previewLongestEdge)
        #expect(ImagePreparer.identifyingMetadata(of: preview).isEmpty)
    }

    @Test("A clip longer than a minute is prepared, because the limit is its size, not its length")
    func lengthIsNotALimit() async throws {
        let long = try await TestVideo.make(seconds: 75, size: CGSize(width: 64, height: 64), fps: 1)
        defer { try? FileManager.default.removeItem(at: long) }
        let prepared = try await VideoPreparer.prepare(long)
        defer { prepared.file.map { try? FileManager.default.removeItem(at: $0) } }
        #expect(abs((prepared.duration ?? 0) - 75) < 1)
    }

    @Test("Something that is not a clip is refused")
    func garbageIsRefused() async throws {
        let junk = URL.temporaryDirectory.appending(path: "junk-\(UUID().uuidString).mov")
        try Data("not a clip".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        await #expect(throws: VideoPreparer.Failure.unreadable) {
            try await VideoPreparer.prepare(junk)
        }
    }
}
