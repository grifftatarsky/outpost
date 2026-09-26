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
                            "This file is the only way back into this account if you lose every device you own. There is no password to reset and nobody to ask — not us, because we have nothing of yours to give back.",
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
                    Text("What is on it", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "These six characters are printed on the file, so you can tell it from anybody else's. It holds your keys and nothing else — no messages, and nothing anybody wrote to you.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END deee3b35

                Section {
                    // COPY BEGIN 4a9f85db [NEEDS HUMAN REVIEW]
                    Label {
                        Text("It makes you you again", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(palette.accentColor)
                    }
                    Label {
                        Text("It does not bring your conversations back", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.destructive)
                    }
                } header: {
                    Text("What it does", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "Your rooms come back because the people in them can address you again, and they send you what was said while you were gone. Anything nobody else still holds is gone.",
                        bundle: .module)
                    // COPY END 4a9f85db
                }
                .groupedRowSurface()

                // COPY BEGIN 5dcfbe43 [NEEDS HUMAN REVIEW]
                Section {
                } footer: {
                    Text(
                        "Anybody who has this file can become you, and there is no way to undo that. Keep it where you keep passwords — not in the photos on the phone it is meant to replace.",
                        bundle: .module)
                        .foregroundStyle(palette.destructive)
                }
                .groupedRowSurface()
                // COPY END 5dcfbe43
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
                    Text("Save my key", bundle: .module).primaryAction()
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
        .navigationTitle(Text("Recovery key", bundle: .module))
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
