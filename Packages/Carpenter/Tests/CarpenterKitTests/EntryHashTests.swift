import CryptoKit
import Foundation
import Testing

@testable import CarpenterKit

@Suite("An entry's hash")
struct EntryHashTests {
    private let start = Date(timeIntervalSince1970: 1_786_635_000)

    private func twoEntries() throws -> (Entry, Entry) {
        var author = Author()
        let first = try author.post("first", at: start)
        let second = try author.append(
            Payload.post("second"), at: start.addingTimeInterval(1), room: RoomID())
        return (first, second)
    }

    @Test("The hash is the digest of what was signed, however the entry was made or read back")
    func hashIsTheDigestOfTheSignedBytes() throws {
        let (_, entry) = try twoEntries()
        let digest = SHA256.hash(
            data: CanonicalBytes.payload(
                domain: Domain.entryHash, fields: [entry.signingPayload, entry.signature]))

        #expect(entry.hash == EntryHash(rawValue: Data(digest)))

        let reread = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(entry))
        #expect(reread.hash == entry.hash)
        #expect(reread == entry)
    }

    @Test("An entry is written down with exactly its fields, a room entry with its link, and never its hash")
    func storedFormIsExact() throws {
        let (first, second) = try twoEntries()
        let keys = { (entry: Entry) throws -> Set<String> in
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry))
            return Set((object as? [String: Any] ?? [:]).keys)
        }

        #expect(try keys(first) == ["author", "device", "seq", "clock", "wallTime", "payload", "signature"])
        #expect(
            try keys(second)
                == [
                    "author", "device", "seq", "previous", "clock", "wallTime", "room", "payload", "roomLink",
                    "signature",
                ])
    }

    @Test("Two entries are equal exactly when their hashes are")
    func equalityFollowsTheHash() throws {
        let (first, second) = try twoEntries()
        #expect(first != second)
        #expect(Set([first, second, first]).count == 2)
    }
}
