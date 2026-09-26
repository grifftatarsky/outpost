import CarpenterKit
import SwiftUI

struct ConversationPreview: View {
    @Environment(\.palette) private var palette
    @Environment(\.personAvatars) private var personAvatars
    @Environment(\.sharedAvatars) private var sharedAvatars

    let room: RoomSummary
    let messages: [Message]

    private static let depth = 6

    private var recent: [Message] {
        Array(messages.suffix(Self.depth))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // COPY BEGIN e4786798 [NEEDS HUMAN REVIEW]
            if recent.isEmpty {
                Text("No messages yet.", bundle: .module)
                    .font(CarpenterFont.footnote)
                    .foregroundStyle(palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ConversationLayout.runs(from: recent)) { run in
                        MessageRunView(run: run)
                            .padding(.bottom, 6)
                    }
                }
            }
            // COPY END e4786798
        }
        .padding(14)
        .frame(width: 300)
        .background(palette.background)
    }

    private var header: some View {
        HStack(spacing: 9) {
            AvatarView(
                initials: room.initials, diameter: 26,
                image: room.partner.flatMap { personAvatars[$0] ?? sharedAvatars[$0] })
            Text(room.name)
                .font(CarpenterFont.rowTitle)
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
