import CryptoKit
import Foundation

public enum DraftSeal {
    public static let key = KeychainKey("draft.sealing")

    public static func newKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func seal(_ words: String, at place: DraftPlace, with key: Data) throws -> Data {
        try ChaChaPoly.seal(
            Data(words.utf8), using: SymmetricKey(data: key), authenticating: boundTo(place)
        ).combined
    }

    public static func open(_ sealed: Data, at place: DraftPlace, with key: Data) -> String? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
            let words = try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: boundTo(place))
        else { return nil }
        return String(data: words, encoding: .utf8)
    }

    private static func boundTo(_ place: DraftPlace) -> Data {
        let fields: [Data] =
            switch place {
            case .room(let room): [room.canonicalBytes]
            case .newPost: [Data("new post".utf8), Data()]
            case .comment(let post): [Data("comment".utf8), post.entry.rawValue]
            }
        return CanonicalBytes.payload(domain: Domain.draft, fields: fields)
    }
}
