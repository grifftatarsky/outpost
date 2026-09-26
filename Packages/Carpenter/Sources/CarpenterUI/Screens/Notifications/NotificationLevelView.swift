import CarpenterKit
import SwiftUI

public struct NotificationLevelView: View {
    @Environment(\.palette) private var palette

    @Binding private var level: NotificationLevel
    private let room: String?
    private let followingDefault: Bool
    private let receipts: RoomReceiptChoice?
    private let notGone: RoomNotGoneChoice?

    public init(
        level: Binding<NotificationLevel>, room: String? = nil, followingDefault: Bool = false,
        receipts: RoomReceiptChoice? = nil, notGone: RoomNotGoneChoice? = nil
    ) {
        _level = level
        self.room = room
        self.followingDefault = followingDefault
        self.receipts = receipts
        self.notGone = notGone
    }

    public var body: some View {
        List {
            // COPY BEGIN e504981b [NEEDS HUMAN REVIEW]
            if room == nil {
                SettingsHeaderCard(
                    icon: "bell.badge.fill",
                    title: Text("Notifications", bundle: .module),
                    paragraph: Text(
                        "Choose how much a banner shows before the phone is unlocked. If you have not allowed notifications, nothing announces itself; messages still arrive every time you open the app.",
                        bundle: .module))
            }
            // COPY END e504981b

            Section {
                ForEach(NotificationLevel.allCases, id: \.self) { rung in
                    ChoiceRow(
                        title: Text(rung.title, bundle: .module),
                        detail: Text(rung.detail, bundle: .module),
                        isSelected: rung == level,
                        action: { level = rung }
                    ) {
                        sample(rung)
                    }
                }
            } header: {
                // COPY BEGIN fe4e679a [NEEDS HUMAN REVIEW]
                if let room {
                    Text("Notifications from \(room)", bundle: .module)
                        .textCase(nil)
                        .font(CarpenterFont.footnote)
                }
                // COPY END fe4e679a
            } footer: {
                caveat
            }
            .groupedRowSurface()

            readReceipts

            notGoneSection
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        // COPY BEGIN b9a3b43b [NEEDS HUMAN REVIEW]
        .navigationTitle(
            room.map { Text(verbatim: $0) } ?? Text("Notifications", bundle: .module))
        // COPY END b9a3b43b
        .toolbarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var readReceipts: some View {
        if let receipts {
            Section {
                ForEach(RoomReceiptChoice.Answer.allCases, id: \.self) { answer in
                    ChoiceRow(
                        title: title(of: answer),
                        detail: detail(of: answer),
                        isSelected: answer == receipts.answer,
                        action: { Task { await receipts.onChange(answer) } })
                }
            } header: {
                // COPY BEGIN 86ad5b92 [NEEDS HUMAN REVIEW]
                Text("Read receipts here", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Reporting is off everywhere until you ask for it. This room can differ from the rest.",
                    bundle: .module)
                // COPY END 86ad5b92
            }
            .groupedRowSurface()
        }
    }

    @ViewBuilder
    private var notGoneSection: some View {
        if let notGone {
            // COPY BEGIN c102116d [NEEDS HUMAN REVIEW]
            Section {
                NavigationLink {
                    NotGoneWaitView(choice: notGone)
                } label: {
                    SettingsRow(
                        icon: "info.circle.fill",
                        title: Text("Say a message has not gone", bundle: .module),
                        detail: notGone.wait.days.map {
                            Text("After ^[\($0) day](inflect: true)", bundle: .module)
                        } ?? Text("Only when newer ones arrive", bundle: .module))
                }
            } header: {
                Text("Messages that have not gone", bundle: .module).sectionHeading()
            } footer: {
                Text(
                    "Waiting for somebody to open the app is ordinary. This is when it stops being.",
                    bundle: .module)
            }
            .groupedRowSurface()
            // COPY END c102116d
        }
    }

    // COPY BEGIN f1d0e16e [NEEDS HUMAN REVIEW]
    private func title(of answer: RoomReceiptChoice.Answer) -> Text {
        switch answer {
        case .followEverywhere: Text("Follow my usual answer", bundle: .module)
        case .on: Text("Report in this room", bundle: .module)
        case .off: Text("Never report here", bundle: .module)
        }
    }
    // COPY END f1d0e16e

    // COPY BEGIN 8a55d791 [NEEDS HUMAN REVIEW]
    private func detail(of answer: RoomReceiptChoice.Answer) -> Text {
        switch answer {
        case .followEverywhere:
            receipts?.everywhere == true
                ? Text("You report, so you report here too.", bundle: .module)
                : Text("You do not report, so nothing is sent here either.", bundle: .module)
        case .on:
            Text("People here see when your device showed their message.", bundle: .module)
        case .off:
            Text("People here are told your marks will not change.", bundle: .module)
        }
    }
    // COPY END 8a55d791

    private func sample(_ rung: NotificationLevel) -> some View {
        // COPY BEGIN aa223603 [NEEDS HUMAN REVIEW]
        let copy = MessageNotification.of(
            room: RoomID(), roomName: "Hangar 7", author: "Alice", body: "are you coming",
            level: rung)
        // COPY END aa223603

        return VStack(alignment: .leading, spacing: 2) {
            Text(copy.title).font(CarpenterFont.micro.weight(.semibold))
            if !copy.subtitle.isEmpty { Text(copy.subtitle).font(CarpenterFont.micro) }
            if !copy.body.isEmpty {
                Text(copy.body).font(CarpenterFont.micro).foregroundStyle(palette.secondaryText)
            }
        }
        .foregroundStyle(palette.primaryText)
        .frame(maxWidth: 190, alignment: .leading)
        .padding(10)
        .background(palette.quotedFill, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }

    // COPY BEGIN 93d56db0 [NEEDS HUMAN REVIEW]
    private var caveat: some View {
        Text(
            """
            The banner is put together on this device after it decrypts the message, so nothing \
            readable crosses the network. But the finished banner goes into the operating system's \
            notification store, and this app cannot reach in and remove it. Choosing less is the \
            only way to keep something out of that store. A photo or a clip is announced by its \
            caption, or as "📷 Photo" or "🎬 Video" when it has none; the picture itself never \
            goes into a banner.
            """,
            bundle: .module
        )
        .font(CarpenterFont.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }
    // COPY END 93d56db0
}

extension NotificationLevel {
    // COPY BEGIN 189c078d [NEEDS HUMAN REVIEW]
    public var shortTitle: LocalizedStringKey {
        switch self {
        case .everything: "Everything"
        case .whoAndWhere: "Room and sender"
        case .whereOnly: "Room only"
        case .nothing: "Arrival only"
        }
    }
    // COPY END 189c078d

    // COPY BEGIN abf72505 [NEEDS HUMAN REVIEW]
    public var title: LocalizedStringKey {
        switch self {
        case .everything: "Room, sender and message"
        case .whoAndWhere: "Room and sender"
        case .whereOnly: "Room only"
        case .nothing: "That a message arrived"
        }
    }
    // COPY END abf72505

    // COPY BEGIN dbffb7ba [NEEDS HUMAN REVIEW]
    public var detail: LocalizedStringKey {
        switch self {
        case .everything: "Anyone who can see your lock screen can read what was said."
        case .whoAndWhere: "They see who is talking to you, and where, but not what was said."
        case .whereOnly: "They see which conversation is moving, and nothing about who."
        case .nothing: "They see only that the app has something for you."
        }
    }
    // COPY END dbffb7ba
}

public struct RoomReceiptChoice: Sendable {
    public enum Answer: CaseIterable, Hashable, Sendable {
        case followEverywhere, on, off
    }

    public let answer: Answer
    public let everywhere: Bool
    public let onChange: @Sendable (Answer) async -> Void

    public init(
        answer: Answer, everywhere: Bool, onChange: @escaping @Sendable (Answer) async -> Void
    ) {
        self.answer = answer
        self.everywhere = everywhere
        self.onChange = onChange
    }
}
