import Compression
import Foundation

public enum Compressed {
    public enum Failure: Error, Hashable, Sendable {
        case tooLarge(Int)
        case damaged
    }

    static let mark = Data("cz1".utf8)
    public static let cap = 32 * 1024 * 1024

    public static func pack(_ plain: Data) -> Data {
        guard plain.count <= cap, !plain.isEmpty,
            let squeezed = try? (plain as NSData).compressed(using: .lzfse) as Data,
            squeezed.count + mark.count + 4 < plain.count
        else { return plain }
        var out = mark
        withUnsafeBytes(of: UInt32(plain.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(squeezed)
        return out
    }

    public static func unpack(_ data: Data, cap: Int = Compressed.cap) throws -> Data {
        guard data.starts(with: mark) else { return data }
        let header = mark.count + 4
        guard data.count > header else { throw Failure.damaged }
        let declared = data.dropFirst(mark.count).prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard declared > 0 else { throw Failure.damaged }
        guard declared <= cap else { throw Failure.tooLarge(declared) }
        let body = Data(data.dropFirst(header))
        var out = Data(count: declared + 1)
        let written = out.withUnsafeMutableBytes { destination in
            body.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, declared + 1,
                    source.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written == declared else { throw written > declared ? Failure.tooLarge(written) : Failure.damaged }
        out.count = declared
        return out
    }
}
