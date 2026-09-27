import SwiftUI

public struct RemovedDeviceView: View {
    @Environment(\.palette) private var palette

    private let onRestore: () -> Void

    public init(onRestore: @escaping () -> Void) {
        self.onRestore = onRestore
    }

    public var body: some View {
        ContentUnavailableView {
            // COPY BEGIN ca91d2d2 [NEEDS HUMAN REVIEW]
            Label {
                Text("This device was removed", bundle: .module)
            } icon: {
                Image(systemName: "iphone.slash")
            }
        } description: {
            Text(
                "This device was removed, by another of your devices or by your recovery key. What it held has been erased, and it no longer receives your messages. To use it again, restore it with your recovery key, which removes every other device you have.",
                bundle: .module)
        } actions: {
            Button(action: onRestore) {
                Text("Use my recovery key", bundle: .module)
                    .font(CarpenterFont.button)
                    .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accentFill)
            // COPY END ca91d2d2
        }
        .background(palette.background)
    }
}

#if DEBUG
    #Preview("Removed") {
        RemovedDeviceView(onRestore: {})
            .themed(.default)
    }
#endif
