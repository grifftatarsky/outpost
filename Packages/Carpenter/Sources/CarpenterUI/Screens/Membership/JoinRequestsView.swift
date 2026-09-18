import CarpenterKit
import SwiftUI

public struct PendingJoin: Identifiable, Hashable, Sendable {
    public let id: ParticipantID
    public let joiner: Member
    public let inviter: Member
    public let phrase: String
    public let expiresAt: Date
    public let refusedBy: [Member]

    public var isIndefinite: Bool { expiresAt >= .distantFuture }

    public let isAlreadyIn: Bool

    public init(
        id: ParticipantID,
        joiner: Member,
        inviter: Member,
        phrase: String,
        expiresAt: Date,
        isAlreadyIn: Bool = false,
        refusedBy: [Member] = []
    ) {
        self.id = id
        self.joiner = joiner
        self.inviter = inviter
        self.phrase = phrase
        self.expiresAt = expiresAt
        self.refusedBy = refusedBy
        self.isAlreadyIn = isAlreadyIn
    }
}

public struct JoinRequestsView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let roomName: String
    private let joins: () -> [PendingJoin]
    private let onDecide: (PendingJoin, Bool) async -> Void
    @State private var decisions = 0
    @State private var decided = false

    public init(
        roomName: String,
        joins: @escaping () -> [PendingJoin],
        onDecide: @escaping (PendingJoin, Bool) async -> Void
    ) {
        self.roomName = roomName
        self.joins = joins
        self.onDecide = onDecide
    }

    public var body: some View {
        NavigationStack {
            Group {
                if joins().isEmpty {
                    ContentUnavailableView {
                        Text("Nothing to check", bundle: .module)
                    } description: {
                        Text(
                            "Joins you have not answered, and people who took your invitation, appear here.",
                            bundle: .module)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(joins()) { join in
                                card(join)
                            }
                        }
                        .padding(.horizontal, CarpenterMetrics.screenMargin)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(palette.background)
            .navigationTitle(roomName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close", bundle: .module))
                        .barIconLargeContent(Text("Close", bundle: .module), systemImage: "xmark")
                }
            }
        }
        .haptic(.commit, trigger: decisions)
    }

    private func card(_ join: PendingJoin) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PersonAvatarView(member: join.joiner, diameter: CarpenterMetrics.roomAvatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(join.joiner.displayName)
                        .font(CarpenterFont.rowTitle)
                        .foregroundStyle(palette.primaryText)
                    join.isAlreadyIn
                        ? Text("Joined on your invitation", bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.secondaryText)
                        : Text("Invited by \(join.inviter.displayName)", bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.secondaryText)

                    if !join.isAlreadyIn, !join.isIndefinite {
                        Text(
                            "Runs out \(join.expiresAt.formatted(.relative(presentation: .named)))",
                            bundle: .module)
                            .font(CarpenterFont.rowDetail)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
            }

            VerificationPhrase(join.phrase)
                .frame(maxWidth: .infinity)

            join.isAlreadyIn
                ? Text(
                    "You invited them, and this room lets anybody in on an invitation — so nobody was asked to approve and they are already here. This is the one check nothing else does: the same characters were shown to both of you, so if theirs match, the person who joined is the person you meant to invite. If they do not, somebody else used your invitation. Saying so stops you sending them the room's key from now on; it does not remove them, and only you are asked.",
                    bundle: .module
                )
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
                : Text(
                    "Admitting them gives them everything this room has ever held, including what was said before today.",
                    bundle: .module
                )
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)

            if !join.refusedBy.isEmpty {
                Label {
                    Text(
                        "\(ListFormatter.localizedString(byJoining: join.refusedBy.map(\.displayName))) already refused.",
                        bundle: .module
                    )
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(CarpenterFont.footnote)
                .foregroundStyle(palette.secondaryText)
            }

            HStack(spacing: 10) {
                Button {
                    decided = false
                    decisions += 1
                    Task { await onDecide(join, false) }
                } label: {
                    (join.isAlreadyIn
                        ? Text("Does not match", bundle: .module)
                        : Text("Refuse", bundle: .module))
                        .font(CarpenterFont.button)
                        .frame(maxWidth: .infinity, minHeight: CarpenterMetrics.buttonHeight)
                        .background(
                            palette.neutralFill,
                            in: .rect(
                                cornerRadius: CarpenterMetrics.buttonRadius, style: .continuous))
                }
                .foregroundStyle(palette.primaryText)

                Button {
                    decided = true
                    decisions += 1
                    Task { await onDecide(join, true) }
                } label: {
                    (join.isAlreadyIn
                        ? Text("They match", bundle: .module)
                        : Text("Admit", bundle: .module)).primaryAction()
                }
                .prominentActionButton()
            }
        }
        .padding(16)
        .background(
            palette.elevatedSurface,
            in: .rect(cornerRadius: CarpenterMetrics.cardRadius, style: .continuous))
    }
}

#Preview("Waiting") {
    JoinRequestsView(
        roomName: "Hangar 7",
        joins: {
            [PendingJoin(
                id: ParticipantID(rawValue: Data([1])),
                joiner: Member.placeholder(ParticipantID(rawValue: Data([1]))),
                inviter: Member.placeholder(ParticipantID(rawValue: Data([2]))),
                phrase: "K7M2QX",
                expiresAt: .now.addingTimeInterval(86_400)
            )]
        },
        onDecide: { _, _ in }
    )
    .themed(.default)
}

#Preview("Nobody waiting") {
    JoinRequestsView(roomName: "Hangar 7", joins: { [] }, onDecide: { _, _ in })
        .themed(.default)
}
