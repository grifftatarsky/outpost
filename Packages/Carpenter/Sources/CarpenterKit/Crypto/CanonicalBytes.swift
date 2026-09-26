import Foundation

public enum CanonicalBytes {
    public static func payload(domain: String, fields: [Data]) -> Data {
        let tag = Data(domain.utf8)
        var out = Data()
        out.reserveCapacity(fields.reduce(4 + tag.count) { $0 + 4 + $1.count })

        out.append(bigEndian(UInt32(tag.count)))
        out.append(tag)

        for field in fields {
            out.append(bigEndian(UInt32(field.count)))
            out.append(field)
        }

        return out
    }

    public static func timestamp(_ date: Date) -> Data {
        let exact = (date.timeIntervalSince1970 * 1_000).rounded()
        let milliseconds = Int64(exactly: exact) ?? (exact > 0 ? .max : .min)
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
    case notSealedForThisDevice
    case malformedSignature
    case badSignature
    case participantMismatch
    case deviceMismatch
    case unknownDevice
    case unknownEpoch
    case wrongRoom
    case openFailed
}
