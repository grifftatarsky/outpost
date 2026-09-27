import AVFoundation
import CarpenterKit
import CarpenterMedia
import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI

public struct DecodedImage: @unchecked Sendable, Equatable {
    public let cgImage: CGImage

    public init(cgImage: CGImage) { self.cgImage = cgImage }

    public static func == (lhs: DecodedImage, rhs: DecodedImage) -> Bool {
        lhs.cgImage === rhs.cgImage
    }

    public var image: Image { Image(decorative: cgImage, scale: 1) }
}

public enum ScreeningVerdict: Hashable, Sendable {
    case notScreened
    case clear
    case sensitive
}

public struct LoadedMedia: Equatable, Sendable {
    public let image: DecodedImage
    public let verdict: ScreeningVerdict
    public let video: URL?

    public init(image: DecodedImage, verdict: ScreeningVerdict, video: URL? = nil) {
        self.image = image
        self.verdict = verdict
        self.video = video
    }
}

public struct MediaAsking {
    public let canAsk: @MainActor (AttachmentID, ParticipantID) -> Bool
    public let isAsked: @MainActor (AttachmentID) -> Bool
    public let ask: @MainActor (AttachmentID, ParticipantID) async -> Bool

    public init(
        canAsk: @escaping @MainActor (AttachmentID, ParticipantID) -> Bool,
        isAsked: @escaping @MainActor (AttachmentID) -> Bool,
        ask: @escaping @MainActor (AttachmentID, ParticipantID) async -> Bool
    ) {
        self.canAsk = canAsk
        self.isAsked = isAsked
        self.ask = ask
    }
}

public enum MediaAskState: Equatable, Sendable {
    case unavailable
    case askable
    case asked
}

public enum MediaLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded(LoadedMedia)
    case gone
    case failed(String)
}

@MainActor
@Observable
public final class MediaLoader {
    public typealias Source = @MainActor (MediaAttachment, ParticipantID) async throws -> Data?
    public typealias ClipSource = @MainActor (MediaAttachment, ParticipantID, URL) async throws -> Bool

    private let source: Source
    private let clipSource: ClipSource?
    private let screen: (any MediaScreen)?
    private let defaults: UserDefaults
    private static let revealedKey = "media.revealed"

    private var states: [AttachmentID: MediaLoadState] = [:]
    private var tasks: [AttachmentID: Task<Void, Never>] = [:]
    private var previews: [AttachmentID: DecodedImage] = [:]
    private var revealed: Set<String>
    private var askedHere: Set<AttachmentID> = []
    @ObservationIgnored private var askable: [AttachmentID: Bool] = [:]
    @ObservationIgnored private var seenAsked: Set<AttachmentID> = []

    public var asking: MediaAsking?

    public var treatsEveryPhotoAsSensitive = false {
        didSet {
            guard treatsEveryPhotoAsSensitive != oldValue else { return }
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
            states.removeAll()
        }
    }

    nonisolated public static let playingDirectory = FileManager.default.temporaryDirectory
        .appending(path: "playing", directoryHint: .isDirectory)

    public init(
        source: @escaping Source, clipSource: ClipSource? = nil, screen: (any MediaScreen)?,
        defaults: UserDefaults = .standard
    ) {
        self.source = source
        self.clipSource = clipSource
        self.screen = screen
        self.defaults = defaults
        revealed = Set(defaults.stringArray(forKey: Self.revealedKey) ?? [])
        try? FileManager.default.removeItem(at: Self.playingDirectory)
    }

    public func state(of attachment: MediaAttachment, sentBy author: ParticipantID) -> MediaLoadState {
        if let state = states[attachment.id] { return state }
        load(attachment, from: author)
        return .loading
    }

    public func retry(_ attachment: MediaAttachment, sentBy author: ParticipantID) {
        guard tasks[attachment.id] == nil else { return }
        load(attachment, from: author)
    }

    public func askState(of attachment: MediaAttachment, sentBy author: ParticipantID) -> MediaAskState {
        guard let asking else { return .unavailable }
        if askedHere.contains(attachment.id) || asking.isAsked(attachment.id) {
            seenAsked.insert(attachment.id)
            return .asked
        }
        if let known = askable[attachment.id] { return known ? .askable : .unavailable }
        let can = asking.canAsk(attachment.id, author)
        askable[attachment.id] = can
        return can ? .askable : .unavailable
    }

    public func ask(for attachment: MediaAttachment, sentBy author: ParticipantID) {
        guard let asking, !askedHere.contains(attachment.id) else { return }
        askedHere.insert(attachment.id)
        Task {
            if !(await asking.ask(attachment.id, author)) { askedHere.remove(attachment.id) }
        }
    }

    public func reconsiderAsked() {
        guard let asking else { return }
        askable.removeAll()
        for id in seenAsked.union(askedHere) where !asking.isAsked(id) {
            seenAsked.remove(id)
            askedHere.remove(id)
            if states[id] == .gone { states[id] = nil }
        }
    }

    private func load(_ attachment: MediaAttachment, from author: ParticipantID) {
        states[attachment.id] = .loading
        tasks[attachment.id] = Task { [weak self] in
            guard let self else { return }
            let result = await fetch(attachment, from: author)
            states[attachment.id] = result
            tasks[attachment.id] = nil
        }
    }

    private func fetch(_ attachment: MediaAttachment, from author: ParticipantID) async -> MediaLoadState {
        do {
            if attachment.kind == .video, let clipSource {
                let url = try Self.playingFile(for: attachment.id)
                guard try await clipSource(attachment, author, url) else { return .gone }
                guard let poster = await Self.poster(of: url) else { return .failed(Self.undecodable) }
                return .loaded(LoadedMedia(image: poster, verdict: await verdict(videoAt: url), video: url))
            }
            guard let data = try await source(attachment, author) else { return .gone }
            switch attachment.kind {
            case .image:
                guard let image = await Self.decode(data) else { return .failed(Self.undecodable) }
                return .loaded(LoadedMedia(image: image, verdict: await verdict(imageData: data)))
            case .video:
                let url = try Self.writeForPlaying(data, id: attachment.id)
                guard let poster = await Self.poster(of: url) else { return .failed(Self.undecodable) }
                return .loaded(
                    LoadedMedia(image: poster, verdict: await verdict(videoAt: url), video: url))
            }
        } catch AttachmentError.digestMismatch {
            return .gone
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // COPY BEGIN 8bbbb833 [NEEDS HUMAN REVIEW]
    private static var undecodable: String {
        String(
            localized: "This could not be decoded.", bundle: .module,
            comment: "Bytes arrived, and are not a photo or a clip this device can draw")
    }
    // COPY END 8bbbb833

    private func verdict(imageData data: Data) async -> ScreeningVerdict {
        await verdict { screen in try await screen.isSensitive(image: data) }
    }

    private func verdict(videoAt url: URL) async -> ScreeningVerdict {
        await verdict { screen in try await screen.isSensitive(videoAt: url) }
    }

    private func verdict(
        _ look: (any MediaScreen) async throws -> Bool
    ) async -> ScreeningVerdict {
        if treatsEveryPhotoAsSensitive { return .sensitive }
        guard let screen, await screen.availability() == .available else { return .notScreened }
        do {
            return try await look(screen) ? .sensitive : .clear
        } catch {
            Diagnostics.sync.error(
                "media: screening declined to look (\(String(describing: error), privacy: .public))")
            return .notScreened
        }
    }

    nonisolated static func decode(_ data: Data) async -> DecodedImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(
                    source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { return nil }
            return DecodedImage(cgImage: image)
        }.value
    }

    nonisolated static func playingFile(for id: AttachmentID) throws -> URL {
        try writeForPlaying(Data(), id: id)
    }

    nonisolated static func writeForPlaying(_ data: Data, id: AttachmentID) throws -> URL {
        try FileManager.default.createDirectory(at: playingDirectory, withIntermediateDirectories: true)
        let url = playingDirectory.appending(path: "\(id.rawValue.uuidString).mp4")
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: url, options: [.atomic])
        #endif
        return url
    }

    nonisolated static func poster(of url: URL) async -> DecodedImage? {
        guard let frame = try? await VideoPreparer.posterFrame(of: AVURLAsset(url: url)) else {
            return nil
        }
        return DecodedImage(cgImage: frame)
    }

    public func preview(of attachment: MediaAttachment) -> DecodedImage? {
        if let cached = previews[attachment.id] { return cached }
        guard let data = attachment.preview,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let decoded = DecodedImage(cgImage: image)
        previews[attachment.id] = decoded
        return decoded
    }

    public func isRevealed(_ id: AttachmentID) -> Bool {
        revealed.contains(id.rawValue.uuidString)
    }

    public func reveal(_ id: AttachmentID) {
        revealed.insert(id.rawValue.uuidString)
        defaults.set(Array(revealed), forKey: Self.revealedKey)
    }
}

extension EnvironmentValues {
    @Entry public var mediaLoader: MediaLoader? = nil
}
