import CryptoKit
import Foundation

public struct AttachmentID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct AttachmentReference: Hashable, Sendable, Codable {
    public let id: AttachmentID

    public let key: Data

    public let digest: Data

    public let byteCount: Int

    public init(id: AttachmentID, key: Data, digest: Data, byteCount: Int) {
        self.id = id
        self.key = key
        self.digest = digest
        self.byteCount = byteCount
    }
}

public enum AttachmentError: Error, Hashable, Sendable {
    case digestMismatch
    case openFailed
    case tooLarge
    case previewTooLarge
}

public enum SealedAttachment {
    public static func maximumPlaintextBytes(for kind: MediaKind) -> Int {
        switch kind {
        case .image: 12 * 1024 * 1024
        case .video: 40 * 1024 * 1024
        }
    }

    public static var maximumPlaintextBytes: Int { maximumPlaintextBytes(for: .image) }

    public static func seal(
        _ plaintext: Data, id: AttachmentID = AttachmentID(), kind: MediaKind = .image
    ) throws -> (reference: AttachmentReference, ciphertext: Data) {
        guard plaintext.count <= maximumPlaintextBytes(for: kind) else {
            throw AttachmentError.tooLarge
        }

        let key = SymmetricKey(size: .bits256)
        let box = try ChaChaPoly.seal(plaintext, using: key, authenticating: context(id: id))
        let ciphertext = box.combined
        let reference = AttachmentReference(
            id: id,
            key: key.withUnsafeBytes { Data($0) },
            digest: Data(SHA256.hash(data: ciphertext)),
            byteCount: ciphertext.count)
        return (reference, ciphertext)
    }

    public static func matches(_ ciphertext: Data, _ reference: AttachmentReference) -> Bool {
        Data(SHA256.hash(data: ciphertext)) == reference.digest
    }

    public static func open(_ ciphertext: Data, with reference: AttachmentReference) throws -> Data {
        guard matches(ciphertext, reference) else { throw AttachmentError.digestMismatch }
        guard let box = try? ChaChaPoly.SealedBox(combined: ciphertext),
            let plaintext = try? ChaChaPoly.open(
                box, using: SymmetricKey(data: reference.key),
                authenticating: context(id: reference.id))
        else { throw AttachmentError.openFailed }
        return plaintext
    }

    static func context(id: AttachmentID) -> Data {
        CanonicalBytes.payload(
            domain: Domain.attachment,
            fields: [withUnsafeBytes(of: id.rawValue.uuid) { Data($0) }])
    }
}
