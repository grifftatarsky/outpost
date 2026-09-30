import CryptoKit
import Foundation

public struct PhotoCopyName: Hashable, Sendable {
    public let rawValue: Data

    public init(of photo: AttachmentID, between pair: PairwiseSecret) {
        let code = HMAC<SHA256>.authenticationCode(
            for: CanonicalBytes.payload(domain: Domain.photoCopyName, fields: [CanonicalBytes.uuid(photo.rawValue)]),
            using: pair.symmetricKey)
        rawValue = Data(code.prefix(Self.width))
    }

    public init?(recordName: String) {
        self.init(spelled: recordName, after: Self.recordPrefix)
    }

    public init?(receiptName: String) {
        guard receiptName.hasPrefix(Self.receiptPrefix) else { return nil }
        let rest = receiptName.dropFirst(Self.receiptPrefix.count)
        self.init(spelled: Self.receiptPrefix + (rest.split(separator: "-").first ?? ""), after: Self.receiptPrefix)
    }

    public var recordName: String { Self.recordPrefix + rawValue.lowercaseHex }

    public func receiptName(by device: DeviceID) -> String {
        Self.receiptPrefix + rawValue.lowercaseHex + "-" + device.rawValue.prefix(Self.width).lowercaseHex
    }

    public func receiptsAmong(_ names: some Sequence<String>) -> [String] {
        names.filter { Self.init(receiptName: $0) == self }
    }

    private static let width = 16
    private static let recordPrefix = "photo-"
    private static let receiptPrefix = "photo-receipt-"

    private init?(spelled name: String, after prefix: String) {
        guard name.hasPrefix(prefix), let bytes = Data(lowercaseHex: name.dropFirst(prefix.count)),
            bytes.count == Self.width
        else { return nil }
        rawValue = bytes
    }
}

public struct PhotoCopy: Hashable, Sendable {
    public let name: PhotoCopyName
    public let tag: RecipientTag
    public let label: Data
    public let sealed: Data

    public init(name: PhotoCopyName, tag: RecipientTag, label: Data, sealed: Data) {
        self.name = name
        self.tag = tag
        self.label = label
        self.sealed = sealed
    }

    public static func seal(
        _ ciphertext: Data, of photo: AttachmentID, for tag: RecipientTag, between pair: PairwiseSecret
    ) throws -> PhotoCopy {
        let name = PhotoCopyName(of: photo, between: pair)
        return PhotoCopy(
            name: name, tag: tag,
            label: try pair.wrap(Data(photo.rawValue.uuidString.utf8), context: labelContext(name)),
            sealed: try pair.wrap(ciphertext, context: context(of: photo)))
    }

    public static func photo(labelled label: Data, named name: PhotoCopyName, between pair: PairwiseSecret)
        -> AttachmentID?
    {
        guard let spelled = try? pair.unwrap(label, context: labelContext(name)),
            let uuid = UUID(uuidString: String(decoding: spelled, as: UTF8.self))
        else { return nil }
        let photo = AttachmentID(rawValue: uuid)
        return PhotoCopyName(of: photo, between: pair) == name ? photo : nil
    }

    public static func open(
        _ downloaded: Data, of photo: AttachmentID, matching digest: Data, between pair: PairwiseSecret
    ) throws -> Data {
        if Data(SHA256.hash(data: downloaded)) == digest { return downloaded }
        guard let opened = try? pair.unwrap(downloaded, context: context(of: photo)),
            Data(SHA256.hash(data: opened)) == digest
        else { throw AttachmentError.digestMismatch }
        return opened
    }

    static func context(of photo: AttachmentID) -> Data {
        CanonicalBytes.payload(domain: Domain.photoCopy, fields: [CanonicalBytes.uuid(photo.rawValue)])
    }

    static func labelContext(_ name: PhotoCopyName) -> Data {
        CanonicalBytes.payload(domain: Domain.photoCopyLabel, fields: [name.rawValue])
    }
}
