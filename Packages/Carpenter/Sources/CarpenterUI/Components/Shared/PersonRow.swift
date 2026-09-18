import CarpenterKit
import SwiftUI

public struct PersonRow<Accessory: View>: View {
    @Environment(\.palette) private var palette

    @Environment(\.personAvatars) private var personAvatars
    @Environment(\.sharedAvatars) private var sharedAvatars

    private let name: String
    private let initials: String
    private let id: ParticipantID?
    private let detail: Text?
    private let diameter: CGFloat
    private let accessory: Accessory

    public init(
        name: String,
        initials: String,
        id: ParticipantID? = nil,
        detail: Text? = nil,
        diameter: CGFloat = CarpenterMetrics.messageAvatar,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.name = name
        self.initials = initials
        self.id = id
        self.detail = detail
        self.diameter = diameter
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                initials: initials, diameter: diameter,
                image: id.flatMap { personAvatars[$0] ?? sharedAvatars[$0] })
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(CarpenterFont.rowTitle)
                    .foregroundStyle(palette.primaryText)
                if let detail {
                    detail
                        .font(CarpenterFont.rowDetail)
                        .foregroundStyle(palette.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .accessibilityElement(children: .combine)
        .contentShape(.rect)
    }
}

public extension PersonRow where Accessory == EmptyView {
    init(_ connection: Connection, detail: Text? = nil) {
        self.init(
            name: connection.person.displayName,
            initials: connection.person.initials,
            id: connection.person.id,
            detail: detail)
    }
}

#if DEBUG
    #Preview("People") {
        List {
            Section {
                PersonRow(
                    name: "Zeppelin Enthusiasts", initials: "ZE",
                    detail: Text(verbatim: "In 2 rooms")
                ) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                }
                PersonRow(name: "C0C2 7894", initials: "C", detail: Text(verbatim: "Outpost only"))
                PersonRow(name: "Hana", initials: "H")
            }
        }
        .themed(.default)
    }
#endif
