import CarpenterKit
import SwiftUI

public struct RecoveryKeyView: View {
    @Environment(\.palette) private var palette

    private let text: String
    private let fingerprint: String
    private let onSaved: () async -> Void

    @State private var shared = false
    @State private var confirming = false

    public init(text: String, fingerprint: String, onSaved: @escaping () async -> Void) {
        self.text = text
        self.fingerprint = fingerprint
        self.onSaved = onSaved
    }

    public var body: some View {
        List {
                // COPY BEGIN b4443225 [NEEDS HUMAN REVIEW]
                Section {
                    SettingsHeaderCard(
                        icon: "key.horizontal.fill",
                        title: Text("Your recovery key", bundle: .module),
                        paragraph: Text(
                            "Save this file in a safe place. It's shown once, now, and none of your devices keep it. It's the only way back if you lose every device, and using it removes every other device.",
                            bundle: .module))
                }
                .groupedRowSurface()
                // COPY END b4443225

                // COPY BEGIN deee3b35 [HUMAN REVIEWED, UNVERIFIED]
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
                // COPY BEGIN d46cf88c [HUMAN REVIEWED, UNVERIFIED]
                ShareLink(
                    item: text,
                    preview: SharePreview(
                        Text("\(Branding.displayName) recovery key", bundle: .module))
                ) {
                    Text("Save key", bundle: .module).primaryAction()
                }
                .prominentActionButton()
                .simultaneousGesture(TapGesture().onEnded { shared = true })
                // COPY END d46cf88c

                // COPY BEGIN a0892d83 [NEEDS HUMAN REVIEW]
                Button { confirming = true } label: {
                    Text("I've saved it", bundle: .module).primaryAction()
                }
                .quietActionButton()
                .disabled(!shared)
                // COPY END a0892d83
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(palette.background)
        // COPY BEGIN 62a19f8e [NEEDS HUMAN REVIEW]
        .navigationTitle(Text("Recovery Key", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        // COPY END 62a19f8e
        // COPY BEGIN 74d78710 [NEEDS HUMAN REVIEW]
        .alert(
            Text("Is your key somewhere safe?", bundle: .module),
            isPresented: $confirming
        ) {
            Button(role: .cancel) {} label: {
                Text("Not yet", bundle: .module)
            }
            Button {
                Task { await onSaved() }
            } label: {
                Text("It's saved", bundle: .module)
            }
        } message: {
            Text(
                "Once you go on, this key can't be shown again, on this device or any other.",
                bundle: .module)
        }
        // COPY END 74d78710
        .interactiveDismissDisabled()
    }
}

#if DEBUG
    #Preview("Recovery key") {
        NavigationStack {
            RecoveryKeyView(text: "OUTPOST RECOVERY KEY v2\n…", fingerprint: "K7M2QX", onSaved: {})
        }
        .themed(.default)
    }
#endif

public struct RecoveryKeyRow {
    public let fingerprint: String
    public let savedAt: Date?

    public init(fingerprint: String, savedAt: Date?) {
        self.fingerprint = fingerprint
        self.savedAt = savedAt
    }
}

#if DEBUG
    extension RecoveryKeyView {
        init(text: String, fingerprint: String, confirmingAtStart: Bool, onSaved: @escaping () async -> Void) {
            self.init(text: text, fingerprint: fingerprint, onSaved: onSaved)
            _shared = State(initialValue: confirmingAtStart)
            _confirming = State(initialValue: confirmingAtStart)
        }
    }
#endif
