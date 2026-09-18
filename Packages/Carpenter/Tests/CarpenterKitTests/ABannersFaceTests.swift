import Foundation
import Testing

@testable import CarpenterKit

@Suite("Which face a banner draws")
struct ABannersFaceTests {
    private let person = ParticipantID(rawValue: Data(repeating: 7, count: 32))

    private func store() throws -> (PersonAvatarStore, URL) {
        let directory = URL.temporaryDirectory.appending(path: "faces-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (PersonAvatarStore(directory: directory), directory)
    }

    private func jpeg(_ tag: UInt8) -> Data { Data([0xFF, 0xD8, tag, 0xFF, 0xD9]) }

    @Test("A banner about a post prefers the picture on the wall it came from")
    func aPostPrefersTheWallsPicture() throws {
        let (photos, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        try photos.saveShared(jpeg(1), for: person, attachment: AttachmentID())
        try photos.savePublished(jpeg(2), for: person, .outpost, attachment: AttachmentID())

        #expect(
            photos.faceForABanner(from: person, aboutAPost: true) == jpeg(2),
            """
            A banner about a post drew the face that person's rooms see. The extension knew about \
            two namespaces and a wall's picture lives in a third, so somebody who chose a different \
            picture for their Outpost got their rooms face on a banner about their wall.
            """)
    }

    @Test("A banner about a message never uses the wall's picture over the rooms one")
    func aMessageKeepsTheRoomsPicture() throws {
        let (photos, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        try photos.saveShared(jpeg(1), for: person, attachment: AttachmentID())
        try photos.savePublished(jpeg(2), for: person, .outpost, attachment: AttachmentID())

        #expect(photos.faceForABanner(from: person, aboutAPost: false) == jpeg(1))
    }

    @Test("A picture this member chose themselves beats both")
    func aPictureThisMemberChoseBeatsBoth() throws {
        let (photos, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        try photos.save(jpeg(9), for: person)
        try photos.saveShared(jpeg(1), for: person, attachment: AttachmentID())

        #expect(photos.faceForABanner(from: person, aboutAPost: false) == jpeg(9))
    }

    @Test("A wall picture stands in when there is nothing else, even for a message")
    func aWallPictureStandsIn() throws {
        let (photos, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        try photos.savePublished(jpeg(2), for: person, .outpost, attachment: AttachmentID())

        #expect(
            photos.faceForABanner(from: person, aboutAPost: false) == jpeg(2),
            "a face the app holds was left unused in favour of a monogram")
    }

    @Test("Nothing held is nothing drawn, rather than somebody else's face")
    func nothingHeldIsNothingDrawn() throws {
        let (photos, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(photos.faceForABanner(from: person, aboutAPost: true) == nil)
        #expect(photos.faceForABanner(from: person, aboutAPost: false) == nil)
    }
}
