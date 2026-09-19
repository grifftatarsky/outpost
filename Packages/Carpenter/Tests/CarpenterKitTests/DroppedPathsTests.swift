import Foundation
import Testing

@testable import CarpenterUI

@Suite("A photo dropped on a text field becomes an attachment, never its path")
struct DroppedPathsTests {
    private func file(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "dropped-paths-\(UUID().uuidString)-\(name)")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    @Test func aPathTheTextViewInsertedIsRecognisedAsTheFile() throws {
        let photo = try file("airship.png")
        defer { try? FileManager.default.removeItem(at: photo) }
        let files = DroppedPaths.files(insertedBetween: "look at ", and: "look at \(photo.path())")
        #expect(files?.map(\.lastPathComponent) == [photo.lastPathComponent])
    }

    @Test func aFileURLIsRecognisedToo() throws {
        let clip = try file("hangar.mov")
        defer { try? FileManager.default.removeItem(at: clip) }
        let files = DroppedPaths.files(insertedBetween: "", and: clip.absoluteString)
        #expect(files?.count == 1)
    }

    @Test func severalFilesOnSeparateLinesAreAllRecognised() throws {
        let one = try file("one.jpg")
        let two = try file("two.heic")
        defer {
            try? FileManager.default.removeItem(at: one)
            try? FileManager.default.removeItem(at: two)
        }
        let files = DroppedPaths.files(insertedBetween: "", and: "\(one.path())\n\(two.path())")
        #expect(files?.count == 2)
    }

    @Test func typingIsNeverTakenForADrop() {
        #expect(DroppedPaths.files(insertedBetween: "hello", and: "hello there") == nil)
        #expect(DroppedPaths.files(insertedBetween: "", and: "/Users/nobody/not-a-real-file.png") == nil)
        #expect(DroppedPaths.files(insertedBetween: "hello there", and: "hello") == nil)
    }

    @Test func aPathToSomethingThatIsNotMediaStaysText() throws {
        let notes = try file("notes.txt")
        defer { try? FileManager.default.removeItem(at: notes) }
        #expect(DroppedPaths.files(insertedBetween: "", and: notes.path()) == nil)
    }

    @Test func aDroppedPhotoIsReadAsItsBytes() throws {
        let photo = try file("airship.png")
        defer { try? FileManager.default.removeItem(at: photo) }
        guard case .image(let data)? = DroppedPaths.media(photo) else {
            Issue.record("a PNG path did not become an image")
            return
        }
        #expect(data == Data([1, 2, 3]))
    }
}
