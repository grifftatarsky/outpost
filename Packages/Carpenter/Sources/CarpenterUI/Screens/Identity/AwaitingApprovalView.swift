import CarpenterKit
import SwiftUI

public struct AwaitingApprovalView: View {
    @Environment(\.palette) private var palette

    private let code: String
    private let askFailed: Bool
    private let onAskAgain: () async -> Void
    private let onRecoveryKey: () -> Void

    @State private var asking = false

    public init(
        code: String, askFailed: Bool = false, onAskAgain: @escaping () async -> Void = {},
        onRecoveryKey: @escaping () -> Void
    ) {
        self.code = code
        self.askFailed = askFailed
        self.onAskAgain = onAskAgain
        self.onRecoveryKey = onRecoveryKey
    }

    public var body: some View {
        ContentUnavailableView {
            // COPY BEGIN 7633fe46 [NEEDS HUMAN REVIEW]
            Label {
                Text("Approve this device", bundle: .module)
            } icon: {
                Image(systemName: "ipad.and.iphone")
            }
        } description: {
            VStack(spacing: 16) {
                Text(
                    "Open \(Branding.displayName) on one of your other devices and approve this one. It will show this code:",
                    bundle: .module)
                Text(verbatim: code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))
                if askFailed {
                    Text("This device could not reach iCloud to ask. Check that it is online, then ask again.", bundle: .module)
                } else {
                    Text("If your other device said no, or nothing appears on it, ask again.", bundle: .module)
                }
            }
        } actions: {
            Button {
                Task {
                    asking = true
                    await onAskAgain()
                    asking = false
                }
            } label: {
                Text("Ask again", bundle: .module)
            }
            .disabled(asking)
            Button(action: onRecoveryKey) {
                Text("I have a recovery key", bundle: .module)
            }
            // COPY END 7633fe46
        }
        .background(palette.background)
    }
}

#if DEBUG
    #Preview("Waiting for approval") {
        AwaitingApprovalView(code: "7K3M9Q", onRecoveryKey: {})
            .themed(.default)
    }
#endif
