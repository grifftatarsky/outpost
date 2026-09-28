import Foundation

extension Data {
    public var lowercaseHex: String {
        var digits: [UInt8] = []
        digits.reserveCapacity(count * 2)
        for byte in self {
            digits.append(Self.hexDigits[Int(byte >> 4)])
            digits.append(Self.hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: digits, as: UTF8.self)
    }

    public init?(lowercaseHex digits: some StringProtocol) {
        let characters = Array(digits.utf8)
        guard !characters.isEmpty, characters.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let high = Self.hexValue(of: characters[index]), let low = Self.hexValue(of: characters[index + 1])
            else { return nil }
            bytes.append(high << 4 | low)
        }
        self = bytes
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    private static func hexValue(of digit: UInt8) -> UInt8? {
        hexDigits.firstIndex(of: digit).map { UInt8($0) }
    }
}
