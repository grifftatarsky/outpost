import CryptoKit
import Foundation

public struct AttachmentID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct AttachmentPart: Hashable, Sendable, Codable {
    public let id: AttachmentID
    public let digest: Data
    public let byteCount: Int

    public init(id: AttachmentID, digest: Data, byteCount: Int) {
        self.id = id
        self.digest = digest
        self.byteCount = byteCount
    }
}

public struct AttachmentReference: Hashable, Sendable, Codable {
    public let id: AttachmentID

    public let key: Data

    public let digest: Data

    public let byteCount: Int

    public let parts: [AttachmentPart]?

    public init(id: AttachmentID, key: Data, digest: Data, byteCount: Int, parts: [AttachmentPart]? = nil) {
        self.id = id
        self.key = key
        self.digest = digest
        self.byteCount = byteCount
        self.parts = parts
    }

    public var transferIDs: [AttachmentID] { parts?.map(\.id) ?? [id] }
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
            fields: [CanonicalBytes.uuid(id.rawValue)])
    }
}

extension SealedAttachment {
    public static let partPlaintextBytes = 16 * 1024 * 1024

    public static let maximumVideoBytes = 287_000_000

    public static func sealParts(
        of file: URL, id: AttachmentID = AttachmentID(),
        take: @Sendable (AttachmentPart, Data) async throws -> Void
    ) async throws -> AttachmentReference {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw AttachmentError.openFailed }
        guard size <= maximumVideoBytes else { throw AttachmentError.tooLarge }
        let count = (size + partPlaintextBytes - 1) / partPlaintextBytes
        let key = SymmetricKey(size: .bits256)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var parts: [AttachmentPart] = []
        for index in 0..<count {
            guard let plaintext = try handle.read(upToCount: partPlaintextBytes), !plaintext.isEmpty else {
                throw AttachmentError.openFailed
            }
            let partID = AttachmentID()
            let ciphertext = try ChaChaPoly.seal(
                plaintext, using: key,
                authenticating: partContext(of: id, part: partID, index: index, count: count)
            ).combined
            let part = AttachmentPart(
                id: partID, digest: Data(SHA256.hash(data: ciphertext)), byteCount: ciphertext.count)
            try await take(part, ciphertext)
            parts.append(part)
        }
        return AttachmentReference(
            id: id, key: key.withUnsafeBytes { Data($0) }, digest: digest(of: parts),
            byteCount: parts.reduce(0) { $0 + $1.byteCount }, parts: parts)
    }

    public static func openParts(
        _ reference: AttachmentReference, into file: URL,
        part fetch: @Sendable (AttachmentPart) async throws -> Data?
    ) async throws -> Bool {
        guard let parts = reference.parts, !parts.isEmpty else { throw AttachmentError.openFailed }
        guard digest(of: parts) == reference.digest else { throw AttachmentError.digestMismatch }
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        let key = SymmetricKey(data: reference.key)
        for (index, part) in parts.enumerated() {
            guard let sealed = try await fetch(part) else { return false }
            guard Data(SHA256.hash(data: sealed)) == part.digest else { throw AttachmentError.digestMismatch }
            guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
                let plaintext = try? ChaChaPoly.open(
                    box, using: key,
                    authenticating: partContext(of: reference.id, part: part.id, index: index, count: parts.count))
            else { throw AttachmentError.openFailed }
            try handle.write(contentsOf: plaintext)
        }
        return true
    }

    static func digest(of parts: [AttachmentPart]) -> Data {
        Data(SHA256.hash(data: CanonicalBytes.payload(domain: Domain.attachment, fields: parts.map(\.digest))))
    }

    static func partContext(of id: AttachmentID, part: AttachmentID, index: Int, count: Int) -> Data {
        CanonicalBytes.payload(
            domain: Domain.attachment,
            fields: [
                CanonicalBytes.uuid(id.rawValue),
                CanonicalBytes.uuid(part.rawValue),
                Data("part \(index) of \(count)".utf8),
            ])
    }
}
