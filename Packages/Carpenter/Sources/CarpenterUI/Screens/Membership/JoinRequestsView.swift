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
                    // COPY BEGIN d6825c61 [NEEDS HUMAN REVIEW]
                    ContentUnavailableView {
                        Text("Nothing to check", bundle: .module)
                    } description: {
                        Text(
                            "Joins you have not answered, and people who took your invitation, appear here.",
                            bundle: .module)
                    }
                    // COPY END d6825c61
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(joins()) { join in
                                JoinCheckCard(join: join) { admit in
                                    decided = admit
                                    decisions += 1
                                    Task { await onDecide(join, admit) }
                                }
                            }
                        }
                        .padding(.horizontal, CarpenterMetrics.screenMargin)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(palette.background)
            .navigationTitle(roomName)
            // COPY BEGIN fd7f32b1 [NEEDS HUMAN REVIEW]
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close", bundle: .module))
                        .barIconLargeContent(Text("Close", bundle: .module), systemImage: "xmark")
                }
            }
            // COPY END fd7f32b1
        }
        .haptic(.commit, trigger: decisions)
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
