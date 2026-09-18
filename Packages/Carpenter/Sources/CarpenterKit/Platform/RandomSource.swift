import Foundation

public protocol RandomSource: Sendable {
    func bytes(count: Int) -> Data
}

public struct SystemRandomSource: RandomSource {
    public init() {}

    public func bytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
