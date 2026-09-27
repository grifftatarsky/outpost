import AVFoundation
import CarpenterKit
import CoreGraphics
import Foundation

public enum VideoPreparer {
    public static let maximumBytes = SealedAttachment.maximumVideoBytes

    public enum Failure: Error, Hashable, Sendable {
        case unreadable
        case tooLarge(Int)
        case exportFailed(String)
        case noPoster
        case cannotFit
    }

    public static func prepare(_ url: URL, caption: String? = nil, limit: Int = maximumBytes) async throws -> PreparedMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await readableDuration(of: asset)

        let output = FileManager.default.temporaryDirectory
            .appending(path: "prepared-\(UUID().uuidString).mp4")
        var kept = false
        defer { if !kept { try? FileManager.default.removeItem(at: output) } }
        do {
            try await export(asset, to: output, preset: AVAssetExportPresetPassthrough)
        } catch {
            try? FileManager.default.removeItem(at: output)
            try await export(asset, to: output, preset: AVAssetExportPresetHEVCHighestQuality)
        }

        let size = byteCount(of: output)
        guard size <= limit else { throw Failure.tooLarge(size) }
        let prepared = try await finished(output, caption: caption, duration: duration)
        kept = true
        return prepared
    }

    public static func sizeIfTooLarge(_ url: URL, limit: Int = maximumBytes) -> Int? {
        let size = byteCount(of: url)
        return size > limit ? size : nil
    }

    public static func prepareToFit(
        _ url: URL, caption: String? = nil, limit: Int = maximumBytes
    ) async throws -> PreparedMedia {
        let asset = AVURLAsset(url: url)
        let duration = try await readableDuration(of: asset)

        let base = try await plan(for: asset, duration: duration, limit: limit)
        var best: (file: URL, size: Int)?
        var kept = false
        defer { if !kept, let best { try? FileManager.default.removeItem(at: best.file) } }
        var search = FitSearch(limit: limit)
        while let quality = search.next {
            let output = FileManager.default.temporaryDirectory
                .appending(path: "fitted-\(UUID().uuidString).mp4")
            do {
                try await encode(asset, to: output, plan: base.at(quality))
            } catch {
                try? FileManager.default.removeItem(at: output)
                throw error
            }
            let size = byteCount(of: output)
            if size > 0, size <= limit, size > best?.size ?? 0 {
                if let best { try? FileManager.default.removeItem(at: best.file) }
                best = (output, size)
            } else {
                try? FileManager.default.removeItem(at: output)
            }
            search.record(quality, size)
        }
        guard let best else { throw Failure.cannotFit }
        let prepared = try await finished(best.file, caption: caption, duration: duration)
        kept = true
        return prepared
    }

    public struct FitPlan: Hashable, Sendable {
        public let width: Int
        public let height: Int
        public let frameRate: Double
        public let videoBitrate: Double
        public let audioBitrate: Double
        let recordedWidth: Int
        let recordedHeight: Int

        public static let headroom = 0.95
        public static let closeEnough = 0.85
        public static let bitsPerPixel = 0.07
        public static let smallestEdge = 320.0
        public static let smallestVideoBitrate = 150_000.0

        public static func plan(
            duration: TimeInterval, width: Int, height: Int, frameRate: Double, hasAudio: Bool, limit: Int
        ) -> FitPlan? {
            guard duration > 0, width > 0, height > 0, limit > 0 else { return nil }
            let total = Double(limit) * 8 * headroom / duration
            let audioBitrate = hasAudio ? (total >= 96_000 * 4 ? 96_000.0 : 64_000.0) : 0
            let videoBitrate = total - audioBitrate
            guard videoBitrate >= smallestVideoBitrate else { return nil }
            let rate = videoBitrate < 8_000_000 ? min(frameRate, 30) : min(frameRate, 60)
            let affordable = videoBitrate / (max(rate, 1) * bitsPerPixel)
            var scale = min(1, (affordable / Double(width * height)).squareRoot())
            let longest = Double(max(width, height))
            if longest * scale < smallestEdge { scale = min(1, smallestEdge / longest) }
            return FitPlan(
                width: even(Double(width) * scale), height: even(Double(height) * scale), frameRate: rate,
                videoBitrate: videoBitrate, audioBitrate: audioBitrate, recordedWidth: width, recordedHeight: height)
        }

        public func expectedBytes(over duration: TimeInterval) -> Double {
            (videoBitrate + audioBitrate) * duration / 8
        }

        public func at(_ quality: Double) -> FitPlan {
            let quality = min(1, max(0, quality))
            let recordedLongest = Double(max(recordedWidth, recordedHeight))
            let floor = min(1, Self.smallestEdge / recordedLongest)
            let planned = Double(max(width, height)) / recordedLongest
            let scale = min(planned, max(floor, planned * quality.squareRoot()))
            return FitPlan(
                width: Self.even(Double(recordedWidth) * scale), height: Self.even(Double(recordedHeight) * scale),
                frameRate: frameRate, videoBitrate: videoBitrate * quality, audioBitrate: audioBitrate,
                recordedWidth: recordedWidth, recordedHeight: recordedHeight)
        }

        private static func even(_ value: Double) -> Int {
            max(2, Int((value / 2).rounded()) * 2)
        }
    }

    public struct FitSearch: Sendable {
        public static let passes = 3
        public static let aim = 0.97

        let limit: Int
        private(set) var tried: [(quality: Double, size: Int)] = []

        public init(limit: Int) { self.limit = limit }

        public mutating func record(_ quality: Double, _ size: Int) {
            tried.append((quality, size))
        }

        public var next: Double? {
            guard let last = tried.last else { return 1 }
            guard tried.count < Self.passes, last.size > 0 else { return nil }
            let under = tried.filter { $0.size <= limit }.max { $0.size < $1.size }
            if let under, Double(under.size) >= Double(limit) * FitPlan.closeEnough { return nil }
            if let under, under.quality >= 1 { return nil }
            let target = Double(limit) * Self.aim
            let over = tried.filter { $0.size > limit }.min { $0.size < $1.size }
            var quality: Double
            if let under, let over, over.size > under.size {
                let share = (target - Double(under.size)) / Double(over.size - under.size)
                quality = under.quality + (over.quality - under.quality) * share
            } else {
                quality = last.quality * target / Double(last.size)
            }
            quality = min(1, quality)
            guard quality > 0, !tried.contains(where: { abs($0.quality - quality) < 0.01 }) else { return nil }
            return quality
        }
    }

    static func plan(for asset: AVURLAsset, duration: TimeInterval, limit: Int) async throws -> FitPlan {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unreadable }
        let (size, rate) = try await track.load(.naturalSize, .nominalFrameRate)
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        guard
            let plan = FitPlan.plan(
                duration: duration, width: Int(abs(size.width)), height: Int(abs(size.height)),
                frameRate: Double(rate > 0 ? rate : 30), hasAudio: hasAudio, limit: limit)
        else { throw Failure.cannotFit }
        return plan
    }

    static func encode(_ asset: AVURLAsset, to output: URL, plan: FitPlan) async throws {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.unreadable
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let transform = try await videoTrack.load(.preferredTransform)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        } catch {
            throw Failure.exportFailed(String(describing: error))
        }
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []

        let videoOut = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: plan.width,
                AVVideoHeightKey: plan.height,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Int(plan.videoBitrate),
                    AVVideoExpectedSourceFrameRateKey: Int(plan.frameRate.rounded()),
                    AVVideoMaxKeyFrameIntervalDurationKey: 2,
                ],
            ])
        videoIn.expectsMediaDataInRealTime = false
        videoIn.transform = transform
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack, plan.audioBitrate > 0 {
            let out = AVAssetReaderTrackOutput(
                track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(out)
            let into = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44_100,
                    AVEncoderBitRateKey: Int(plan.audioBitrate),
                ])
            into.expectsMediaDataInRealTime = false
            writer.add(into)
            (audioOut, audioIn) = (out, into)
        }

        guard reader.startReading(), writer.startWriting() else {
            throw Failure.exportFailed(String(describing: reader.error ?? writer.error))
        }
        writer.startSession(atSourceTime: .zero)

        let spacing = CMTime(seconds: 0.85 / plan.frameRate, preferredTimescale: 6000)
        var lanes = [Lane(output: videoOut, input: videoIn, spacing: spacing)]
        if let audioOut, let audioIn { lanes.append(Lane(output: audioOut, input: audioIn, spacing: nil)) }
        await Transfer(lanes: lanes).run()

        if reader.status == .failed { writer.cancelWriting(); throw Failure.exportFailed(String(describing: reader.error)) }
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.exportFailed(String(describing: writer.error)) }
    }

    private struct Lane {
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        let spacing: CMTime?
    }

    private final class Transfer: @unchecked Sendable {
        private let lanes: [Lane]
        private let queue = DispatchQueue(label: "video.fit")
        private var lastKept: [Int: CMTime] = [:]
        private var finished: Set<Int> = []

        init(lanes: [Lane]) { self.lanes = lanes }

        func run() async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                for index in lanes.indices {
                    group.enter()
                    lanes[index].input.requestMediaDataWhenReady(on: queue) { [self] in
                        if drain(index) { group.leave() }
                    }
                }
                group.notify(queue: queue) { done.resume() }
            }
        }

        private func drain(_ index: Int) -> Bool {
            guard !finished.contains(index) else { return false }
            let lane = lanes[index]
            while lane.input.isReadyForMoreMediaData {
                guard let sample = lane.output.copyNextSampleBuffer() else { return finish(index) }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                if let spacing = lane.spacing, let last = lastKept[index],
                    CMTimeCompare(CMTimeSubtract(time, last), spacing) < 0
                {
                    continue
                }
                lastKept[index] = time
                if !lane.input.append(sample) { return finish(index) }
            }
            return false
        }

        private func finish(_ index: Int) -> Bool {
            lanes[index].input.markAsFinished()
            return finished.insert(index).inserted
        }
    }

    private static func readableDuration(of asset: AVURLAsset) async throws -> TimeInterval {
        let duration: TimeInterval
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            throw Failure.unreadable
        }
        guard duration.isFinite, duration > 0 else { throw Failure.unreadable }
        return duration
    }

    private static func finished(_ output: URL, caption: String?, duration: TimeInterval) async throws -> PreparedMedia {
        let exported = AVURLAsset(url: output)
        let poster = try await posterFrame(of: exported)
        let dimensions = try await naturalSize(of: exported)
        let preview = try? ImagePreparer.jpeg(
            try ImagePreparer.scaled(poster, to: ImagePreparer.previewLongestEdge),
            quality: ImagePreparer.previewQuality)
        return PreparedMedia(
            kind: .video,
            width: dimensions.width,
            height: dimensions.height,
            file: output,
            preview: preview.flatMap { $0.count <= MediaBody.previewByteCap ? $0 : nil },
            caption: caption,
            duration: duration)
    }

    static func byteCount(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    static func export(_ asset: AVURLAsset, to output: URL, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.exportFailed("no export session for \(preset)")
        }
        session.shouldOptimizeForNetworkUse = true
        session.metadataItemFilter = .forSharing()
        session.metadata = []
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
        var items = try await asset.load(.metadata)
        for format in try await asset.load(.availableMetadataFormats) {
            items += try await asset.loadMetadata(for: format)
        }
        for item in items {
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
        return Array(Set(found)).sorted()
    }
}
