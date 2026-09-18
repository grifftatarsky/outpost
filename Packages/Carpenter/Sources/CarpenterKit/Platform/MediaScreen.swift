import Foundation

public enum ScreeningAvailability: Hashable, Sendable {
    case available
    case offInSystemSettings
    case unsupported
}

public protocol MediaScreen: Sendable {
    func availability() async -> ScreeningAvailability

    func isSensitive(image data: Data) async throws -> Bool

    func isSensitive(videoAt url: URL) async throws -> Bool
}
