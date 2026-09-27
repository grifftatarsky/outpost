import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

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
