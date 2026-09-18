import CoreGraphics
import SwiftUI

public enum CarpenterMetrics {
    public static let screenMargin: CGFloat = 20
    public static let rowVerticalPadding: CGFloat = 11
    public static let conversationGutter: CGFloat = 8
    public static let conversationRowPadding: CGFloat = 7
    public static let hairline: CGFloat = 0.5
    public static let mediaOverlayDimming = 0.55

    public static let hitTarget: CGFloat = 44

    // MARK: Bubbles

    public static let bubbleRadius: CGFloat = 20
    public static let bubbleTailRadius: CGFloat = 6
    public static let bubbleMaxWidthFraction: CGFloat = 0.74

    public static func bubbleRadius(forHeight height: CGFloat) -> CGFloat {
        switch height {
        case ..<40: 9
        case ..<64: 14
        default: bubbleRadius
        }
    }

    // MARK: Controls

    public static let mastheadTopInset: CGFloat = 12

    public static let composerControlHeight: CGFloat = 38

    public static let composerSpacing: CGFloat = 9
    public static let composerFieldRadius: CGFloat = composerControlHeight / 2

    public static let cardRadius: CGFloat = 22
    public static let buttonRadius: CGFloat = 14
    public static let buttonHeight: CGFloat = 52

    public static let fieldMinHeight: CGFloat = 46
    public static let fieldRadius: CGFloat = 12
    public static let fieldBorderWidth: CGFloat = 1
    public static let fieldFocusedBorderWidth: CGFloat = 1.5

    public static let readableWidth: CGFloat = 460

    // MARK: Avatars

    public static let roomAvatar: CGFloat = 45
    public static let compactRoomAvatar: CGFloat = 40
    public static let composerAvatar: CGFloat = 40
    public static let messageAvatar: CGFloat = 28

    // MARK: Delivery marks

    public static let deliveryMarkBox: CGFloat = 10
}

extension View {
    public func tappable() -> some View {
        frame(minWidth: CarpenterMetrics.hitTarget, minHeight: CarpenterMetrics.hitTarget)
            .contentShape(Rectangle())
    }
}
