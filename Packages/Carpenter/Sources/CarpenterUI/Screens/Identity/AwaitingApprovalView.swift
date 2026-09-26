import CarpenterKit
import SwiftUI

public struct AwaitingApprovalView: View {
    @Environment(\.palette) private var palette

    private let code: String
    private let onRecoveryKey: () -> Void

    public init(code: String, onRecoveryKey: @escaping () -> Void) {
        self.code = code
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
            }
        } actions: {
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
