import CarpenterKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CarpenterUI

@Suite("A photo or a clip dragged in arrives as what the picker would have handed over")
struct DroppedMediaTests {
    private func load(_ provider: NSItemProvider) async -> DroppedMedia? {
        await withCheckedContinuation { done in
            _ = provider.loadTransferable(type: DroppedMedia.self) { result in
                done.resume(returning: try? result.get())
            }
        }
    }

    @Test func aDraggedImageArrivesAsItsBytes() async {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let provider = NSItemProvider(item: bytes as NSData, typeIdentifier: UTType.png.identifier)
        let dropped = await load(provider)
        guard case .image(let data)? = dropped?.picked else {
            Issue.record("a PNG did not arrive as an image")
            return
        }
        #expect(data == bytes)
    }

    @Test func aDraggedClipArrivesAsACopyTheAppOwns() async throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).mov")
        try Data("not really a movie".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.quickTimeMovie.identifier, visibility: .all
        ) { finish in
            finish(source, false, nil)
            return nil
        }
        let dropped = await load(provider)
        guard case .video(let url)? = dropped?.picked else {
            Issue.record("a QuickTime file did not arrive as a clip")
            return
        }
        #expect(url != source)
        #expect(FileManager.default.fileExists(atPath: url.path()))
        #expect(url.pathExtension == "mov")
        try? FileManager.default.removeItem(at: url)
    }

    @Test func draggedTextIsNotMedia() async {
        let provider = NSItemProvider(object: "just words" as NSString)
        #expect(await load(provider) == nil)
    }
}
