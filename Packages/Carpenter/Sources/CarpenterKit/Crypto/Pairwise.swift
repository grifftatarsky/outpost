import CryptoKit
import Foundation

public struct PairwiseSecret: Hashable, Sendable {
    public let material: Data

    init(material: Data) {
        self.material = material
    }

    public static func derive(mine: Identity, theirs: IdentityPublicKeys) throws -> PairwiseSecret {
        let shared = try mine.sharedSecret(with: theirs)
        let ids = [mine.id.rawValue, theirs.participantID.rawValue]
            .sorted { $0.lexicographicallyPrecedes($1) }

        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(Domain.pairwiseSecret.utf8),
            sharedInfo: CanonicalBytes.payload(domain: Domain.pairwiseSecret, fields: ids),
            outputByteCount: 32
        )
        return PairwiseSecret(material: key.withUnsafeBytes { Data($0) })
    }

    var symmetricKey: SymmetricKey { SymmetricKey(data: material) }

    public func recipientTag(window: UInt64, for recipient: ParticipantID) -> RecipientTag {
        let digest = HMAC<SHA256>.authenticationCode(
            for: CanonicalBytes.payload(
                domain: Domain.recipientTag,
                fields: [CanonicalBytes.sequence(window), recipient.rawValue]),
            using: symmetricKey
        )
        return RecipientTag(rawValue: Data(digest))
    }

    public func bellName(for recipient: ParticipantID) -> String {
        let digest = HMAC<SHA256>.authenticationCode(
            for: CanonicalBytes.payload(
                domain: Domain.messageBell, fields: [recipient.rawValue]),
            using: symmetricKey
        )
        return "bell-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public func shareOfferName(for recipient: ParticipantID) -> String {
        let digest = HMAC<SHA256>.authenticationCode(
            for: CanonicalBytes.payload(
                domain: Domain.shareOffer, fields: [recipient.rawValue]),
            using: symmetricKey
        )
        return "offer-" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public static let shareOfferContext = Data(Domain.shareOffer.utf8)

    public func shareOfferDigest(of url: URL) -> String {
        let digest = HMAC<SHA256>.authenticationCode(
            for: CanonicalBytes.payload(
                domain: Domain.shareOfferDigest, fields: [Data(url.absoluteString.utf8)]),
            using: symmetricKey
        )
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public func wrap(_ plaintext: Data, context: Data) throws -> Data {
        let sealed = try ChaChaPoly.seal(plaintext, using: symmetricKey, authenticating: context)
        return sealed.combined
    }

    public func unwrap(_ ciphertext: Data, context: Data) throws -> Data {
        guard let box = try? ChaChaPoly.SealedBox(combined: ciphertext),
            let opened = try? ChaChaPoly.open(box, using: symmetricKey, authenticating: context)
        else {
            throw CryptoError.openFailed
        }
        return opened
    }
}
