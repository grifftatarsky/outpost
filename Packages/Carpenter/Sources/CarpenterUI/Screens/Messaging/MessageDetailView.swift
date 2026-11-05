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

    private let formatter = RelativeTimestampFormatter()

    public init(
        message: Message, actions: MessageActions, readers: [ReadBy] = [], isSolo: Bool = false
    ) {
        self.message = message
        self.actions = actions
        self.readers = readers
        self.isSolo = isSolo
    }

    public var body: some View {
        List {
            // COPY BEGIN 4d6bfd04 [NEEDS HUMAN REVIEW]
            Section {
                Text(verbatim: message.body)
                    .font(CarpenterFont.bubble)
                    .foregroundStyle(
                        message.isWithdrawn ? palette.secondaryText : palette.primaryText)
                    .italic(message.isWithdrawn)
            } header: {
                Text("Message", bundle: .module).sectionHeading()
            } footer: {
                sentAndEdited
            }
            .groupedRowSurface()
            // COPY END 4d6bfd04

            delivery
            history
            acts
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN c5a62b92 [NEEDS HUMAN REVIEW]
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
        // COPY END c5a62b92
        .sheet(isPresented: $reporting) {
            ReportView(item: ViewedItem(message))
        }
    }

    // COPY BEGIN 7b083304 [NEEDS HUMAN REVIEW]
    private var sentAndEdited: Text {
        let sent = Text("Sent \(formatter.exact(message.sentAt))", bundle: .module)
        guard let editedAt = message.editedAt else { return sent }
        return Text("\(sent) · Edited \(formatter.exact(editedAt))", bundle: .module)
    }
    // COPY END 7b083304

    @ViewBuilder
    private var delivery: some View {
        if message.isMine, !readers.isEmpty {
            Section {
                ForEach(readers) { reader in
                    RecipientRow(reader: reader, formatter: formatter)
                }
            } header: {
                // COPY BEGIN 3e540edb [NEEDS HUMAN REVIEW]
                Text("Delivery", bundle: .module).sectionHeading()
            } footer: {
                if readers.allSatisfy({ $0.report == .doesNotReport }) {
                    isSolo
                        ? Text(
                            "Collected is when iCloud stored their phone's signed receipt for this message. They do not report when a message is shown, which is the default.",
                            bundle: .module)
                        : Text(
                            "Collected is when iCloud stored each phone's signed receipt for this message. Nobody here reports when a message is shown, which is the default.",
                            bundle: .module)
                } else {
                    Text(
                        "Collected is when iCloud stored their phone's signed receipt for this message. Shown is when a phone that reports it displayed the message, never that somebody read it.",
                        bundle: .module)
                }
                // COPY END 3e540edb
            }
            .groupedRowSurface()
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
                // COPY BEGIN 8605b99e [NEEDS HUMAN REVIEW]
                Text("Every wording", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Each edit is its own entry in the room, so everybody can read what changed.",
                    bundle: .module)
                // COPY END 8605b99e
            }
            .groupedRowSurface()
        }
    }

    private var acts: some View {
        Section {
            // COPY BEGIN 1dadf3f6 [NEEDS HUMAN REVIEW]
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
            // COPY END 1dadf3f6

            // COPY BEGIN 0c0c9dd1 [NEEDS HUMAN REVIEW]
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
            // COPY END 0c0c9dd1

            // COPY BEGIN 2e314aa0 [NEEDS HUMAN REVIEW]
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
            // COPY END 2e314aa0

            if explainingHide {
                // COPY BEGIN 9de72c36 [NEEDS HUMAN REVIEW]
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
                // COPY END 9de72c36
                .font(CarpenterFont.caption)
                .foregroundStyle(palette.secondaryText)
            }
        } header: {
            // COPY BEGIN dd2f7a19 [NEEDS HUMAN REVIEW]
            Text("This message", bundle: .module).sectionHeading()
            // COPY END dd2f7a19
        }
        .groupedRowSurface()
    }
}

struct RecipientRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var glyph: CGFloat = 13

    let reader: ReadBy
    let formatter: RelativeTimestampFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                PersonAvatarView(member: reader.member, diameter: CarpenterMetrics.messageAvatar)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: reader.member.displayName)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                Label {
                    collection.foregroundStyle(palette.secondaryText)
                } icon: {
                    DeliveryGlyph(.plane(filled: reader.collection.collectedAt != nil), size: glyph)
                        .accessibilityHidden(true)
                }
                if reader.report != .doesNotReport {
                    Label {
                        display.foregroundStyle(palette.secondaryText)
                    } icon: {
                        DeliveryGlyph(.eye(filled: reader.report.wasDisplayed), size: glyph)
                            .accessibilityHidden(true)
                    }
                }
            }
            .font(CarpenterFont.footnote)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // COPY BEGIN 52d2b508 [NEEDS HUMAN REVIEW]
    private var collection: Text {
        switch reader.collection {
        case .collected(let at):
            Text("Collected \(formatter.exact(at))", bundle: .module)
        case .noReceipt:
            Text("No receipt yet", bundle: .module)
        case .notCollected:
            Text("Not collected in ^[\(NotGone.takenBackAfterDays) day](inflect: true)", bundle: .module)
        }
    }

    private var display: Text {
        switch reader.report {
        case .displayed(let at):
            Text("Shown \(formatter.exact(at))", bundle: .module)
        case .nothingYet, .doesNotReport:
            Text("Not shown yet", bundle: .module)
        }
    }
    // COPY END 52d2b508
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
