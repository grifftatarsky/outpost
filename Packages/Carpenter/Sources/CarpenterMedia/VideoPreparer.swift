import AVFoundation
import CarpenterKit
import CoreGraphics
import Foundation

public enum VideoPreparer {
    public static let preset = AVAssetExportPreset960x540
    public static let maximumDuration: TimeInterval = 60

    public enum Failure: Error, Hashable, Sendable {
        case unreadable
        case tooLong(TimeInterval)
        case exportFailed(String)
        case noPoster
    }

    public static func prepare(_ url: URL, caption: String? = nil) async throws -> PreparedMedia {
        let asset = AVURLAsset(url: url)
        let duration: TimeInterval
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            throw Failure.unreadable
        }
        guard duration.isFinite, duration > 0 else { throw Failure.unreadable }
        guard duration <= maximumDuration else { throw Failure.tooLong(duration) }

        let output = FileManager.default.temporaryDirectory
            .appending(path: "prepared-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        try await export(asset, to: output)

        let bytes = try Data(contentsOf: output)
        let exported = AVURLAsset(url: output)
        let poster = try await posterFrame(of: exported)
        let size = try await naturalSize(of: exported)

        let preview = try? ImagePreparer.jpeg(
            try ImagePreparer.scaled(poster, to: ImagePreparer.previewLongestEdge),
            quality: ImagePreparer.previewQuality)

        return PreparedMedia(
            kind: .video,
            width: size.width,
            height: size.height,
            bytes: bytes,
            preview: preview.flatMap { $0.count <= MediaBody.previewByteCap ? $0 : nil },
            caption: caption,
            duration: duration)
    }

    static func export(_ asset: AVURLAsset, to output: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.exportFailed("no export session for \(preset)")
        }
        session.shouldOptimizeForNetworkUse = true
        session.metadataItemFilter = .forSharing()
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            throw Failure.exportFailed(String(describing: error))
        }
    }

    public static func posterFrame(of asset: AVAsset) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            return try await generator.image(at: .zero).image
        } catch {
            throw Failure.noPoster
        }
    }

    static func naturalSize(of asset: AVAsset) async throws -> (width: Int, height: Int) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.unreadable
        }
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rotated = size.applying(transform)
        return (Int(abs(rotated.width).rounded()), Int(abs(rotated.height).rounded()))
    }

    public static func duration(of url: URL) async throws -> TimeInterval {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    public static func identifyingMetadata(of url: URL) async throws -> [String] {
        let asset = AVURLAsset(url: url)
        var found: [String] = []
        for item in try await asset.load(.metadata) {
            guard let identifier = item.identifier?.rawValue else { continue }
            let lowered = identifier.lowercased()
            if lowered.contains("location") || lowered.contains("gps") || lowered.contains("make")
                || lowered.contains("model") || lowered.contains("software") || lowered.contains("creationdate")
                || lowered.contains("author") || lowered.contains("artist") || lowered.contains("copyright")
                || lowered.contains("identifier")
            {
                found.append(identifier)
            }
        }
        return found.sorted()
    }
}
