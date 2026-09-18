import CarpenterKit
import SwiftUI

public struct JoinPromptView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let greeting: RoomGreeting
    private let onOpen: () async -> Void

    @State private var opening = false

    public init(greeting: RoomGreeting, onOpen: @escaping () async -> Void) {
        self.greeting = greeting
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    heading
                    if !greeting.isDirect {
                        people
                        settings
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 12)
            }

            Button {
                Task {
                    opening = true
                    await onOpen()
                    opening = false
                    dismiss()
                }
            } label: {
                Text("Open \(greeting.name)", bundle: .module).primaryAction()
            }
            .prominentActionButton()
            .disabled(opening)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(palette.background)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: greeting.name)
                .font(CarpenterFont.largeTitle)
                .foregroundStyle(palette.primaryText)
                .heading()

            if greeting.isDirect {
                Text("Started a solo with you", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else if let inviter = greeting.invitedBy {
                Text("\(inviter.displayName) added you to this room", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else {
                Text("You are a member of this room", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("^[\(greeting.members.count) member](inflect: true)", bundle: .module)
                .sectionHeading()

            VStack(spacing: 10) {
                ForEach(greeting.members) { member in
                    PersonRow(
                        name: member.displayName,
                        initials: member.initials,
                        id: member.id,
                        detail: member.isPlaceholder
                            ? Text("Has not published a name", bundle: .module) : nil)
                        .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.contentSurface,
                in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))
        }
    }

    private static func asSentence(_ phrase: String) -> String {
        guard let first = phrase.first else { return phrase }
        return first.uppercased() + phrase.dropFirst()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How people get in", bundle: .module).sectionHeading()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock")
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(verbatim: Self.asSentence(NoticeCopy.describe(greeting.access)))
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
    #Preview("Brought into a room") {
        JoinPromptView(
            greeting: RoomGreeting(
                id: RoomID(),
                name: "Hangar 7",
                invitedBy: Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                members: [
                    Member(id: ParticipantID(rawValue: Data([1])), displayName: "Ada"),
                    Member(id: ParticipantID(rawValue: Data([2])), displayName: "Bo"),
                    Member.placeholder(ParticipantID(rawValue: Data([0xC0, 0xC2]))),
                ],
                access: .atLeast(2)),
            onOpen: {}
        )
        .themed(.default)
    }
#endif
