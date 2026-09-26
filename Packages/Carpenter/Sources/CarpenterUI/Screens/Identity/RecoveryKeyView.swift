import CarpenterKit
import SwiftUI

public struct RecoveryKeyView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let text: String
    private let fingerprint: String
    private let isFirstTime: Bool
    private let onSaved: () -> Void
    private let onSkip: (() -> Void)?

    @State private var confirming = false

    public init(
        text: String, fingerprint: String, isFirstTime: Bool,
        onSaved: @escaping () -> Void, onSkip: (() -> Void)? = nil
    ) {
        self.text = text
        self.fingerprint = fingerprint
        self.isFirstTime = isFirstTime
        self.onSaved = onSaved
        self.onSkip = onSkip
    }

    public var body: some View {
        List {
                // COPY BEGIN b4443225 [NEEDS HUMAN REVIEW]
                Section {
                    SettingsHeaderCard(
                        icon: "key.horizontal.fill",
                        title: Text("Your recovery key", bundle: .module),
                        paragraph: Text(
                            "Save this file in a safe place. This is the only way back into your account if all devices are lost.",
                            bundle: .module))
                }
                .groupedRowSurface()
                // COPY END b4443225

                // COPY BEGIN deee3b35 [NEEDS HUMAN REVIEW]
                Section {
                    VerificationPhrase(fingerprint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } header: {
                    Text("The Key", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "These six characters are your identifier, so your recovery key is distinct from all others. It holds your identity, but no history.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END deee3b35
            }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                // COPY BEGIN d46cf88c [NEEDS HUMAN REVIEW]
                ShareLink(
                    item: text,
                    preview: SharePreview(
                        Text("\(Branding.displayName) recovery key", bundle: .module))
                ) {
                    Text("Save key", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .simultaneousGesture(TapGesture().onEnded { onSaved() })
                // COPY END d46cf88c

                // COPY BEGIN d3255589 [NEEDS HUMAN REVIEW]
                if onSkip != nil {
                    Button { confirming = true } label: {
                        Text("Not now", bundle: .module)
                    }
                    .quietActionButton()
                }
                // COPY END d3255589
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background)
        // COPY BEGIN 62a19f8e [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Recovery Key", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(
            Text("Continue without your key?", bundle: .module),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                dismiss()
                onSkip?()
            } label: {
                Text("Continue without it", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("Save it first", bundle: .module)
            }
        } message: {
            Text(
                "You can save it later under You. Until you do, losing every device you own ends this account.",
                bundle: .module)
        // COPY END 62a19f8e
        }
    }
}

#if DEBUG
    #Preview("Recovery key") {
        NavigationStack {
            RecoveryKeyView(
                text: "OUTPOST RECOVERY KEY v1\n…", fingerprint: "K7M2QX", isFirstTime: true,
                onSaved: {}, onSkip: {})
        }
        .themed(.default)
    }
#endif

public struct RecoveryKeyRow {
    public let text: () -> String
    public let fingerprint: String
    public let savedAt: Date?
    public let onSaved: () -> Void

    public init(
        text: @escaping () -> String, fingerprint: String, savedAt: Date?,
        onSaved: @escaping () -> Void
    ) {
        self.text = text
        self.fingerprint = fingerprint
        self.savedAt = savedAt
        self.onSaved = onSaved
    }
}
