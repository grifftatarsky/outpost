import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

extension View {
    func presentingTrimmer(
        _ item: Binding<StagedAttachment?>, maximumDuration: TimeInterval,
        onTrimmed: @escaping (StagedAttachment, URL) -> Void
    ) -> some View {
        #if os(iOS)
            fullScreenCover(item: item) { staged in
                if case .video(let url) = staged.picked, VideoTrimmerView.canTrim(url) {
                    VideoTrimmerView(
                        url: url, maximumDuration: maximumDuration,
                        onTrimmed: { trimmed in
                            item.wrappedValue = nil
                            onTrimmed(staged, trimmed)
                        },
                        onCancel: { item.wrappedValue = nil })
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("This clip cannot be trimmed here", bundle: .module)
                        } icon: {
                            Image(systemName: "scissors")
                        }
                    } description: {
                        Text("Trim it in Photos to a minute or less, then pick it again.", bundle: .module)
                    } actions: {
                        Button { item.wrappedValue = nil } label: { Text("OK", bundle: .module) }
                    }
                }
            }
        #else
            self
        #endif
    }
}

struct PickedClip: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { clip in
            SentTransferredFile(clip.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedClip(url: copy)
        }
    }
}
