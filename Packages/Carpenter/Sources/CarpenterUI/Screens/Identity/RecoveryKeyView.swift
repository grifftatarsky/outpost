import CarpenterKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
    import LinkPresentation
    import UIKit
#endif

public struct RecoveryKeyView: View {
    @Environment(\.palette) private var palette

    private let text: String
    private let fingerprint: String
    private let onSaved: () async -> Void

    @State private var shared = false
    @State private var confirming = false
    @State private var exporting = false

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
                // COPY BEGIN d46cf88c [NEEDS HUMAN REVIEW]
                Button(action: save) {
                    Text("Save key", bundle: .module).primaryAction()
                }
                .prominentActionButton()
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
        #if os(macOS)
            .fileExporter(
                isPresented: $exporting, item: text, contentTypes: [.plainText], defaultFilename: Self.title
            ) { result in
                if case .success = result { shared = true }
            }
        #endif
    }

    // COPY BEGIN 40676436 [NEEDS HUMAN REVIEW]
    private static var title: String {
        String(localized: "\(Branding.displayName) recovery key", bundle: .module)
    }
    // COPY END 40676436

    private func save() {
        #if os(iOS)
            KeySharing.present(text, titled: Self.title) { completed in
                if completed { shared = true }
            }
        #else
            exporting = true
        #endif
    }
}

#if os(iOS)
    @MainActor
    enum KeySharing {
        static func present(_ text: String, titled title: String, finished: @escaping @MainActor (Bool) -> Void) {
            guard
                let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                var top = scene.keyWindow?.rootViewController
            else {
                finished(false)
                return
            }
            while let presented = top.presentedViewController { top = presented }
            let sheet = UIActivityViewController(
                activityItems: [KeyItem(text: text, title: title)], applicationActivities: nil)
            sheet.completionWithItemsHandler = { _, completed, _, _ in
                Task { @MainActor in finished(completed) }
            }
            sheet.popoverPresentationController?.sourceView = top.view
            top.present(sheet, animated: true)
        }
    }

    private final class KeyItem: NSObject, UIActivityItemSource {
        let text: String
        let title: String

        init(text: String, title: String) {
            self.text = text
            self.title = title
        }

        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }

        func activityViewController(
            _ controller: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?
        ) -> Any? { text }

        func activityViewController(
            _ controller: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?
        ) -> String { title }

        func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            return metadata
        }
    }
#endif

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
        enum Stage { case shared, confirming }

        init(text: String, fingerprint: String, at stage: Stage, onSaved: @escaping () async -> Void) {
            self.init(text: text, fingerprint: fingerprint, onSaved: onSaved)
            _shared = State(initialValue: true)
            _confirming = State(initialValue: stage == .confirming)
        }
    }
#endif
