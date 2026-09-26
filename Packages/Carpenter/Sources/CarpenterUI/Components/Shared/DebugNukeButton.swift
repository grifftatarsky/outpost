import SwiftUI

public struct DebugNukeButton: View {
    @Environment(\.palette) private var palette

    private let action: () async -> Void

    @State private var confirming = false
    @State private var running = false

    public init(action: @escaping () async -> Void) {
        self.action = action
    }

    public var body: some View {
        Button {
            confirming = true
        } label: {
            Label {
                // COPY BEGIN 4987e07b [NEEDS HUMAN REVIEW]
                Text("Nuke this account", bundle: .module)
                    .font(CarpenterFont.button)
                // COPY END 4987e07b
            } icon: {
                Image("NukeMark", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
            }
            .foregroundStyle(palette.destructive)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay {
                Capsule().strokeBorder(
                    palette.destructive, lineWidth: CarpenterMetrics.hairline * 2)
            }
        }
        .buttonStyle(.plain)
        .tint(palette.destructive)
        .disabled(running)
        // COPY BEGIN 0303c9a1 [NEEDS HUMAN REVIEW]
        .accessibilityHint(Text("Erases this Apple Account and starts over", bundle: .module))
        .alert(
            Text("Erase this Apple Account?", bundle: .module),
            isPresented: $confirming
        ) {
            Button(role: .destructive) {
                Task {
                    running = true
                    await action()
                    running = false
                }
            } label: {
                Text("Erase everything", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "Erases the CloudKit zone, every key this app has stored, and the log on this device — then starts over. It reaches every device on this Apple Account, not just this one.",
                bundle: .module
            )
        // COPY END 0303c9a1
        }
    }
}

#if DEBUG
    #Preview("The nuke") {
        DebugNukeButton {}
            .themed(.default)
            .preferredColorScheme(.dark)
    }
#endif
