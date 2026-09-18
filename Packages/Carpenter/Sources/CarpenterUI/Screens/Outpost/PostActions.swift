import CarpenterKit
import SwiftUI

public struct PostActions: Sendable {
    public var edit: @Sendable (PostID, String) async -> String?
    public var withdraw: @Sendable (PostID) async -> String?
    public var editableFor: @MainActor @Sendable (PostID) -> TimeInterval?
    public var withdrawableFor: @MainActor @Sendable (PostID) -> TimeInterval?

    public init(
        edit: @escaping @Sendable (PostID, String) async -> String? = { _, _ in nil },
        withdraw: @escaping @Sendable (PostID) async -> String? = { _ in nil },
        editableFor: @escaping @MainActor @Sendable (PostID) -> TimeInterval? = { _ in nil },
        withdrawableFor: @escaping @MainActor @Sendable (PostID) -> TimeInterval? = { _ in nil }
    ) {
        self.edit = edit
        self.withdraw = withdraw
        self.editableFor = editableFor
        self.withdrawableFor = withdrawableFor
    }
}

enum PostKind {
    case post
    case comment
}

extension View {
    func postActions(
        _ item: ViewedItem, isWithdrawn: Bool, kind: PostKind, actions: PostActions?
    ) -> some View {
        modifier(
            PostActionsModifier(
                item: item, isWithdrawn: isWithdrawn, kind: kind, actions: actions))
    }
}

private struct PostActionsModifier: ViewModifier {
    @Environment(\.palette) private var palette

    let item: ViewedItem
    let isWithdrawn: Bool
    let kind: PostKind
    let actions: PostActions?

    @State private var editing = false
    @State private var withdrawing = false
    @State private var reporting = false
    @State private var problem: String?
    @State private var editDetent: PresentationDetent = .large

    private var id: PostID { PostID(entry: item.entry) }
    private var isMine: Bool { item.isMine }

    private var mayEdit: Bool {
        guard let actions, isMine, !isWithdrawn else { return false }
        return actions.editableFor(id) != nil
    }

    private var mayWithdraw: Bool {
        guard let actions, isMine, !isWithdrawn else { return false }
        return actions.withdrawableFor(id) != nil
    }

    private var mayReport: Bool { !isMine && !isWithdrawn }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if mayEdit {
                    Button { editing = true } label: {
                        Label {
                            Text("Edit", bundle: .module)
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                }
                if mayWithdraw {
                    Button(role: .destructive) { withdrawing = true } label: {
                        Label {
                            Text("Withdraw", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                    .tint(palette.destructive)
                }
                if mayReport {
                    Button(role: .destructive) { reporting = true } label: {
                        Label {
                            Text("Report", bundle: .module)
                        } icon: {
                            Image(systemName: "exclamationmark.bubble")
                        }
                    }
                    .tint(palette.destructive)
                }
            }
            .sheet(isPresented: $reporting) {
                ReportView(item: item)
            }
            .sheet(isPresented: $editing) {
                EditWordsView(
                    title: kind == .post
                        ? Text("Edit post", bundle: .module)
                        : Text("Edit comment", bundle: .module),
                    placeholder: kind == .post
                        ? Text("Your post", bundle: .module)
                        : Text("Your comment", bundle: .module),
                    current: item.words
                ) { text in
                    await actions?.edit(id, text)
                }
                .presentationDetents([.medium, .large], selection: $editDetent)
                .presentationDragIndicator(.visible)
            }
            .alert(
                kind == .post
                    ? Text("Withdraw this post?", bundle: .module)
                    : Text("Withdraw this comment?", bundle: .module),
                isPresented: $withdrawing
            ) {
                Button(role: .destructive) {
                    Task { problem = await actions?.withdraw(id) }
                } label: {
                    Text("Withdraw it", bundle: .module)
                }
                Button(role: .cancel) { withdrawing = false } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text(
                    "Everybody stops seeing the words. Nothing is erased from anybody's device — each copy shows that it was withdrawn.",
                    bundle: .module)
            }
            .alert(
                Text("That did not go through", bundle: .module),
                isPresented: Binding(
                    get: { problem != nil }, set: { if !$0 { problem = nil } })
            ) {
                Button { problem = nil } label: { Text("OK", bundle: .module) }
            } message: {
                Text(verbatim: problem ?? "")
            }
    }
}
