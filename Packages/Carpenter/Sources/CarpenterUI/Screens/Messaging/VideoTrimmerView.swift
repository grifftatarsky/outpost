#if canImport(UIKit)
    import CarpenterKit
    import SwiftUI
    import UIKit

    struct VideoTrimmerView: UIViewControllerRepresentable {
        let url: URL
        let maximumDuration: TimeInterval
        let onTrimmed: (URL) -> Void
        let onCancel: () -> Void

        static func canTrim(_ url: URL) -> Bool {
            UIVideoEditorController.canEditVideo(atPath: url.path)
        }

        func makeUIViewController(context: Context) -> UIVideoEditorController {
            let editor = UIVideoEditorController()
            editor.videoPath = url.path
            editor.videoMaximumDuration = maximumDuration
            editor.videoQuality = .typeHigh
            editor.delegate = context.coordinator
            return editor
        }

        func updateUIViewController(_ controller: UIVideoEditorController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        final class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
            private let parent: VideoTrimmerView

            init(_ parent: VideoTrimmerView) { self.parent = parent }

            func videoEditorController(
                _ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String
            ) {
                parent.onTrimmed(URL(fileURLWithPath: editedVideoPath))
            }

            func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) {
                parent.onCancel()
            }

            func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: any Error) {
                Diagnostics.sync.error(
                    "media: the system trimmer failed (\(String(describing: error), privacy: .public))")
                parent.onCancel()
            }
        }
    }
#endif
