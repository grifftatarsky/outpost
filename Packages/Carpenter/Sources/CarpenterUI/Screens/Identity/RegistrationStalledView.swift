import CarpenterKit
import SwiftUI

public struct RegistrationStalledView: View {
    @Environment(\.palette) private var palette

    private let stall: RegistrationStall
    private let onRetry: () async -> Void
    private let onRestore: (() -> Void)?
    private let onNuke: (() async -> Void)?

    @State private var retrying = false

    public init(
        stall: RegistrationStall,
        onRetry: @escaping () async -> Void,
        onRestore: (() -> Void)? = nil,
        onNuke: (() async -> Void)? = nil
    ) {
        self.stall = stall
        self.onRetry = onRetry
        self.onRestore = onRestore
        self.onNuke = onNuke
    }

    public var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(palette.tertiaryText)
                .accessibilityHidden(true)

            headline
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            detail
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // COPY BEGIN fa05dc81 [NEEDS HUMAN REVIEW]
            Button {
                Task {
                    retrying = true
                    await onRetry()
                    retrying = false
                }
            } label: {
                Text("Check again", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(retrying)
            .padding(.horizontal, 32)
            .padding(.top, 6)
            // COPY END fa05dc81

            // COPY BEGIN c1d22f7a [NEEDS HUMAN REVIEW]
            if let onRestore, offersARecoveryKey {
                Button(action: onRestore) {
                    Text("I have a recovery key", bundle: .module)
                        .font(CarpenterFont.button)
                        .foregroundStyle(palette.accentColor)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                        .background(
                            palette.elevatedSurface,
                            in: .rect(cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            // COPY END c1d22f7a

            Spacer(minLength: 0)

            if let onNuke {
                DebugNukeButton(action: onNuke)
                    .padding(.bottom, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .accessibilityElement(children: .contain)
    }

    private var offersARecoveryKey: Bool {
        switch stall {
        case .accountHasAMember, .accountUnreadable, .accountOffline: true
        case .keychainUnreadable: false
        }
    }

    // COPY BEGIN 4f8229af [NEEDS HUMAN REVIEW]
    private var headline: Text {
        switch stall {
        case .accountHasAMember:
            Text("This Apple Account already has a member", bundle: .module)
        case .accountUnreadable:
            Text("Could not read this Apple Account", bundle: .module)
        case .accountOffline:
            Text("Could not reach iCloud", bundle: .module)
        case .keychainUnreadable:
            Text("The Keychain would not answer", bundle: .module)
        }
    }
    // COPY END 4f8229af

    // COPY BEGIN 682b13fe [NEEDS HUMAN REVIEW]
    private var detail: Text {
        switch stall {
        case .accountHasAMember:
            Text(
                "Their key has not reached this device. It travels through iCloud Keychain, so check that Passwords and Keychain sync is on for this device; this app will notice by itself if it arrives. If iCloud Keychain was reset, or sync was never on, it will not arrive, and a recovery key is the way back.",
                bundle: .module)
        case .accountUnreadable:
            Text(
                "iCloud answered, but not with an answer. This device will not offer to make a second member until it knows there is not one already.",
                bundle: .module)
        case .accountOffline:
            Text(
                "This device has to ask iCloud whether this Apple Account already has a member before it makes one, so there are never two of you. Check that it is online and signed in to iCloud in Settings, then try again.",
                bundle: .module)
        case .keychainUnreadable:
            Text(
                "This device cannot tell whether it already holds a member, so it will not make a second one. Unlocking the device and checking again usually settles it.",
                bundle: .module)
        }
    }
    // COPY END 682b13fe
}

#if DEBUG
    #Preview("Stalled — the account has a member") {
        RegistrationStalledView(
            stall: .accountHasAMember, onRetry: {}, onRestore: {}, onNuke: {})
            .themed(.default)
            .preferredColorScheme(.dark)
    }

    #Preview("Stalled — the account would not answer") {
        RegistrationStalledView(stall: .accountUnreadable, onRetry: {})
            .themed(.default)
            .preferredColorScheme(.light)
    }

    #Preview("Stalled — the Keychain would not answer") {
        RegistrationStalledView(stall: .keychainUnreadable, onRetry: {})
            .themed(.default)
            .preferredColorScheme(.dark)
    }
#endif
