import AVFoundation
import CarpenterKit
import CarpenterMedia
import Foundation
import Testing

@Suite("Preparing a clip to send", .serialized)
struct VideoPreparerTests {
    @Test("A clip that fits goes as it was recorded, at its own size and length")
    func sentAsRecorded() async throws {
        let original = try await TestVideo.make(seconds: 3)
        defer { try? FileManager.default.removeItem(at: original) }

        let prepared = try await VideoPreparer.prepare(original)

        #expect(prepared.kind == .video)
        #expect(prepared.width == 1280 && prepared.height == 720, "\(prepared.width)×\(prepared.height)")
        let duration = try #require(prepared.duration)
        #expect(abs(duration - 3) < 0.2, "ran \(duration)s")
        let file = try #require(prepared.file, "a clip is handed over as a file")
        defer { try? FileManager.default.removeItem(at: file) }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        #expect(size > 0)
        #expect(size <= VideoPreparer.maximumBytes)
        #expect(prepared.bytes.isEmpty, "a clip was read into memory")
    }

    @Test("Location and camera are stripped")
    func metadataIsStripped() async throws {
        let original = try await TestVideo.make(seconds: 2)
        defer { try? FileManager.default.removeItem(at: original) }
        let before = try await VideoPreparer.identifyingMetadata(of: original)
        try #require(!before.isEmpty, "the fixture carries no identifying tags, so this test proves nothing")

        let prepared = try await VideoPreparer.prepare(original)

        let output = try #require(prepared.file)
        defer { try? FileManager.default.removeItem(at: output) }
        let after = try await VideoPreparer.identifyingMetadata(of: output)
        #expect(after.isEmpty, "identifying metadata survived: \(after)")
    }

    @Test("A clip keeps only its picture and sound: no track of timed location or anything else rides along")
    func timedMetadataIsDropped() async throws {
        let original = try await TestVideo.make(seconds: 2, timedLocation: true)
        defer { try? FileManager.default.removeItem(at: original) }
        let carried = try await AVURLAsset(url: original).loadTracks(withMediaType: .metadata)
        try #require(!carried.isEmpty, "the fixture carries no timed metadata, so this test proves nothing")

        let prepared = try await VideoPreparer.prepare(original)
        let file = try #require(prepared.file)
        defer { try? FileManager.default.removeItem(at: file) }
        let tracks = try await AVURLAsset(url: file).load(.tracks)
        #expect(
            tracks.allSatisfy { $0.mediaType == .video || $0.mediaType == .audio },
            "a clip went out with tracks other than picture and sound: \(tracks.map(\.mediaType.rawValue))")

        let fitted = try await VideoPreparer.prepareToFit(original, limit: 200_000)
        let fittedFile = try #require(fitted.file)
        defer { try? FileManager.default.removeItem(at: fittedFile) }
        let fittedTracks = try await AVURLAsset(url: fittedFile).load(.tracks)
        #expect(fittedTracks.allSatisfy { $0.mediaType == .video || $0.mediaType == .audio })
    }

    @Test("The first frame becomes a preview that fits the entry")
    func previewFits() async throws {
        let original = try await TestVideo.make(seconds: 1)
        defer { try? FileManager.default.removeItem(at: original) }
        let prepared = try await VideoPreparer.prepare(original)
        defer { prepared.file.map { try? FileManager.default.removeItem(at: $0) } }
        let preview = try #require(prepared.preview)
        #expect(preview.count <= MediaBody.previewByteCap)
        let size = try #require(ImagePreparer.size(of: preview))
        #expect(max(size.width, size.height) <= ImagePreparer.previewLongestEdge)
        #expect(ImagePreparer.identifyingMetadata(of: preview).isEmpty)
    }

    @Test("A clip longer than a minute is prepared, because the limit is its size, not its length")
    func lengthIsNotALimit() async throws {
        let long = try await TestVideo.make(seconds: 75, size: CGSize(width: 64, height: 64), fps: 1)
        defer { try? FileManager.default.removeItem(at: long) }
        let prepared = try await VideoPreparer.prepare(long)
        defer { prepared.file.map { try? FileManager.default.removeItem(at: $0) } }
        #expect(abs((prepared.duration ?? 0) - 75) < 1)
    }

    @Test("A clip over the limit is refused as it is, and made to fit only when asked")
    func tooLargeUntilAskedToFit() async throws {
        let original = try await TestVideo.make(
            seconds: 3, size: CGSize(width: 640, height: 360), fps: 10, noisy: true)
        defer { try? FileManager.default.removeItem(at: original) }
        let recorded = VideoPreparerTestsSize.of(original)
        let limit = recorded / 4
        try #require(limit > 50_000, "the fixture is too small to need fitting: \(recorded) bytes")

        await #expect(throws: VideoPreparer.Failure.self) {
            try await VideoPreparer.prepare(original, limit: limit)
        }

        let fitted = try await VideoPreparer.prepareToFit(original, limit: limit)
        let file = try #require(fitted.file)
        defer { try? FileManager.default.removeItem(at: file) }
        let size = VideoPreparerTestsSize.of(file)
        #expect(size <= limit, "made to fit, and came out at \(size) of \(limit)")
        #expect(Double(size) >= Double(limit) * 0.6, "came out at \(size), far under \(limit): the fit threw away more than it had to")
        #expect(abs((fitted.duration ?? 0) - 3) < 0.3, "the fit changed the length to \(fitted.duration ?? 0)")
        #expect(fitted.width <= 640 && fitted.height <= 360 && fitted.width % 2 == 0 && fitted.height % 2 == 0)
        #expect(abs(Double(fitted.width) / Double(fitted.height) - 16.0 / 9.0) < 0.05, "\(fitted.width)×\(fitted.height)")
        #expect(try await VideoPreparer.identifyingMetadata(of: file).isEmpty)
    }

    @Test("Making a clip fit keeps location and camera out of the file")
    func fittingStripsMetadata() async throws {
        let original = try await TestVideo.make(seconds: 2)
        defer { try? FileManager.default.removeItem(at: original) }
        try #require(!(try await VideoPreparer.identifyingMetadata(of: original)).isEmpty)
        let fitted = try await VideoPreparer.prepareToFit(original, limit: 200_000)
        let file = try #require(fitted.file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try await VideoPreparer.identifyingMetadata(of: file).isEmpty)
    }

    @Test("Something that is not a clip is refused")
    func garbageIsRefused() async throws {
        let junk = TestScratch.root.appending(path: "junk-\(UUID().uuidString).mov")
        try Data("not a clip".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        await #expect(throws: VideoPreparer.Failure.unreadable) {
            try await VideoPreparer.prepare(junk)
        }
        await #expect(throws: VideoPreparer.Failure.unreadable) {
            try await VideoPreparer.prepareToFit(junk)
        }
    }
}

enum VideoPreparerTestsSize {
    static func of(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}

@Suite("Working out how to make a clip fit")
struct FittingAClipTests {
    private let limit = VideoPreparer.maximumBytes

    private func plan(_ seconds: Double, _ width: Int = 3840, _ height: Int = 2160, fps: Double = 60, audio: Bool = true)
        -> VideoPreparer.FitPlan?
    {
        VideoPreparer.FitPlan.plan(
            duration: seconds, width: width, height: height, frameRate: fps, hasAudio: audio, limit: limit)
    }

    @Test("The plan spends the whole allowance, and a little less, whatever the length")
    func landsJustUnder() throws {
        for seconds in [30.0, 120, 600, 1800, 3600] {
            let plan = try #require(self.plan(seconds))
            let bytes = plan.expectedBytes(over: seconds)
            #expect(bytes <= Double(limit) * 0.96, "\(seconds)s planned \(bytes) bytes")
            #expect(bytes >= Double(limit) * 0.94, "\(seconds)s planned only \(bytes) bytes")
        }
    }

    @Test("A longer clip is drawn smaller, never larger, and never larger than it was recorded")
    func longerIsSmaller() throws {
        var last = Int.max
        for seconds in [10.0, 60, 300, 900, 1800, 3600, 7200] {
            let plan = try #require(self.plan(seconds))
            #expect(plan.width <= 3840 && plan.height <= 2160)
            #expect(plan.width <= last, "\(seconds)s grew to \(plan.width)")
            last = plan.width
        }
        let small = try #require(plan(60, 640, 360, fps: 30))
        #expect(small.width == 640 && small.height == 360, "a small clip was scaled up")
    }

    @Test("The picture keeps its shape, in even numbers, portrait or landscape")
    func keepsItsShape() throws {
        for (width, height) in [(3840, 2160), (2160, 3840), (1920, 1440), (1080, 1920), (1000, 1000)] {
            let plan = try #require(self.plan(1800, width, height))
            #expect(plan.width % 2 == 0 && plan.height % 2 == 0)
            let before = Double(width) / Double(height)
            let after = Double(plan.width) / Double(plan.height)
            #expect(abs(after - before) / before < 0.02, "\(width)×\(height) became \(plan.width)×\(plan.height)")
        }
    }

    @Test("A long clip drops to thirty frames a second before it drops more of its picture")
    func frameRateFirst() throws {
        let short = try #require(plan(20))
        #expect(short.frameRate == 60)
        let long = try #require(plan(1800))
        #expect(long.frameRate == 30)
    }

    @Test("Nothing is planned that could not be watched, or that has no length")
    func refusesTheImpossible() {
        #expect(plan(60 * 60 * 24 * 7) == nil, "a week of video was planned into one attachment")
        #expect(plan(0) == nil)
        #expect(plan(-5) == nil)
        #expect(plan(60, 0, 1080) == nil)
    }

    @Test("A plan asked for less draws smaller and spends less; asked for everything, it is the plan")
    func lowerQualityIsSmaller() throws {
        let plan = try #require(self.plan(600))
        #expect(plan.at(1) == plan)
        let less = plan.at(0.5)
        #expect(less.videoBitrate < plan.videoBitrate)
        #expect(less.width < plan.width && less.height < plan.height)
        #expect(less.width % 2 == 0 && less.height % 2 == 0)
        #expect(plan.at(4) == plan, "asking for more than the allowance drew bigger than the plan")
        let squeezed = plan.at(0.000_1)
        #expect(Double(max(squeezed.width, squeezed.height)) >= VideoPreparer.FitPlan.smallestEdge - 2)
    }

    @Test("A first try that fits closely is kept, and one that fits with room left is kept too when it is everything")
    func searchStopsWhenItIsClose() {
        var search = VideoPreparer.FitSearch(limit: 1_000)
        #expect(search.next == 1)
        search.record(1, 900)
        #expect(search.next == nil, "a try at 90% was not good enough")

        var easy = VideoPreparer.FitSearch(limit: 1_000)
        easy.record(1, 20)
        #expect(easy.next == nil, "a clip that is small at full quality was squeezed for more")
    }

    @Test("A try that comes out too big is followed by a smaller one, then one between the two")
    func searchCloses() throws {
        var search = VideoPreparer.FitSearch(limit: 1_000)
        search.record(1, 3_000)
        let second = try #require(search.next)
        #expect(second < 1 && abs(second - VideoPreparer.FitSearch.aim / 3) < 0.01)
        search.record(second, 600)
        let third = try #require(search.next)
        #expect(third > second && third < 1, "the third try was not between an under and an over")
        search.record(third, 950)
        #expect(search.next == nil, "a search ran past its passes")
    }

    @Test("A search that never fits gives up after its passes rather than trying forever")
    func searchGivesUp() {
        var search = VideoPreparer.FitSearch(limit: 1_000)
        var passes = 0
        while let quality = search.next {
            passes += 1
            search.record(quality, 5_000)
        }
        #expect(passes == VideoPreparer.FitSearch.passes)
    }
}
