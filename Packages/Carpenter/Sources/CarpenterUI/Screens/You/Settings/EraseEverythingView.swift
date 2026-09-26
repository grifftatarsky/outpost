import CarpenterKit
import SwiftUI

public struct EraseEverythingView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let onErase: () async -> Void

    @State private var erasing = false
    @State private var confirming = false

    public init(onErase: @escaping () async -> Void) {
        self.onErase = onErase
    }

    public var body: some View {
        NavigationStack {
            List {
                // COPY BEGIN 3f677afd [NEEDS HUMAN REVIEW]
                Section {
                    fact(
                        "trash",
                        Text("Your member identity and every room key are erased from this device and from iCloud Keychain.", bundle: .module))
                    fact(
                        "icloud",
                        Text("Every feed, every packet and every photo in flight that this Apple Account holds in iCloud is deleted.", bundle: .module))
                    fact(
                        "internaldrive",
                        Text("Your history on this device goes with it, photos and clips included.", bundle: .module))
                    fact(
                        "iphone.gen3",
                        Text("Your other devices lose the identity too, the next time they check. They cannot get it back.", bundle: .module))
                } header: {
                    Text("What is erased", bundle: .module).sectionHeading()
                }
                .groupedRowSurface()
                // COPY END 3f677afd

                // COPY BEGIN 96d3cb2b [NEEDS HUMAN REVIEW]
                Section {
                    fact(
                        "person.2",
                        Text("Nothing is removed from anybody else's device. What you sent is already theirs, and stays theirs.", bundle: .module))
                    fact(
                        "bell.slash",
                        Text("Rooms you were in are not told. To them, you simply stop arriving.", bundle: .module))
                    fact(
                        "arrow.uturn.backward.circle",
                        Text("There is no undo and nobody can restore this for you, because nobody else holds your keys.", bundle: .module))
                } header: {
                    Text("What is not", bundle: .module).sectionHeading()
                } footer: {
                    Text(
                        "This removes your access to your own history. It does not, and cannot, remove your history from the people you shared it with.",
                        bundle: .module)
                }
                .groupedRowSurface()
                // COPY END 96d3cb2b

                Section {
                    Button {
                        confirming = true
                    } label: {
                        // COPY BEGIN d6cb6319 [NEEDS HUMAN REVIEW]
                        Label {
                            Text("Erase everything", bundle: .module).primaryAction()
                        } icon: {
                            Image("NukeMark", bundle: .module)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundStyle(.white)
                        }
                        // COPY END d6cb6319
                    }
                    .destructiveActionButton()
                    .disabled(erasing)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            // COPY BEGIN a12e6eb2 [NEEDS HUMAN REVIEW]
            .alert(
                Text("Erase everything?", bundle: .module), isPresented: $confirming
            ) {
                Button(role: .destructive) {
                    Task {
                        erasing = true
                        await onErase()
                        erasing = false
                        dismiss()
                    }
                } label: {
                    Text("Erase everything", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            } message: {
                Text(
                    "Your identity goes from this device, from your iCloud Keychain, and from every other device you have. There is no undo and nobody can restore this for you.",
                    bundle: .module)
            // COPY END a12e6eb2
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            // COPY BEGIN bd94bb9e [NEEDS HUMAN REVIEW]
            .navigationTitle(Text("Erase everything", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(erasing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .disabled(erasing)
                }
            }
            // COPY END bd94bb9e
        }
    }

    private func fact(_ symbol: String, _ text: Text) -> some View {
        Label {
            text
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.primaryText)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(palette.destructive)
        }
    }
}

#if DEBUG
    #Preview("Erase everything") {
        EraseEverythingView(onErase: {})
            .themed(.default)
    }
#endif
