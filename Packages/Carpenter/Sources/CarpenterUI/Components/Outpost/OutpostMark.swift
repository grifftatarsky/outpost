import CarpenterKit
import SwiftUI

public struct OutpostMark: View {
    @Environment(\.palette) private var palette

    private let width: CGFloat
    private let tint: Color?

    public init(width: CGFloat, tint: Color? = nil) {
        self.width = width
        self.tint = tint
    }

    public var body: some View {
        Image("OutpostLogo", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: width)
            .foregroundStyle(tint ?? palette.primaryText)
            .accessibilityLabel(Text(verbatim: Branding.displayName))
    }
}

#if DEBUG
    #Preview("The mark, tinted every way") {
        VStack(spacing: 28) {
            OutpostMark(width: 220)
            OutpostMark(width: 220, tint: .accentColor)
        }
        .padding(40)
        .themed(.cobalt)
    }
#endif
