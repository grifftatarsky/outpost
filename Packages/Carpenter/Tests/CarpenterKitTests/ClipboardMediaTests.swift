#if os(macOS)
    import AppKit
    import CarpenterKit
    import Testing

    @testable import CarpenterUI

    @Suite("A photo or a copied file on the clipboard becomes an attachment when pasted", .serialized)
    struct ClipboardMediaTests {
        private func board() -> NSPasteboard {
            let board = NSPasteboard(name: .init("outpost-clipboard-tests-\(UUID().uuidString)"))
            board.clearContents()
            return board
        }

        private func file(_ name: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "clipboard-\(UUID().uuidString)-\(name)")
            try Data([7, 7, 7]).write(to: url)
            return url
        }

        @Test func aCopiedImageIsReadAsItsBytes() {
            let board = board()
            defer { board.releaseGlobally() }
            board.setData(Data([1, 2, 3]), forType: .png)
            guard case .image(let data)? = ClipboardMedia.media(on: board).first else {
                Issue.record("a PNG on the clipboard was not read as an image")
                return
            }
            #expect(data == Data([1, 2, 3]))
        }

        @Test func aFileCopiedInFinderIsReadAsTheFile() throws {
            let photo = try file("airship.png")
            defer { try? FileManager.default.removeItem(at: photo) }
            let board = board()
            defer { board.releaseGlobally() }
            board.writeObjects([photo as NSURL])
            board.setString(photo.lastPathComponent, forType: .string)
            #expect(ClipboardMedia.media(on: board).count == 1)
            #expect(ClipboardMedia.files(named: [photo.lastPathComponent], on: board) == [photo])
        }

        @Test func wordsOnTheClipboardAreNotMedia() {
            let board = board()
            defer { board.releaseGlobally() }
            board.setString("pasted words", forType: .string)
            #expect(ClipboardMedia.media(on: board).isEmpty)
        }

        @Test func copiedWritingThatCarriesAnImageStaysWriting() {
            let board = board()
            defer { board.releaseGlobally() }
            board.declareTypes([.string, .png], owner: nil)
            board.setString("a paragraph about airships", forType: .string)
            board.setData(Data([1, 2, 3]), forType: .png)
            #expect(ClipboardMedia.media(on: board).isEmpty)
        }

        @Test func aCopiedImageThatAlsoCarriesItsLinkIsTheImage() {
            let board = board()
            defer { board.releaseGlobally() }
            board.declareTypes([.string, .png], owner: nil)
            board.setString("https://example.com/zeppelin.png", forType: .string)
            board.setData(Data([1, 2, 3]), forType: .png)
            #expect(ClipboardMedia.media(on: board).count == 1)
        }

        @Test func aNameThatIsNotOnTheClipboardIsLeftAsText() throws {
            let photo = try file("airship.png")
            defer { try? FileManager.default.removeItem(at: photo) }
            let board = board()
            defer { board.releaseGlobally() }
            board.writeObjects([photo as NSURL])
            #expect(ClipboardMedia.files(named: ["somethingelse.png"], on: board) == nil)
        }

        @Test func aCopiedDocumentIsNotMedia() throws {
            let notes = try file("notes.txt")
            defer { try? FileManager.default.removeItem(at: notes) }
            let board = board()
            defer { board.releaseGlobally() }
            board.writeObjects([notes as NSURL])
            #expect(ClipboardMedia.media(on: board).isEmpty)
        }
    }
#endif
