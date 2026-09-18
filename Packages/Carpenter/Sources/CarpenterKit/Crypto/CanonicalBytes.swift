import Foundation

public enum CanonicalBytes {
    public static func payload(domain: String, fields: [Data]) -> Data {
        var out = Data()

        let tag = Data(domain.utf8)
        out.append(bigEndian(UInt32(tag.count)))
        out.append(tag)

        for field in fields {
            out.append(bigEndian(UInt32(field.count)))
            out.append(field)
        }

        return out
    }

    public static func timestamp(_ date: Date) -> Data {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        return bigEndian(UInt64(bitPattern: milliseconds))
    }

    public static func sequence(_ value: UInt64) -> Data {
        bigEndian(value)
    }

    public static func optional(_ value: Data?) -> [Data] {
        guard let value else { return [Data([0])] }
        return [Data([1]), value]
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func bigEndian(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

public enum CryptoError: Error, Hashable, Sendable {
    case malformedKey
    case malformedSignature
    case badSignature
    case participantMismatch
    case deviceMismatch
    case unknownDevice
    case unknownEpoch
    case wrongRoom
    case openFailed
}
