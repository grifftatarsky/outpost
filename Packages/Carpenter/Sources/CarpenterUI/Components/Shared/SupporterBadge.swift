import CarpenterKit
import SwiftUI

public enum AvatarGround: Sendable {
    case background, contentSurface
}

extension EnvironmentValues {
    @Entry public var supporters: Set<ParticipantID> = []

    @Entry public var avatarGround: AvatarGround = .background
}

public struct SupporterBadge: View {
    @Environment(\.palette) private var palette
    @Environment(\.avatarGround) private var ground

    public static let smallestAvatar: CGFloat = 28

    private let avatar: CGFloat

    public init(onAvatarOf diameter: CGFloat) {
        avatar = diameter
    }

    static func size(onAvatarOf diameter: CGFloat) -> CGFloat {
        max(14, (diameter * 0.36).rounded())
    }

    public var body: some View {
        let size = Self.size(onAvatarOf: avatar)
        let ring = max(1.5, size * 0.08)
        Image("SupporterMark", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .padding(size * 0.16)
            .frame(width: size, height: size)
            .background(palette.accentFill, in: .circle)
            .overlay(
                Circle().strokeBorder(
                    ground == .contentSurface ? palette.contentSurface : palette.background, lineWidth: ring))
            .offset(x: size * 0.18, y: size * 0.18)
            .accessibilityHidden(true)
    }
}

extension View {
    public func supporterBadge(_ shown: Bool, onAvatarOf diameter: CGFloat) -> some View {
        overlay(alignment: .bottomTrailing) {
            if shown, diameter >= SupporterBadge.smallestAvatar {
                SupporterBadge(onAvatarOf: diameter)
            }
        }
    }
}

#Preview("Supporter badges") {
    HStack(spacing: 20) {
        ForEach([28.0, 45, 56, 88], id: \.self) { size in
            AvatarView(initials: "GT", diameter: size, isAccented: true)
                .supporterBadge(true, onAvatarOf: size)
        }
    }
    .padding(40)
    .themed(.default)
}
