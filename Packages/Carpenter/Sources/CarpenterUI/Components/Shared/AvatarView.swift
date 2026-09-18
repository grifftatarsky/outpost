import CarpenterKit
import SwiftUI

public struct AvatarView: View {
    @Environment(\.palette) private var palette

    private let initials: String
    private let diameter: CGFloat
    private let isAccented: Bool
    private let usesStrongFill: Bool
    private let image: Image?
    private let symbol: String?

    public init(
        initials: String,
        diameter: CGFloat,
        isAccented: Bool = false,
        usesStrongFill: Bool = false,
        image: Image? = nil,
        symbol: String? = nil
    ) {
        self.initials = initials
        self.diameter = diameter
        self.isAccented = isAccented
        self.usesStrongFill = usesStrongFill
        self.image = image
        self.symbol = symbol
    }

    public var body: some View {
        Circle()
            .fill(fill)
            .frame(width: diameter, height: diameter)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(.circle)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: diameter * 0.46, weight: .semibold))
                        .foregroundStyle(palette.textOnAccent)
                } else {
                    Text(initials)
                        .font(CarpenterFont.avatar(diameter: diameter))
                        .foregroundStyle(foreground)
                }
            }
            .accessibilityHidden(true)
    }

    private var fill: Color {
        if symbol != nil { return palette.accentColor }
        if isAccented { return palette.accentTint }
        return usesStrongFill ? palette.avatarFillStrong : palette.avatarFill
    }

    private var foreground: Color {
        isAccented ? palette.accentColor : palette.neutralText
    }
}

#Preview("Avatars") {
    VStack(spacing: 24) {
        HStack(spacing: 12) {
            AvatarView(initials: "ZE", diameter: 52, isAccented: true)
            AvatarView(initials: "CA", diameter: 52)
            AvatarView(initials: "H", diameter: 28, usesStrongFill: true)
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .themed(.cobalt)
}

public struct PersonAvatarView: View {
    @Environment(\.personAvatars) private var personAvatars
    @Environment(\.sharedAvatars) private var sharedAvatars
    @Environment(\.outpostAvatars) private var outpostAvatars
    @Environment(\.ownAvatar) private var ownAvatar
    @Environment(\.ownOutpostAvatar) private var ownOutpostAvatar
    @Environment(\.viewerID) private var viewerID
    @Environment(\.anonFace) private var anonFace
    @Environment(\.supporters) private var supporters

    private let member: Member
    private let diameter: CGFloat
    private let isAccented: Bool
    private let usesStrongFill: Bool
    private let onOutpost: Bool

    public init(
        member: Member, diameter: CGFloat, isAccented: Bool = false, usesStrongFill: Bool = false,
        onOutpost: Bool = false
    ) {
        self.member = member
        self.diameter = diameter
        self.isAccented = isAccented
        self.usesStrongFill = usesStrongFill
        self.onOutpost = onOutpost
    }

    private var drawn: Image? {
        switch avatarSource(
            isViewer: viewerID != nil && member.id == viewerID,
            onOutpost: onOutpost,
            hasOwn: ownAvatar != nil,
            hasOwnOutpost: ownOutpostAvatar != nil,
            hasChosen: personAvatars[member.id] != nil,
            hasOutpost: outpostAvatars[member.id] != nil,
            hasRooms: sharedAvatars[member.id] != nil)
        {
        case .own: return ownAvatar
        case .ownOutpost: return ownOutpostAvatar
        case .chosen: return personAvatars[member.id]
        case .outpost: return outpostAvatars[member.id]
        case .rooms: return sharedAvatars[member.id]
        case .monogram: return nil
        }
    }

    public var body: some View {
        AvatarView(
            initials: member.initials, diameter: diameter, isAccented: isAccented,
            usesStrongFill: usesStrongFill,
            image: drawn,
            symbol: member.isAnonymous ? anonFace.symbol : nil)
        .supporterBadge(!member.isAnonymous && supporters.contains(member.id), onAvatarOf: diameter)
    }
}
