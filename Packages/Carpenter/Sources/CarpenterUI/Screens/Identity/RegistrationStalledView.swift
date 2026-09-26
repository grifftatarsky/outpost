import CarpenterKit
import SwiftUI

public struct RegistrationStalledView: View {
    @Environment(\.palette) private var palette

    private let stall: RegistrationStall
    private let onRetry: () async -> Void
    private let onRestore: (() -> Void)?
    private let onNuke: (() async -> Void)?
    private let testProfiles: TestProfilesControl?

    @State private var retrying = false
    @State private var choosingTestProfile = false

    public init(
        stall: RegistrationStall,
        onRetry: @escaping () async -> Void,
        onRestore: (() -> Void)? = nil,
        onNuke: (() async -> Void)? = nil,
        testProfiles: TestProfilesControl? = nil
    ) {
        self.stall = stall
        self.onRetry = onRetry
        self.onRestore = onRestore
        self.onNuke = onNuke
        self.testProfiles = testProfiles
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

            // COPY BEGIN fa05dc81 [HUMAN REVIEWED, UNVERIFIED]
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

            // COPY BEGIN c1d22f7a [HUMAN REVIEWED, UNVERIFIED]
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

            #if DEBUG
                if let testProfiles {
                    Button {
                        choosingTestProfile = true
                    } label: {
                        // COPY BEGIN 33f3faee [NEEDS HUMAN REVIEW]
                        Text("Are you running a testing server?", bundle: .module)
                        // COPY END 33f3faee
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .sheet(isPresented: $choosingTestProfile) {
                        NavigationStack {
                            TestProfilesView(control: testProfiles)
                        }
                        .themed(palette.accent)
                    }
                }
            #endif

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
        case .accountUnreadable, .accountOffline: true
        case .keychainUnreadable: false
        }
    }

    // COPY BEGIN 4f8229af [HUMAN REVIEWED, UNVERIFIED]
    private var headline: Text {
        switch stall {
        case .accountUnreadable:
            Text("Apple Account cannot be used", bundle: .module)
        case .accountOffline:
            Text("Could not reach iCloud", bundle: .module)
        case .keychainUnreadable:
            Text("Keychain would not answer", bundle: .module)
        }
    }
    // COPY END 4f8229af

    // COPY BEGIN 682b13fe [HUMAN REVIEWED, UNVERIFIED]
    private var detail: Text {
        switch stall {
        case .accountUnreadable:
            Text(
                "iCloud is unreadable.",
                bundle: .module)
        case .accountOffline:
            Text(
                "iCloud is offline. Check your settings and return here.",
                bundle: .module)
        case .keychainUnreadable:
            Text(
                "The Keychain is unreadable. Try locking and unlocking your device.",
                bundle: .module)
        }
    }
    // COPY END 682b13fe
}

#if DEBUG
    #Preview("Stalled — iCloud is offline") {
        RegistrationStalledView(
            stall: .accountOffline, onRetry: {}, onRestore: {}, onNuke: {})
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
