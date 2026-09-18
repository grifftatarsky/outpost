import CarpenterKit
import CoreGraphics
import Foundation
import ImageIO
import SensitiveContentAnalysis

public struct SystemMediaScreen: MediaScreen {
    public struct Unavailable: Error {}

    public init() {}

    public func availability() async -> ScreeningAvailability {
        SCSensitivityAnalyzer().analysisPolicy == .disabled ? .offInSystemSettings : .available
    }

    public func isSensitive(image data: Data) async throws -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else { throw Unavailable() }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImagePreparer.Failure.undecodable }
        return try await analyzer.analyzeImage(image).isSensitive
    }

    public func isSensitive(videoAt url: URL) async throws -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else { throw Unavailable() }
        return try await analyzer.videoAnalysis(forFileAt: url).hasSensitiveContent().isSensitive
    }
}
