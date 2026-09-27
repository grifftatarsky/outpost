import CarpenterApp
import CarpenterCloudKit
import CarpenterKeychain
import CloudKit
import CarpenterKit
import CarpenterMedia
import CarpenterUI
import OSLog
import Intents
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

// MARK: Preparing what is attached, and loading it back

extension AppRootView {
    func attach(_ picked: PickedMedia, caption: String?, to room: RoomID) async -> String? {
        // COPY BEGIN c7bf5484 [NEEDS HUMAN REVIEW]
        do {
            try await session.send(try await prepare(picked, caption: caption), to: room, through: media)
            discardSources([picked])
            return nil
        } catch VideoPreparer.Failure.tooLarge(let bytes) {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return String(
                localized: "Videos up to 287 MB can be sent. This one is \(size).",
                comment: "A clip larger than the limit once prepared")
        } catch {
            Diagnostics.sync.error("attach failed: \(String(describing: error), privacy: .public)")
            return SessionProblem.sentence(for: error)
        }
        // COPY END c7bf5484
    }

    func post(_ picked: [PickedMedia], caption: String?) async -> String? {
        do {
            var prepared: [PreparedMedia] = []
            for (index, one) in picked.enumerated() {
                prepared.append(try await prepare(one, caption: index == 0 ? caption : nil))
            }
            try await session.post(prepared, through: media)
            discardSources(picked)
            return nil
        } catch VideoPreparer.Failure.tooLarge(let bytes) {
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            // COPY BEGIN 6f398e13 [NEEDS HUMAN REVIEW]
            return String(
                localized: "Clips up to 287 MB can be posted. One of these is \(size).",
                comment: "A clip larger than the limit once prepared, picked for a post")
            // COPY END 6f398e13
        } catch {
            Diagnostics.sync.error("post attach failed: \(String(describing: error), privacy: .public)")
            return SessionProblem.sentence(for: error)
        }
    }

    private func prepare(_ picked: PickedMedia, caption: String?) async throws -> PreparedMedia {
        switch picked {
        case .image(let data):
            return try await Task.detached(priority: .userInitiated) {
                try ImagePreparer.prepare(data, caption: caption)
            }.value
        case .video(let url):
            return try await VideoPreparer.prepare(url, caption: caption)
        }
    }

    private func discardSources(_ picked: [PickedMedia]) {
        for one in picked {
            guard case .video(let url) = one else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func makeMediaLoader() -> MediaLoader {
        let loader = MediaLoader(
            source: { [self] attachment, author in
                try await session.attachmentData(for: attachment, sentBy: author, through: media)
            },
            clipSource: { [self] attachment, author, file in
                try await session.writeClip(for: attachment, sentBy: author, through: media, to: file)
            },
            screen: SystemMediaScreen())
        loader.treatsEveryPhotoAsSensitive = safety.blursEveryPhoto
        return loader
    }
}
