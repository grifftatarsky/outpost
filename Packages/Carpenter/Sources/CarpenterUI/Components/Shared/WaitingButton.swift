import CarpenterKit
import SwiftUI

public struct WaitingButton: View {
    @Environment(\.palette) private var palette

    private let rooms: [RoomSummary]
    private let authors: [Member]
    private let badge: Int
    private let onOpenRoom: (RoomID) -> Void
    private let onOpenOutpost: (ParticipantID) -> Void

    @State private var showing = false

    public init(
        rooms: [RoomSummary],
        authors: [Member],
        badge: Int,
        onOpenRoom: @escaping (RoomID) -> Void,
        onOpenOutpost: @escaping (ParticipantID) -> Void
    ) {
        self.rooms = rooms.filter(\.hasUnread)
        self.authors = authors
        self.badge = badge
        self.onOpenRoom = onOpenRoom
        self.onOpenOutpost = onOpenOutpost
    }

    public var count: Int { rooms.count + authors.count }

    public var body: some View {
        Button { showing.toggle() } label: {
            Label {
                Text("What's waiting", bundle: .module)
            } icon: {
                Image("MailboxMark", bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 14)
                    .overlay(alignment: .topTrailing) { count(badge) }
            }
        }
        .help(Text("What's waiting", bundle: .module))
        .accessibilityValue(badge > 0 ? Text("\(badge) new", bundle: .module) : Text(verbatim: ""))
        .popover(isPresented: $showing, arrowEdge: .bottom) { waiting }
    }

    @ViewBuilder
    private func count(_ number: Int) -> some View {
        if number > 0 {
            Text(verbatim: number > 99 ? "99+" : number.formatted())
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 3.5)
                .frame(minWidth: 13, minHeight: 13)
                .background(Capsule().fill(Color.red))
                .fixedSize()
                .frame(width: 0, height: 0, alignment: .leading)
                .offset(x: -4)
                .accessibilityHidden(true)
        }
    }

    private var waiting: some View {
        List {
            if count == 0 {
                Text("Nothing new.", bundle: .module)
                    .foregroundStyle(palette.secondaryText)
            }
            if !rooms.isEmpty {
                Section {
                    ForEach(rooms) { room in
                        Button {
                            showing = false
                            onOpenRoom(room.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: room.name)
                                    .foregroundStyle(palette.primaryText)
                                if !room.lastMessage.isEmpty {
                                    Text(verbatim: room.lastMessage)
                                        .font(CarpenterFont.rowDetail)
                                        .foregroundStyle(palette.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Rooms", bundle: .module).sectionHeading()
                }
            }
            if !authors.isEmpty {
                Section {
                    ForEach(authors) { author in
                        Button {
                            showing = false
                            onOpenOutpost(author.id)
                        } label: {
                            HStack(spacing: 8) {
                                PersonAvatarView(member: author, diameter: 22, onOutpost: true)
                                Text(verbatim: author.displayName)
                                    .foregroundStyle(palette.primaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Outposts", bundle: .module).sectionHeading()
                }
            }
        }
        .frame(width: 300, height: height)
    }

    private var height: CGFloat {
        let headers = (rooms.isEmpty ? 0 : 1) + (authors.isEmpty ? 0 : 1)
        let lines = CGFloat(rooms.count) * 46 + CGFloat(authors.count) * 34 + CGFloat(headers) * 30
        return min(440, max(64, lines + 24))
    }
}
