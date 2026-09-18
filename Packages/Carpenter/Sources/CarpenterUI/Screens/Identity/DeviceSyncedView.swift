import SwiftUI

public struct DeviceSyncedView: View {
    public enum Arrival: Sendable, Equatable {
        case keychain
        case recoveryKey
    }

    @Environment(\.palette) private var palette

    private let memberName: String
    private let arrival: Arrival
    private let onContinue: () -> Void

    public init(
        memberName: String, arrival: Arrival = .keychain, onContinue: @escaping () -> Void
    ) {
        self.memberName = memberName
        self.arrival = arrival
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(palette.accentColor)

            headline
                .font(CarpenterFont.navigationTitle)
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.center)

            detail
            .font(CarpenterFont.rowDetail)
            .foregroundStyle(palette.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 34)

            Spacer()

            Button(action: onContinue) {
                Text("Continue", bundle: .module)
                    .font(CarpenterFont.button)
                    .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accentFill)
            .padding(.horizontal, CarpenterMetrics.screenMargin)
            .padding(.bottom, 22)
        }
        .background(palette.background)
    }

    private var headline: Text {
        switch arrival {
        case .keychain:
            Text("This device is now yours too", bundle: .module)
        case .recoveryKey:
            Text("This device is you again", bundle: .module)
        }
    }

    private var detail: Text {
        switch arrival {
        case .keychain:
            Text(
                "It recognized your keys from iCloud and joined your account as \(memberName). Nothing to set up — your rooms are already here.",
                bundle: .module)
        case .recoveryKey:
            Text(
                "Your key put you back as \(memberName). Your rooms return as the people in them reach you again, and what was said comes from whoever still holds it.",
                bundle: .module)
        }
    }
}

#if DEBUG
    #Preview("Device synced — dark") {
        DeviceSyncedView(memberName: "Griff", onContinue: {})
            .themed(.default).preferredColorScheme(.dark)
    }

    #Preview("Device synced — light") {
        DeviceSyncedView(memberName: "Griff", onContinue: {})
            .themed(.default).preferredColorScheme(.light)
    }

    #Preview("Device synced — back from a recovery key") {
        DeviceSyncedView(memberName: "Griff", arrival: .recoveryKey, onContinue: {})
            .themed(.default).preferredColorScheme(.dark)
    }
#endif
