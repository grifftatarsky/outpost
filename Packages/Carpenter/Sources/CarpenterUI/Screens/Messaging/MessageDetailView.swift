import CarpenterKit
import SwiftUI

public struct MessageDetailView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let message: Message
    private let actions: MessageActions
    private let readers: [ReadBy]
    private let isSolo: Bool

    @State private var confirmingHide = false
    @State private var explainingHide = false
    @State private var problem: String?
    @State private var reporting = false

    public init(
        message: Message, actions: MessageActions, readers: [ReadBy] = [], isSolo: Bool = false
    ) {
        self.message = message
        self.actions = actions
        self.readers = readers
        self.isSolo = isSolo
    }

    public var body: some View {
        SettingsPage {
            Section {
                Text(verbatim: message.body)
                    .font(CarpenterFont.bubble)
                    .foregroundStyle(
                        message.isWithdrawn ? palette.secondaryText : palette.primaryText)
                    .italic(message.isWithdrawn)
            } header: {
                Text("Message", bundle: .module).sectionHeading()
            }
            .groupedRowSurface()

            delivery
            readBy
            history
            acts
        }
        .listSurfaceHidden()
        .pageBackground()
        .navigationTitle(Text("Details", bundle: .module))
        .toolbarTitleDisplayMode(.inline)
        .alert(
            Text("Hide this message?", bundle: .module),
            isPresented: $confirmingHide
        ) {
            Button(role: .destructive) {
                Task { await actions.hide(message.id) }
                dismiss()
            } label: {
                Text("Hide it", bundle: .module)
            }
            Button(role: .cancel) { confirmingHide = false } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text(
                "It stops being drawn on your devices. Nobody else is affected and nothing is erased.",
                bundle: .module)
        }
        .alert(
            Text("That did not go through", bundle: .module),
            isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
        ) {
            Button { problem = nil } label: { Text("OK", bundle: .module) }
        } message: {
            Text(verbatim: problem ?? "")
        }
        .sizedSheet(isPresented: $reporting) {
            ReportView(item: ViewedItem(message))
        }
    }

    private var delivery: some View {
        Section {
            row(Text("Sent", bundle: .module), value: message.sentAt.formatted(date: .abbreviated, time: .shortened))
            if let editedAt = message.editedAt {
                row(Text("Edited", bundle: .module), value: editedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let displayedAt = message.delivery.displayedAt {
                row(Text("Shown on their screen", bundle: .module), value: displayedAt.formatted(date: .abbreviated, time: .shortened))
            }
        } header: {
            Text("Delivery", bundle: .module).sectionHeading()
        } footer: {
            if message.isMine, message.delivery.displayedAt == nil {
                Text(
                    "A read mark appears only if somebody's device reports one. Its absence is not evidence either way.",
                    bundle: .module)
            }
        }
        .groupedRowSurface()
    }

    @ViewBuilder
    private var readBy: some View {
        if message.isMine, !readers.isEmpty {
            let shown = readers.filter(\.report.wasDisplayed)
            let quiet = readers.filter { $0.report == .doesNotReport }

            Section {
                ForEach(readers) { reader in
                    SettingsRow(
                        icon: reader.report.wasDisplayed
                            ? "checkmark.circle.fill" : "circle.dotted",
                        title: Text(verbatim: reader.member.displayName),
                        detail: detail(of: reader.report))
                }
            } header: {
                isSolo
                    ? Text("Read", bundle: .module).sectionHeading()
                    : Text("Read by", bundle: .module).sectionHeading()
            } footer: {
                if shown.isEmpty && quiet.count == readers.count {
                    Text(
                        "Everybody here has read receipts off, which is the default. These marks will never change, and that is the answer rather than a wait.",
                        bundle: .module)
                } else {
                    Text(
                        "A time is when a device displayed this message, never that somebody read it.",
                        bundle: .module)
                }
            }
            .groupedRowSurface()
        }
    }

    private func detail(of report: ReadReport) -> Text {
        switch report {
        case .displayed(let at):
            Text(verbatim: at.formatted(date: .omitted, time: .shortened))
        case .nothingYet:
            Text("Nothing yet", bundle: .module)
        case .doesNotReport:
            Text("Does not report", bundle: .module)
        }
    }

    @ViewBuilder
    private var history: some View {
        if message.revisions.count > 1 {
            Section {
                ForEach(Array(message.revisions.enumerated()), id: \.offset) { index, revision in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: revision.text)
                            .font(CarpenterFont.footnote)
                            .foregroundStyle(
                                index == message.revisions.count - 1
                                    ? palette.primaryText : palette.secondaryText)
                        Text(verbatim: revision.at.formatted(date: .omitted, time: .shortened))
                            .font(CarpenterFont.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Every wording", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Each edit is its own entry in the room, so everybody can read what changed.",
                    bundle: .module)
            }
            .groupedRowSurface()
        }
    }

    private var acts: some View {
        Section {
            if !message.isMine {
                Button {
                    reporting = true
                } label: {
                    Label {
                        Text("Report", bundle: .module)
                    } icon: {
                        Image(systemName: "flag").foregroundStyle(palette.accentColor)
                    }
                }
            }

            Button(role: .destructive) {
                confirmingHide = true
            } label: {
                Label {
                    Text("Hide for me", bundle: .module)
                } icon: {
                    Image(systemName: "eye.slash").foregroundStyle(palette.destructive)
                }
            }
            .tint(palette.destructive)

            Button {
                explainingHide.toggle()
            } label: {
                Label {
                    Text("What hiding actually does", bundle: .module)
                } icon: {
                    Image(systemName: explainingHide ? "chevron.down" : "chevron.right")
                        .foregroundStyle(palette.accentColor)
                }
            }

            if explainingHide {
                Text(
                    """
                    Hiding is yours alone. The message stops being drawn on your devices and stays \
                    exactly where it was for everybody else — it is still in your log too, still \
                    synced, and you can put it back.

                    It is not the same as withdrawing. Withdrawing is something only the person who \
                    wrote a message can do, within two minutes, and it takes the words back from \
                    everybody's view. Even then nothing is erased from anybody's device: the entry \
                    stays and each copy draws a placeholder instead. Nothing in this app reaches \
                    into somebody else's copy of a conversation.
                    """,
                    bundle: .module
                )
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.secondaryText)
            }
        } header: {
            Text("This message", bundle: .module).sectionHeading()
        }
        .groupedRowSurface()
    }

    private func row(_ label: Text, value: String) -> some View {
        HStack {
            label
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.primaryText)
            Spacer()
            Text(verbatim: value)
                .font(CarpenterFont.rowDetail)
                .foregroundStyle(palette.secondaryText)
        }
    }
}

public struct MessageActions: Sendable {
    public var edit: @Sendable (MessageID, String) async -> String?
    public var withdraw: @Sendable (MessageID) async -> String?
    public var hide: @Sendable (MessageID) async -> Void
    public var editableFor: @MainActor @Sendable (MessageID) -> TimeInterval?
    public var withdrawableFor: @MainActor @Sendable (MessageID) -> TimeInterval?
    public var react: @Sendable (MessageID, String?) async -> Void
    public var block: (@Sendable (ParticipantID) async -> Void)?
    public var member: @MainActor @Sendable (ParticipantID) -> Member?
    public var readBy: @MainActor @Sendable (MessageID, RoomID) -> [ReadBy]

    public init(
        edit: @escaping @Sendable (MessageID, String) async -> String? = { _, _ in nil },
        withdraw: @escaping @Sendable (MessageID) async -> String? = { _ in nil },
        hide: @escaping @Sendable (MessageID) async -> Void = { _ in },
        editableFor: @escaping @MainActor @Sendable (MessageID) -> TimeInterval? = { _ in nil },
        withdrawableFor: @escaping @MainActor @Sendable (MessageID) -> TimeInterval? = { _ in nil },
        react: @escaping @Sendable (MessageID, String?) async -> Void = { _, _ in },
        block: (@Sendable (ParticipantID) async -> Void)? = nil,
        member: @escaping @MainActor @Sendable (ParticipantID) -> Member? = { _ in nil },
        readBy: @escaping @MainActor @Sendable (MessageID, RoomID) -> [ReadBy] = { _, _ in [] }
    ) {
        self.edit = edit
        self.withdraw = withdraw
        self.hide = hide
        self.editableFor = editableFor
        self.withdrawableFor = withdrawableFor
        self.react = react
        self.block = block
        self.member = member
        self.readBy = readBy
    }
}

#if DEBUG
    #Preview("Message details") {
        NavigationStack {
            MessageDetailView(
                message: Message(
                    id: MessageID(entry: EntryHash(rawValue: Data([1]))),
                    author: Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                    body: "third go",
                    sentAt: .now.addingTimeInterval(-400),
                    isMine: true,
                    editedAt: .now.addingTimeInterval(-60),
                    revisions: [
                        Revision(text: "frist", at: .now.addingTimeInterval(-400)),
                        Revision(text: "first", at: .now.addingTimeInterval(-200)),
                        Revision(text: "third go", at: .now.addingTimeInterval(-60)),
                    ]),
                actions: MessageActions())
        }
        .themed(.default)
    }
#endif
