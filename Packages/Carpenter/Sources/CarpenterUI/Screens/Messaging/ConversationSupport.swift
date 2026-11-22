import CarpenterKit
import CarpenterMedia
import PhotosUI
import SwiftUI

struct PickedClip: Transferable {
    let file: ScratchFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { clip in
            SentTransferredFile(clip.file.url)
        } importing: { received in
            let copy = try ScratchSpace.shared.newFile("picked", extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy.url)
            try copy.protect()
            return PickedClip(file: copy)
        }
    }
}
