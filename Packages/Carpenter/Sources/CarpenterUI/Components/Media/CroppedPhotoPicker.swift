import CarpenterMedia
import PhotosUI
import SwiftUI

extension View {
    func croppingPickedPhoto(
        _ selection: Binding<PhotosPickerItem?>,
        onChosen: @escaping (PickedAvatar) async -> Void
    ) -> some View {
        modifier(CroppedPhotoPicker(selection: selection, onChosen: onChosen))
    }
}

private struct CroppedPhotoPicker: ViewModifier {
    @Binding var selection: PhotosPickerItem?
    let onChosen: (PickedAvatar) async -> Void

    @State private var pending: PendingPhoto?

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    selection = nil
                    guard let data else { return }
                    pending = PendingPhoto(data: data)
                }
            }
            .sizedSheet(item: $pending) { photo in
                AvatarCropView(photo.data) { crop in
                    Task { await onChosen(PickedAvatar(data: photo.data, crop: crop)) }
                }
            }
    }
}

private struct PendingPhoto: Identifiable {
    let id = UUID()
    let data: Data
}
