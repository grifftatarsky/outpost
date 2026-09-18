import SwiftUI

public enum CarpenterFont {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let navigationTitle = Font.headline

    public static let rowTitle = Font.headline
    public static let rowDetail = Font.subheadline
    public static let timestamp = Font.subheadline

    public static let bubble = Font.body
    public static let postBody = Font.body
    public static let postAuthor = Font.callout.weight(.semibold)
    public static let postDetail = Font.footnote

    public static let comment = Font.subheadline

    public static let button = Font.headline
    public static let footnote = Font.footnote
    public static let caption = Font.caption
    public static let micro = Font.caption2
    public static let badge = Font.caption.weight(.semibold)
    public static let sectionLabel = Font.caption2.weight(.semibold)

    public static func avatar(diameter: CGFloat) -> Font {
        Font.system(size: diameter * 0.37, weight: .semibold)
    }
}
