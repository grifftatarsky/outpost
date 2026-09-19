import CarpenterKit
import SwiftUI

struct RoomRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.personAvatars) private var personAvatars
    @Environment(\.sharedAvatars) private var sharedAvatars
    @Environment(\.clock) private var clock
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.drafts) private var drafts

    let room: RoomSummary
    let organisation: RoomsListOrganisation
    let density: RoomsListDensity
    let marksGroups: Bool
    let isSilenced: Bool
    let showsAvatar: Bool
    var isAwaitingSomebody: Bool = false

    private var avatarDiameter: CGFloat {
        density == .compact ? CarpenterMetrics.compactRoomAvatar : CarpenterMetrics.roomAvatar
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Circle()
                .fill(palette.accentColor)
                .frame(width: 10, height: 10)
                .opacity(room.hasUnread ? 1 : 0)
                .accessibilityLabel(Text("Unread", bundle: .module))
                .accessibilityHidden(!room.hasUnread)
                .padding(.trailing, 8)

            if showsAvatar {
                RoomAvatar(
                    initials: room.initials,
                    diameter: avatarDiameter,
                    isAccented: false,
                    isPinned: organisation.isPinned(room.id),
                    isGroup: marksGroups && !room.isDirect,
                    isSilenced: isSilenced,
                    image: room.partner.flatMap { personAvatars[$0] ?? sharedAvatars[$0] }
                )
                .padding(.trailing, 13)
            }

            VStack(alignment: .leading, spacing: 2) {
                let heading = AnyLayout(
                    typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                )

                heading {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(room.name)
                            .font(CarpenterFont.rowTitle)
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)

                        if !showsAvatar || isAwaitingSomebody {
                            RoomMarks(
                                isSilenced: showsAvatar ? false : isSilenced,
                                isPinned: showsAvatar ? false : organisation.isPinned(room.id),
                                isAwaitingSomebody: isAwaitingSomebody)
                        }

                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    }

                    Text(
                        RelativeTimestampFormatter().roomsList(
                            for: room.lastActivity, now: clock.now)
                    )
                    .font(CarpenterFont.timestamp)
                    .foregroundStyle(palette.timestampText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }

                if density != .compact {
                    detail
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(
                            typeSize.isAccessibilitySize ? 6 : 2,
                            reservesSpace: !typeSize.isAccessibilitySize)
                        .multilineTextAlignment(.leading)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width + CarpenterMetrics.screenMargin }
    }

    private var detail: Text {
        let draft = drafts?.read(.room(room.id)) ?? ""
        if !draft.isEmpty {
            let words = draft.split(whereSeparator: \.isNewline).joined(separator: " ")
            let label = Text("Draft", bundle: .module).foregroundStyle(palette.accentColor).fontWeight(.semibold)
            return Text("\(label) \(words)", bundle: .module, comment: "A conversation's draft in the rooms list: the word Draft, then what was written")
        }
        return room.lastMessage.isEmpty ? Text("No messages yet", bundle: .module) : Text(room.lastMessage)
    }
}
