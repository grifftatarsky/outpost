import CryptoKit
import Foundation

public enum DraftSeal {
    public static let key = KeychainKey("draft.sealing")

    public static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func seal(_ words: String, in room: RoomID, with key: Data) throws -> Data {
        try ChaChaPoly.seal(
            Data(words.utf8), using: SymmetricKey(data: key), authenticating: boundTo(room)
        ).combined
    }

    public static func open(_ sealed: Data, in room: RoomID, with key: Data) -> String? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
            let words = try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: boundTo(room))
        else { return nil }
        return String(data: words, encoding: .utf8)
    }

    private static func boundTo(_ room: RoomID) -> Data {
        CanonicalBytes.payload(domain: Domain.draft, fields: [room.canonicalBytes])
    }
}
