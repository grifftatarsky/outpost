import CryptoKit
import Foundation

public struct SealedPayload: Hashable, Sendable, Codable {
    public let epoch: EpochNumber
    public let ciphertext: Data

    public let alsoFor: Data?

    public init(epoch: EpochNumber, ciphertext: Data, alsoFor: Data? = nil) {
        self.epoch = epoch
        self.ciphertext = ciphertext
        self.alsoFor = alsoFor
    }

    var canonicalBytes: Data {
        var fields = [epoch.canonicalBytes, ciphertext]
        if let alsoFor { fields.append(alsoFor) }
        return CanonicalBytes.payload(domain: Domain.sealedPayload, fields: fields)
    }

    static func context(room: ConversationID, epoch: EpochNumber, by writer: FeedKey) -> Data {
        CanonicalBytes.payload(
            domain: Domain.sealedPayload,
            fields: [room.canonicalBytes, epoch.canonicalBytes, writer.canonicalBytes])
    }
}

extension Payload {
    func plaintext() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    public func sealed(
        at epoch: EpochNumber, using chain: EpochChain, by writer: FeedKey,
        alsoFor extra: PairwiseSecret? = nil
    ) throws -> SealedPayload {
        let plaintext = try plaintext()
        let box = try ChaChaPoly.seal(
            plaintext,
            using: try chain.sealingKey(for: epoch),
            authenticating: SealedPayload.context(room: chain.room, epoch: epoch, by: writer)
        )
        let alsoFor = try extra.map {
            try ChaChaPoly.seal(
                plaintext, using: $0.symmetricKey,
                authenticating: SealedPayload.context(room: chain.room, epoch: epoch, by: writer)
            ).combined
        }
        return SealedPayload(epoch: epoch, ciphertext: box.combined, alsoFor: alsoFor)
    }
}

extension SealedPayload {
    public func opened(using chain: EpochChain, by writer: FeedKey) throws -> Payload {
        let key = try chain.sealingKey(for: epoch)
        guard let box = try? ChaChaPoly.SealedBox(combined: ciphertext),
            let plaintext = try? ChaChaPoly.open(
                box, using: key,
                authenticating: SealedPayload.context(room: chain.room, epoch: epoch, by: writer))
        else {
            throw CryptoError.openFailed
        }
        return try JSONDecoder().decode(Payload.self, from: plaintext)
    }

    public func opened(
        pairwise secret: PairwiseSecret, room: ConversationID, by writer: FeedKey
    ) throws -> Payload {
        guard let alsoFor,
            let box = try? ChaChaPoly.SealedBox(combined: alsoFor),
            let plaintext = try? ChaChaPoly.open(
                box, using: secret.symmetricKey,
                authenticating: SealedPayload.context(room: room, epoch: epoch, by: writer))
        else {
            throw CryptoError.openFailed
        }
        return try JSONDecoder().decode(Payload.self, from: plaintext)
    }
}
