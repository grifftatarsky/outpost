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

            if settingsCanFixIt {
                OpenSettingsButton()
                    .font(CarpenterFont.button)
                    .quietActionButton()
            }

            // COPY BEGIN c1d22f7a [HUMAN REVIEWED, UNVERIFIED]
            if let onRestore, offersARecoveryKey {
                Button(action: onRestore) {
                    Text("I have a recovery key", bundle: .module)
                        .primaryAction()
                }
                .quietActionButton()
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
        case .signedOut, .restricted, .keychainUnreadable, .heldBySecurity: false
        }
    }

    private var settingsCanFixIt: Bool {
        switch stall {
        case .signedOut, .restricted: true
        case .accountUnreadable, .accountOffline, .keychainUnreadable, .heldBySecurity: false
        }
    }

    // COPY BEGIN 7f30cac5 [NEEDS HUMAN REVIEW]
    private var heldHeadline: Text {
        Text("iCloud hasn't trusted this device", bundle: .module)
    }

    private var heldDetail: Text {
        Text(
            "Your Apple Account's security settings, such as Advanced Data Protection, keep this device out of iCloud until your other devices trust it. It will set up here once they do.",
            bundle: .module)
    }
    // COPY END 7f30cac5

    // COPY BEGIN 4f8229af [NEEDS HUMAN REVIEW]
    private var headline: Text {
        switch stall {
        case .accountUnreadable:
            Text("iCloud did not answer", bundle: .module)
        case .accountOffline:
            Text("Could not reach iCloud", bundle: .module)
        case .signedOut:
            Text("Signed out of iCloud", bundle: .module)
        case .restricted:
            Text("iCloud is restricted on this device", bundle: .module)
        case .keychainUnreadable:
            Text("Keychain would not answer", bundle: .module)
        case .heldBySecurity:
            heldHeadline
        }
    }
    // COPY END 4f8229af

    // COPY BEGIN 682b13fe [NEEDS HUMAN REVIEW]
    private var detail: Text {
        switch stall {
        case .accountUnreadable:
            Text(
                "iCloud would not say whether this account already has a member, so nothing has been set up. This is often brief.",
                bundle: .module)
        case .accountOffline:
            Text(
                "This phone could not reach iCloud. Check that it is online, then check again.",
                bundle: .module)
        case .signedOut:
            Text(
                "Everything this app keeps lives in your own iCloud. Sign in at the top of the Settings app, then come back.",
                bundle: .module)
        case .restricted:
            Text(
                "Screen Time, or whoever manages this device, keeps this app out of iCloud. Change that in Settings, then come back.",
                bundle: .module)
        case .heldBySecurity:
            heldDetail
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

    #Preview("Stalled — iCloud hasn't trusted this device") {
        RegistrationStalledView(stall: .heldBySecurity, onRetry: {})
            .themed(.default)
            .preferredColorScheme(.light)
    }
#endif
